import Foundation
import UIKit

/// 后端 API 弹幕数据源（HTTP 轮询模式，点播专用）
///
/// 接口规范：
///   GET  /api/danmu/video?video_id=X&time=Y(ms)   — 查询点播弹幕（无需认证）
///   POST /api/danmu/send                           — 发送弹幕（需要认证）
///
/// Context 参数（start(context:) 传入）：
///   - "video_id":           Int    — 视频 ID（必填）
///   - "oauth_id":           String — 用户 OAuth ID（发送弹幕时必填）
///   - "token":              String — JWT Token（传入后通过 X-Auth-Token 发送；不传则 debug 模式）
///   - "getCurrentPosition": () -> TimeInterval — 获取当前播放位置（秒，必填）
public class APIDanmakuDataSource: DanmakuDataSource {

    // MARK: - DanmakuDataSource

    public var sourceType: DanmakuSourceType { .timeline }
    public weak var delegate: DanmakuDataSourceDelegate?

    // MARK: - 配置

    private let baseURL: String
    private var videoId: Int = 0
    private var oauthId: String = ""
    private var token: String?
    private var pollingInterval: TimeInterval

    // MARK: - 状态

    private var pollingTimer: Timer?
    /// 已缓存的全部弹幕（按 timestamp 排列）
    private var allItems: [DanmakuItem] = []
    /// 已接收 dmid 集合，用于去重
    private var receivedDmids: Set<String> = []
    private var getCurrentPosition: (() -> TimeInterval)?

    // MARK: - Init

    /// - Parameters:
    ///   - baseURL: API 基础 URL，如 `http://47.236.181.171:80`
    ///   - pollingInterval: 轮询间隔（秒），默认 5 秒（服务端每次返回 10 秒窗口）
    public init(baseURL: String, pollingInterval: TimeInterval = 5) {
        self.baseURL = baseURL
        self.pollingInterval = pollingInterval
    }

    deinit { stop() }

    // MARK: - DanmakuDataSource 方法

    public func start(context: [String: Any]) {
        videoId = context["video_id"] as? Int ?? 0
        oauthId = context["oauth_id"] as? String ?? ""
        token = context["token"] as? String
        getCurrentPosition = context["getCurrentPosition"] as? (() -> TimeInterval)

        allItems.removeAll()
        receivedDmids.removeAll()

        // 立即拉取一次
        pollOnce()

        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
        if let timer = pollingTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        print("🔄 [弹幕API] 启动轮询, videoId=\(videoId), 间隔=\(pollingInterval)s")
    }

