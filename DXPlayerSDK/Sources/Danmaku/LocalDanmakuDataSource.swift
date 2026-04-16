import Foundation

/// 本地模式資料來源（用於測試）
public class LocalDanmakuDataSource: DanmakuDataSource {

    // MARK: - DanmakuDataSource 屬性

    public var sourceType: DanmakuSourceType { return .local }
    public weak var delegate: DanmakuDataSourceDelegate?

    // MARK: - 屬性

    private var mockDanmakus: [DanmakuItem] = []
    private var timer: Timer?

    // MARK: - 初始化

    public init() {}

    deinit {
        stop()
    }

    // MARK: - DanmakuDataSource 方法

    public func start(context: [String: Any]) {
        DXPlayerLogger.info("🎬 [本地彈幕] 啟動本地彈幕資料來源")

        // 產生模擬資料
        generateMockDanmakus()

        // 模擬定時接收彈幕
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sendRandomDanmaku()
        }
    }

    public func stop() {
        DXPlayerLogger.info("⏹️ [本地彈幕] 停止本地彈幕資料來源")
        timer?.invalidate()
        timer = nil
    }

    public func send(text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // 模擬發送成功
        // 注意：不要在這裡調用 delegate?.dataSource(self, didReceive:)
        // 因為 DanmakuManager.sendDanmaku 已經在本地顯示了彈幕，避免重複
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            DXPlayerLogger.info("📤 [本地彈幕] 模擬發送成功: \(text)")
            completion(.success(()))
        }
    }

    public func fetchDanmaku(from startTime: TimeInterval, to endTime: TimeInterval, completion: @escaping (Result<[DanmakuItem], Error>) -> Void) {
        let filtered = mockDanmakus.filter { danmaku in
            guard let timestamp = danmaku.timestamp else { return false }
            return timestamp >= startTime && timestamp < endTime
        }
        completion(.success(filtered))
    }

    // MARK: - 私有方法

    private func generateMockDanmakus() {
        let texts = [
            "精彩！", "太棒了！", "主播加油！", "XDDD", "哈哈哈哈",
            "这段好看", "来了来了", "666", "刷起来", "支持支持",
            "弹幕测试", "真不错", "学到了", "感谢分享", "继续继续",
            "厉害厉害", "牛逼", "👍", "🔥", "😂",
            "好看好看", "有意思", "很棒", "赞赞赞", "加油加油"
        ]

        mockDanmakus = (0..<100).map { index in
            DanmakuItem(
                id: "mock_\(index)",
                text: texts.randomElement()!,
                timestamp: TimeInterval(index * 5)
            )
        }

        DXPlayerLogger.info("📝 [本地彈幕] 生成 \(mockDanmakus.count) 條模擬彈幕")
    }

    private func sendRandomDanmaku() {
        guard let danmaku = mockDanmakus.randomElement() else { return }

        // 隨機顏色（10% 機率）
        var randomDanmaku = danmaku
        if Int.random(in: 0..<10) == 0 {
            let colors: [UIColor] = [.red, .green, .blue, .yellow, .cyan, .magenta]
            randomDanmaku = DanmakuItem(
                text: danmaku.text,
                color: colors.randomElement() ?? .white
            )
        }

        delegate?.dataSource(self, didReceive: randomDanmaku)
    }
}
