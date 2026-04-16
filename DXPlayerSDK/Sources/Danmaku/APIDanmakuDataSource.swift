import Foundation
import UIKit

/// 后端 API 弹幕数据源（轮询模式）
/// GET /danmu/list?video_id=123&from=0&to=60
/// POST /danmu/send { video_id, time, text, color }
public class APIDanmakuDataSource: DanmakuDataSource {

    // MARK: - DanmakuDataSource

    public var sourceType: DanmakuSourceType { .timeline }
    public weak var delegate: DanmakuDataSourceDelegate?

    // MARK: - 配置

    private let baseURL: String
    private var videoId: Int = 0
    private var pollingInterval: TimeInterval = 30
    private let prefetchWindow: TimeInterval = 60
    private let prefetchAhead: TimeInterval = 30

    // MARK: - 状态

    private var pollingTimer: Timer?
    private var lastFetchedTo: TimeInterval = 0
    private var allItems: [DanmakuItem] = []
    private var existingIds: Set<String> = []
    private var getCurrentPosition: (() -> TimeInterval)?

    // MARK: - Init

    /// - Parameters:
    ///   - baseURL: API 基础 URL（如 https://api.example.com）
    ///   - pollingInterval: 轮询间隔（秒），默认 30
    public init(baseURL: String, pollingInterval: TimeInterval = 30) {
        self.baseURL = baseURL
        self.pollingInterval = pollingInterval
    }

    deinit { stop() }

    // MARK: - DanmakuDataSource 方法

    public func start(context: [String: Any]) {
        videoId = context["video_id"] as? Int ?? 0
        getCurrentPosition = context["getCurrentPosition"] as? (() -> TimeInterval)
        lastFetchedTo = 0
        allItems.removeAll()
        existingIds.removeAll()

        // 立即预载第一段
        pollOnce()
        // 定时轮询
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

    public func send(text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let currentTime = getCurrentPosition?() ?? 0
        let urlStr = "\(baseURL)/danmu/send"
        guard let url = URL(string: urlStr) else {
            completion(.failure(NSError(domain: "DanmakuAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效 URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["video_id": videoId, "time": currentTime, "text": text, "color": "#ffffff"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("❌ [弹幕API] 发送失败: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            print("✅ [弹幕API] 发送成功: \(text)")
            DispatchQueue.main.async { completion(.success(())) }
        }.resume()
    }

    public func fetchDanmaku(from startTime: TimeInterval, to endTime: TimeInterval, completion: @escaping (Result<[DanmakuItem], Error>) -> Void) {
        // 從內存快取過濾，供 DanmakuManager 時間同步計時器使用
        // 預載由 pollOnce() 獨立完成
        let filtered = allItems.filter { item in
            guard let ts = item.timestamp else { return false }
            return ts >= startTime && ts < endTime
        }
        DispatchQueue.main.async { completion(.success(filtered)) }
    }

    // MARK: - 轮询

    private func pollOnce() {
        let pos = getCurrentPosition?() ?? 0
        let from = lastFetchedTo > 0 ? lastFetchedTo : pos
        let to = pos + prefetchWindow + prefetchAhead
        guard to > lastFetchedTo else { return }

        fetchFromServer(from: from, to: to) { [weak self] result in
            if case .success(let items) = result, !items.isEmpty {
                self?.lastFetchedTo = to
            }
        }
    }

    /// 從後端拉取指定時間段的彈幕並存入快取（不觸發 delegate 顯示）
    private func fetchFromServer(from startTime: TimeInterval, to endTime: TimeInterval, completion: @escaping (Result<[DanmakuItem], Error>) -> Void) {
        let urlStr = "\(baseURL)/danmu/list?video_id=\(videoId)&from=\(Int(startTime))&to=\(Int(endTime))"
        guard let url = URL(string: urlStr) else {
            completion(.failure(NSError(domain: "DanmakuAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效 URL"])))
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error {
                print("❌ [弹幕API] 预载失败: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                DispatchQueue.main.async { completion(.success([])) }
                return
            }

            var newItems: [DanmakuItem] = []
            for json in jsonArray {
                let id = json["id"] as? String ?? UUID().uuidString
                guard !self.existingIds.contains(id) else { continue }
                let text = json["text"] as? String ?? ""
                let time = json["time"] as? TimeInterval ?? 0
                let colorStr = json["color"] as? String ?? "#ffffff"
                let color = self.parseColor(colorStr)
                let item = DanmakuItem(id: id, text: text, color: color, timestamp: time)
                newItems.append(item)
                self.existingIds.insert(id)
            }

            self.allItems.append(contentsOf: newItems)
            print("✅ [弹幕API] 预载 \(newItems.count) 条 (总计 \(self.allItems.count))")

            DispatchQueue.main.async { completion(.success(newItems)) }
        }.resume()
    }

    // MARK: - Helpers

    private func parseColor(_ hex: String) -> UIColor {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }
        guard hexStr.count == 6, let rgb = UInt32(hexStr, radix: 16) else { return .white }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
