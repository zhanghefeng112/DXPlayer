import Foundation
import UIKit

/// 点播 WebSocket 弹幕数据源（iOS 13+）
///
/// 通信模式：双向
///   - 客户端每秒上报 {"video_time": ms}（暂停时位置不变则不上报）
///   - 服务端推送 {"type":"danmu","data":{"list":[...],"total":N}}
///
/// 接口：WS /ws/video/:video_id?token=xxx  或  ?oauth_id=xxx（debug）
///
/// Context 参数（start(context:) 传入）：
///   - "video_id":           Int    — 视频 ID（必填）
///   - "oauth_id":           String — debug 模式用户 ID（不传 token 时必填）
///   - "token":              String — JWT Token（优先使用）
///   - "getCurrentPosition": () -> TimeInterval — 当前播放位置（秒，必填）
@available(iOS 13.0, *)
public class WSVideoDanmakuDataSource: DanmakuDataSource {

    // MARK: - DanmakuDataSource

    /// 实时模式：弹幕通过 delegate 推送，DanmakuManager 不启动时间同步计时器
    public var sourceType: DanmakuSourceType { .realtime }
    public weak var delegate: DanmakuDataSourceDelegate?

    // MARK: - 配置

    private let baseURL: String
    private var videoId: Int = 0
    private var oauthId: String = ""
    private var token: String?
    private var getCurrentPosition: (() -> TimeInterval)?

    // MARK: - WebSocket 状态

    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var isRunning = false

    // MARK: - 上报计时器

    private var reportingTimer: Timer?
    private var lastReportedMs: Int64 = -1

    // MARK: - 连接状态追踪

    private var hasReceivedFirstMessage = false

    // MARK: - 去重

    private var receivedDmids: Set<String> = []

    // MARK: - 重连

    private var reconnectTimer: Timer?
    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 30

    // MARK: - Init

    /// - Parameter baseURL: HTTP 基础 URL，如 `http://47.236.181.171:80`（自动推导 WS 地址）
    public init(baseURL: String) {
        self.baseURL = baseURL
    }

    deinit { stop() }

    // MARK: - DanmakuDataSource 方法

    public func start(context: [String: Any]) {
        videoId = context["video_id"] as? Int ?? 0
        oauthId = context["oauth_id"] as? String ?? ""
        token = context["token"] as? String
        getCurrentPosition = context["getCurrentPosition"] as? (() -> TimeInterval)

        receivedDmids.removeAll()
        reconnectAttempt = 0
        hasReceivedFirstMessage = false
        isRunning = true

        connect()
        print("🔌 [WS点播] 启动, videoId=\(videoId)")
    }

    public func stop() {
        isRunning = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        stopReporting()
        disconnect()
        print("⏹ [WS点播] 停止")
    }

    /// 发送弹幕 — POST /api/danmu/send（HTTP，与接收的 WS 通道无关）
    public func send(text: String, mode: DanmakuMode = .scroll, color: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        let positionSec = getCurrentPosition?() ?? 0
        let videoTimeMs = Int64(positionSec * 1000)

        let urlStr = "\(baseURL)/api/danmu/send"
        guard let url = URL(string: urlStr) else {
            completion(.failure(makeError(-1, "无效 URL")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        }

        var body: [String: Any] = [
            "type": "video",
            "oauth_id": oauthId,
            "video_id": videoId,
            "video_time": videoTimeMs,
            "content": text,
            "mode": mode.rawValue
        ]
        if let color = color { body["color"] = color }
        if token == nil { body["oauth_type"] = "debug" }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let errno = json["errno"] as? Int else {
                    completion(.failure(self.makeError(-2, "响应解析失败")))
                    return
                }
                if errno == 0 {
                    completion(.success(()))
                } else {
                    let errmsg = json["errmsg"] as? String ?? "未知错误"
                    completion(.failure(self.makeError(errno, self.sendErrorMessage(errno: errno, fallback: errmsg))))
                }
            }
        }.resume()
    }

    /// WS 实时模式下此方法不使用（返回空列表）
    public func fetchDanmaku(from startTime: TimeInterval, to endTime: TimeInterval, completion: @escaping (Result<[DanmakuItem], Error>) -> Void) {
        completion(.success([]))
    }

    // MARK: - 连接管理

    private func connect() {
        guard isRunning else { return }

        let wsBase = baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")

        var urlStr: String
        if let token = token {
            urlStr = "\(wsBase)/ws/video/\(videoId)?token=\(token)"
        } else {
            urlStr = "\(wsBase)/ws/video/\(videoId)?oauth_id=\(oauthId)"
        }

        guard let url = URL(string: urlStr) else {
            print("❌ [WS点播] 无效 URL: \(urlStr)")
            return
        }

        urlSession = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.dataSource(self!, didChangeConnectionState: .connecting)
        }