    public func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        print("⏹ [弹幕API] 停止轮询")
    }

    /// 发送弹幕 — POST /api/danmu/send
    public func send(text: String, mode: DanmakuMode = .scroll, color: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        let currentPositionSec = getCurrentPosition?() ?? 0
        let videoTimeMs = Int64(currentPositionSec * 1000)

        let urlStr = "\(baseURL)/api/danmu/send"
        guard let url = URL(string: urlStr) else {
            completion(.failure(makeError(-1, "无效 URL")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 认证：有 token 则放 Header，否则 debug 模式将 oauth_id 放 Body
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
        // debug 模式：同时传 oauth_type 占位，方便服务端识别
        if token == nil {
            body["oauth_type"] = "debug"
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ [弹幕API] 发送网络错误: \(error.localizedDescription)")
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
                    print("✅ [弹幕API] 发送成功: \(text)")
                    completion(.success(()))
                } else {
                    let errmsg = json["errmsg"] as? String ?? "未知错误"
                    let userMsg = self.sendErrorMessage(errno: errno, fallback: errmsg)
                    print("❌ [弹幕API] 发送失败 errno=\(errno): \(errmsg)")
                    completion(.failure(self.makeError(errno, userMsg)))
                }
            }
        }.resume()
    }

    /// 供 DanmakuManager 时间同步计时器调用：从内存缓存中按秒过滤
    public func fetchDanmaku(from startTime: TimeInterval, to endTime: TimeInterval, completion: @escaping (Result<[DanmakuItem], Error>) -> Void) {
        let filtered = allItems.filter { item in
            guard let ts = item.timestamp else { return false }
            return ts >= startTime && ts < endTime
        }
        completion(.success(filtered))
    }

    // MARK: - 轮询

    private func pollOnce() {
        let positionSec = getCurrentPosition?() ?? 0
        let timeMs = Int64(positionSec * 1000)
        fetchFromServer(timeMs: timeMs)
    }

    /// 拉取 [timeMs, timeMs+10000ms] 窗口的弹幕并存入缓存
    private func fetchFromServer(timeMs: Int64) {
        let urlStr = "\(baseURL)/api/danmu/video?video_id=\(videoId)&time=\(timeMs)"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ [弹幕API] 轮询失败: \(error.localizedDescription)")
                return
            }
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let errno = root["errno"] as? Int, errno == 0,
                  let dataDict = root["data"] as? [String: Any],
                  let list = dataDict["list"] as? [[String: Any]] else {
                return
            }

            var newItems: [DanmakuItem] = []
            for json in list {
                let dmid = json["dmid"] as? String ?? UUID().uuidString
                guard !self.receivedDmids.contains(dmid) else { continue }
                self.receivedDmids.insert(dmid)

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

            if !newItems.isEmpty {
                self.allItems.append(contentsOf: newItems)
                // 按 timestamp 排序，保证时间同步计时器能顺序匹配
                self.allItems.sort { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
                print("✅ [弹幕API] 缓存 +\(newItems.count) 条（总计 \(self.allItems.count)，time=\(timeMs)ms）")
            }
        }.resume()
    }

    // MARK: - 辅助

    private func makeError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "DanmakuAPI", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - 用户设置接口

    /// 获取用户弹幕设置（GET /api/danmu/setting）
    ///
    /// 需在 `start(context:)` 传入 token 后调用，否则服务端返回未登录错误。
    public func fetchSetting(completion: @escaping (Result<DanmakuUserSetting, Error>) -> Void) {
        let urlStr = "\(baseURL)/api/danmu/setting"
        guard let url = URL(string: urlStr) else {
            completion(.failure(makeError(-1, "无效 URL")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = token {
            request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        }

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
                guard errno == 0 else {
                    let errmsg = json["errmsg"] as? String ?? "未知错误"
                    completion(.failure(self.makeError(errno, errmsg)))
                    return
                }
                guard let dataDict = json["data"] as? [String: Any] else {
                    completion(.failure(self.makeError(-3, "data 字段缺失")))
                    return
                }
                let rawColor = dataDict["color"] as? String ?? ""
                let setting = DanmakuUserSetting(
                    color: rawColor.isEmpty ? nil : rawColor,
                    vipLevel: dataDict["vip_level"] as? Int ?? 0,
                    isUper: (dataDict["is_uper"] as? Int ?? 0) == 1,
                    disturbKeywords: dataDict["disturb_kw"] as? [String] ?? [],
                    receiveLevel: dataDict["receive_level"] as? Int ?? 0
                )
                print("✅ [弹幕API] 获取设置成功 - color:\(setting.color ?? "nil") vip:\(setting.vipLevel) isUper:\(setting.isUper)")
                completion(.success(setting))
            }
        }.resume()
    }

    /// 更新用户弹幕设置（POST /api/danmu/setting）
    ///
    /// `update` 中 nil 字段不会发送，传 `color: ""` 可清除颜色设置。
    public func updateSetting(_ update: DanmakuUserSettingUpdate, completion: @escaping (Result<Void, Error>) -> Void) {
        let urlStr = "\(baseURL)/api/danmu/setting"
        guard let url = URL(string: urlStr) else {
            completion(.failure(makeError(-1, "无效 URL")))
            return
        }

        var body: [String: Any] = [:]
        if let color = update.color { body["color"] = color }
        if let keywords = update.disturbKeywords { body["disturb_kw"] = keywords }
        if let level = update.receiveLevel { body["receive_level"] = level }

        guard !body.isEmpty else {
            completion(.success(()))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        }
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
                    print("✅ [弹幕API] 更新设置成功")
                    completion(.success(()))
                } else {
                    let errmsg = json["errmsg"] as? String ?? "未知错误"
                    completion(.failure(self.makeError(errno, errmsg)))
                }
            }
        }.resume()
    }

    /// 将服务端 errno 映射为用户可读错误信息
    private func sendErrorMessage(errno: Int, fallback: String) -> String {
        switch errno {
        // 弹幕业务错误码（301xx）
        case 30102: return "发送太快，请稍后再试"
        case 30103: return "请勿发送重复内容"
        case 30104: return "内容包含敏感词，请修改后重试"
        case 30105: return "身份校验失败，请重新登录"
        case 30109: return "弹幕模式无效"
        case 30110: return "颜色格式无效，请使用 #RRGGBB 格式"
        case 30111: return "该颜色为保留色，不可使用"
        case 30112: return "您已被屏蔽，请联系管理员"
        case 30116: return "该颜色需要对应 VIP 等级才能使用"
        case 30117: return "过滤模式无效"
        // 认证错误码（10xxx）
        case 10007: return "认证已过期，请重新登录"
        case 10008: return "未登录，无法发送弹幕"
        case 10010: return "请先登录"
        case 10011: return "权限不足"
        // 服务端异常（101xx）
        case 10101: return "弹幕发送失败，请稍后重试"
        case 10102: return "弹幕查询失败，请稍后重试"
        case 10103: return "连接失败，请检查网络"
        default:    return fallback
        }
    }
}
