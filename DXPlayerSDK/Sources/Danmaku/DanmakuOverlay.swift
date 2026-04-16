import UIKit

/// 彈幕覆蓋層
class DanmakuOverlay: UIView {

    // MARK: - 屬性

    /// 當前設定
    private var currentSettings: DanmakuSettings = .default

    /// 軌道資訊
    private var tracks: [DanmakuTrack] = []

    /// 彈幕佇列
    private var danmakuQueue: [DanmakuItem] = []
    private let maxQueueSize = 100

    /// 彈幕池（複用機制）
    private var danmakuPool: [DanmakuLabel] = []
    private let maxPoolSize = 50

    /// 渲染計時器
    private var displayLink: CADisplayLink?

    /// 是否啟用
    private var isEnabled: Bool = true

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        stopRendering()
    }

    // MARK: - UI 設置

    private func setupUI() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        // 初始化軌道
        setupTracks(count: currentSettings.displayLines)

        // 啟動渲染
        startRendering()
    }

    // MARK: - 公共方法

    /// 添加彈幕到佇列
    func enqueueDanmaku(_ danmaku: DanmakuItem) {
        // 如果佇列已滿，丟棄最舊的彈幕
        if danmakuQueue.count >= maxQueueSize {
            danmakuQueue.removeFirst()
            DXPlayerLogger.warning("⚠️ [彈幕] 佇列已滿，丟棄最舊彈幕")
        }

        danmakuQueue.append(danmaku)
    }

    /// 更新設定
    func applySettings(_ settings: DanmakuSettings) {
        let oldLineCount = currentSettings.displayLines
        currentSettings = settings
        isEnabled = settings.isEnabled

        // 如果行數變化，重新設置軌道
        if oldLineCount != settings.displayLines {
            setupTracks(count: settings.displayLines)
        }

        // 更新現有彈幕的樣式
        updateExistingDanmakus()
    }

    /// 設定是否啟用
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            // 關閉時：立即清除畫面上的彈幕給用戶明確反饋，但保留佇列
            clearVisibleDanmakus()
        }
        // 開啟時：processQueue 會繼續從佇列取出彈幕顯示
    }

    /// 裁剪佇列，保留最後 N 條（記憶體警告時使用）
    func trimQueue(keepLast count: Int) {
        guard danmakuQueue.count > count else { return }
        danmakuQueue = Array(danmakuQueue.suffix(count))
        DXPlayerLogger.warning("⚠️ [彈幕] 記憶體警告，佇列裁剪至 \(count) 條")
    }

    /// 清除畫面上正在顯示的彈幕（不清空佇列）
    private func clearVisibleDanmakus() {
        for track in tracks {
            for view in track.danmakuViews {
                view.layer.removeAllAnimations()
                view.removeFromSuperview()
                recycleDanmakuView(view)
            }
        }
        // 重置軌道
        setupTracks(count: currentSettings.displayLines)
    }

    /// 清空所有彈幕
    func clear() {
        // 停止所有動畫並移除視圖
        for track in tracks {
            for view in track.danmakuViews {
                view.layer.removeAllAnimations()
                view.removeFromSuperview()
                recycleDanmakuView(view)
            }
        }

        // 重置軌道
        setupTracks(count: currentSettings.displayLines)

        // 清空佇列
        danmakuQueue.removeAll()
    }

    /// 清空彈幕池（記憶體警告時呼叫）
    func clearPool() {
        danmakuPool.removeAll()
    }

    // MARK: - 私有方法 - 軌道管理

    private func setupTracks(count: Int) {
        // 清理舊軌道
        for track in tracks {
            for view in track.danmakuViews {
                view.removeFromSuperview()
                recycleDanmakuView(view)
            }
        }

        // 創建新軌道
        tracks = (0..<count).map { DanmakuTrack(index: $0) }
    }

    private func allocateTrack(for danmaku: DanmakuItem) -> Int? {
        let danmakuWidth = estimateWidth(for: danmaku)
        let screenWidth = bounds.width

        // 策略 1: 優先選擇空閒軌道
        for track in tracks {
            if track.danmakuViews.isEmpty {
                return track.index
            }
        }

        // 策略 2: 選擇可以放置的軌道（通過碰撞檢測）
        for track in tracks {
            if track.canPlace(screenWidth: screenWidth, danmakuWidth: danmakuWidth) {
                return track.index
            }
        }

        // 策略 3: 無可用軌道
        return nil
    }

    private func estimateWidth(for danmaku: DanmakuItem) -> CGFloat {
        let fontSize = danmaku.fontSize ?? currentSettings.fontSize.points
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let attributes = [NSAttributedString.Key.font: font]
        let textSize = (danmaku.text as NSString).size(withAttributes: attributes)
        return textSize.width + 16 // 加上內距
    }

    // MARK: - 私有方法 - 彈幕顯示

    private func displayDanmaku(_ danmaku: DanmakuItem, in trackIndex: Int) {
        // 從池中取得或創建視圖
        let danmakuView = dequeueDanmakuView()

        // 配置視圖
        danmakuView.configure(
            danmaku: danmaku,
            fontSize: currentSettings.fontSize.points,
            opacity: currentSettings.opacity
        )
        danmakuView.trackIndex = trackIndex

        // 計算 Y 軸位置
        let trackHeight: CGFloat = 30
        let yPosition = safeAreaInsets.top + 10 + CGFloat(trackIndex) * trackHeight

        // 設定起始位置（畫面右側外）
        danmakuView.frame.origin = CGPoint(x: bounds.width, y: yPosition)

        // 添加到視圖
        addSubview(danmakuView)

        // 記錄到軌道
        tracks[trackIndex].danmakuViews.append(danmakuView)

        // 啟動動畫
        animateDanmaku(view: danmakuView, trackIndex: trackIndex)
    }

    private func animateDanmaku(view: DanmakuLabel, trackIndex: Int) {
        let duration = currentSettings.speed.duration
        let endX = -view.frame.width

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveLinear],
            animations: {
                view.frame.origin.x = endX
            },
            completion: { [weak self] finished in
                guard let self = self else { return }

                if finished {
                    // 從軌道中移除
                    if trackIndex < self.tracks.count {
                        self.tracks[trackIndex].danmakuViews.removeAll { $0 === view }
                    }

                    // 回收視圖
                    self.recycleDanmakuView(view)
                }
            }
        )
    }

    // MARK: - 私有方法 - 彈幕池管理

    private func dequeueDanmakuView() -> DanmakuLabel {
        if let view = danmakuPool.popLast() {
            return view
        } else {
            return DanmakuLabel()
        }
    }

    private func recycleDanmakuView(_ view: DanmakuLabel) {
        view.reset()

        if danmakuPool.count < maxPoolSize {
            danmakuPool.append(view)
        }
    }

    // MARK: - 私有方法 - 渲染循環

    private func startRendering() {
        guard displayLink == nil else { return }

        displayLink = CADisplayLink(target: self, selector: #selector(update))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopRendering() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func update() {
        processQueue()
    }

    private func processQueue() {
        guard !danmakuQueue.isEmpty, isEnabled else { return }

        // 每次處理一條彈幕
        guard let danmaku = danmakuQueue.first else { return }

        // 嘗試分配軌道
        if let trackIndex = allocateTrack(for: danmaku) {
            danmakuQueue.removeFirst()
            displayDanmaku(danmaku, in: trackIndex)
        }
        // 若無可用軌道，等待下一幀再試
    }

    // MARK: - 私有方法 - 更新現有彈幕

    private func updateExistingDanmakus() {
        for track in tracks {
            for view in track.danmakuViews {
                guard let danmaku = view.danmakuItem else { continue }

                // 更新整個視圖的透明度（同時影響文字和表情符號）
                view.alpha = currentSettings.opacity

                // 更新字體大小（如果沒有自訂字體）
                if danmaku.fontSize == nil {
                    view.font = UIFont.systemFont(ofSize: currentSettings.fontSize.points, weight: .medium)
                    view.sizeToFit()
                }
            }
        }
    }
}