        receive()
        startReporting()
        print("🔌 [WS点播] 正在连接: \(urlStr)")
    }

    private func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    // MARK: - 接收消息

    private func receive() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self, self.isRunning else { return }

            switch result {
            case .success(let message):
                if !hasReceivedFirstMessage {
                    hasReceivedFirstMessage = true
                    print("✅ [WS点播] 连接成功")
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.dataSource(self, didChangeConnectionState: .connected)
                    }
                }
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // 继续监听下一条消息
                self.receive()

            case .failure(let error):
                print("❌ [WS点播] 连接断开: \(error.localizedDescription)")
                self.handleDisconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = root["type"] as? String, type == "danmu",
              let dataDict = root["data"] as? [String: Any],
              let list = dataDict["list"] as? [[String: Any]] else {
            return
        }

        var newItems: [DanmakuItem] = []
        for json in list {
            let dmid = json["dmid"] as? String ?? UUID().uuidString
            guard !receivedDmids.contains(dmid) else { continue }
            receivedDmids.insert(dmid)

            let content = json["content"] as? String ?? ""
            let videoTimeMs = json["video_time"] as? Int64 ?? 0
            let sendTimeMs = json["send_time"] as? Int64
            let modeStr = json["mode"] as? String ?? "scroll"
            let mode = DanmakuMode(rawValue: modeStr) ?? .scroll
            let colorHex = json["color"] as? String
            let color = colorHex.flatMap { UIColor.danmaku_fromHex($0) } ?? .white
            let title = json["title"] as? String

            let item = DanmakuItem(
                id: dmid,
                text: content,
                userId: json["oauth_id"] as? String,
                color: color,
                mode: mode,
                title: title,
                timestamp: TimeInterval(videoTimeMs) / 1000.0,
                sendTime: sendTimeMs
            )
            newItems.append(item)
        }

        guard !newItems.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.dataSource(self, didReceive: newItems)
        }

        if reconnectAttempt > 0 {
            reconnectAttempt = 0
        }
    }

    // MARK: - 上报进度

    private func startReporting() {
        stopReporting()
        lastReportedMs = -1
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.reportCurrentTime()
        }
        RunLoop.main.add(timer, forMode: .common)
        reportingTimer = timer
    }

    private func stopReporting() {
        reportingTimer?.invalidate()
        reportingTimer = nil
    }

    private func reportCurrentTime() {
        guard let pos = getCurrentPosition?() else { return }
        let ms = Int64(pos * 1000)
        // 位置未变（暂停中）不重复上报，节省带宽
        guard ms != lastReportedMs else { return }
        lastReportedMs = ms

        let msg = "{\"video_time\": \(ms)}"
        webSocketTask?.send(.string(msg)) { [weak self] error in
            if let error = error {
                print("❌ [WS点播] 上报失败: \(error.localizedDescription)")
            } else {
                print("📤 [WS点播] 上报 video_time=\(ms)ms")
                guard let self = self else { return }
                if !self.hasReceivedFirstMessage {
                    self.hasReceivedFirstMessage = true
                    print("✅ [WS点播] 连接成功（首次上报成功）")
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.dataSource(self, didChangeConnectionState: .connected)
                    }
                }
            }
        }
    }

    // MARK: - 重连

    private func handleDisconnect() {
        stopReporting()
        disconnect()
        hasReceivedFirstMessage = false

        guard isRunning else { return }

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.dataSource(self!, didChangeConnectionState: .reconnecting)
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        reconnectAttempt += 1
        print("🔄 [WS点播] \(Int(delay))s 后重连（第\(reconnectAttempt)次）")

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }

    // MARK: - 辅助

    private func makeError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "WSVideoDanmaku", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func sendErrorMessage(errno: Int, fallback: String) -> String {
        switch errno {
        case 30102: return "发送太快，请稍后再试"
        case 30103: return "请勿发送重复内容"
        case 30104: return "内容包含敏感词，请修改后重试"
        case 30105: return "身份校验失败，请重新登录"
        case 30109: return "弹幕模式无效"
        case 30110: return "颜色格式无效，请使用 #RRGGBB 格式"
        case 30111: return "该颜色为保留色，不可使用"
        case 30112: return "您已被屏蔽，请联系管理员"
        case 30116: return "该颜色需要对应 VIP 等级才能使用"
        case 10007: return "认证已过期，请重新登录"
        case 10008: return "未登录，无法发送弹幕"
        case 10101: return "弹幕发送失败，请稍后重试"
        default:    return fallback
        }
    }
}
