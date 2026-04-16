import Foundation
import UIKit
import FSPlayer

/// 彈幕管理器
public class DanmakuManager {

    // MARK: - 屬性

    private weak var containerView: IJKPlayerContainerView?
    private weak var mainPlayer: FSPlayer?
    private var danmakuOverlay: DanmakuOverlay?

    /// 資料來源
    private var dataSource: DanmakuDataSource?

    /// 當前設定
    private var currentSettings: DanmakuSettings = .default

    /// 是否正在顯示
    private var isShowing: Bool = false

    /// 發送頻率限制（秒，預設 5 秒）
    public var sendRateLimit: TimeInterval = 5.0
    /// 上次成功發送的時間
    private var lastSendTime: Date?

    /// 已入佇列的彈幕 ID，防止重複顯示
    private var displayedItemIds: Set<String> = []

    /// 時間同步計時器（VOD 時間軸模式）
    private var syncTimer: Timer?

    // MARK: - 初始化

    public init(containerView: IJKPlayerContainerView, mainPlayer: FSPlayer) {
        self.containerView = containerView
        self.mainPlayer = mainPlayer

        // 載入設定
        currentSettings = DanmakuSettings.load()

        // 監聽記憶體警告
        setupMemoryWarningObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopSyncTimer()
        hide()
    }

    // MARK: - 公共方法 - 資料來源

    /// 設定資料來源
    public func setDataSource(_ dataSource: DanmakuDataSource) {
        // 停止舊資料來源
        self.dataSource?.stop()
        stopSyncTimer()

        // 設定新資料來源
        self.dataSource = dataSource
        dataSource.delegate = self

        // timeline / local 模式：啟動時間同步計時器
        if dataSource.sourceType == .timeline || dataSource.sourceType == .local {
            startSyncTimer()
        }
    }

    // MARK: - 公共方法 - 顯示/隱藏

    /// 顯示彈幕覆蓋層
    public func show() {
        guard let containerView = containerView else {
            DXPlayerLogger.warning("⚠️ [彈幕] 容器視圖未初始化")
            return
        }

        guard !isShowing else {
            DXPlayerLogger.warning("⚠️ [彈幕] 彈幕覆蓋層已顯示")
            return
        }

        DXPlayerLogger.info("📺 [彈幕] 顯示彈幕覆蓋層")

        // 創建覆蓋層
        let overlay = DanmakuOverlay(frame: containerView.bounds)
        overlay.applySettings(currentSettings)

        containerView.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        danmakuOverlay = overlay
        isShowing = true
    }

    /// 隱藏彈幕覆蓋層
    public func hide() {
        guard isShowing else { return }

        DXPlayerLogger.info("👋 [彈幕] 隱藏彈幕覆蓋層")

        danmakuOverlay?.removeFromSuperview()
        danmakuOverlay = nil
        isShowing = false
    }

    // MARK: - 公共方法 - 彈幕控制

    /// 發送彈幕
    public func sendDanmaku(text: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        // 驗證輸入
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let error = NSError(domain: "DanmakuManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "彈幕內容不能為空"])
            completion?(.failure(error))
            return
        }

        guard text.count <= 100 else {
            let error = NSError(domain: "DanmakuManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "彈幕長度不能超過 100 字"])
            completion?(.failure(error))
            return
        }

        // 發送頻率限制
        if let last = lastSendTime, Date().timeIntervalSince(last) < sendRateLimit {
            let remaining = Int(sendRateLimit - Date().timeIntervalSince(last)) + 1
            let error = NSError(domain: "DanmakuManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "發送太頻繁，請等待 \(remaining) 秒後再試"])
            completion?(.failure(error))
            return
        }
        lastSendTime = Date()

        DXPlayerLogger.info("📤 [彈幕] 發送彈幕: \(text)")

        // 本地立即顯示
        let localDanmaku = DanmakuItem(text: text, isSelf: true)
        enqueueDanmaku(localDanmaku)

        // 發送至資料來源
        dataSource?.send(text: text, completion: { result in
            completion?(result)
        })
    }

    /// 添加彈幕到佇列（直接入佇，不做去重）
    public func enqueueDanmaku(_ danmaku: DanmakuItem) {
        danmakuOverlay?.enqueueDanmaku(danmaku)
    }

    /// 更新設定
    public func updateSettings(_ settings: DanmakuSettings) {
        currentSettings = settings
        danmakuOverlay?.applySettings(settings)

        DXPlayerLogger.info("⚙️ [彈幕] 更新設定 - 透明度:\(settings.opacity), 行數:\(settings.displayLines), 字體:\(settings.fontSize.displayName), 速度:\(settings.speed.displayName)")
    }

    /// 設定彈幕開關
    public func setEnabled(_ enabled: Bool) {
        currentSettings.isEnabled = enabled
        danmakuOverlay?.setEnabled(enabled)

        DXPlayerLogger.info("🔄 [彈幕] 彈幕開關: \(enabled ? "開啟" : "關閉")")
    }

    /// 清空彈幕
    public func clear() {
        danmakuOverlay?.clear()
        displayedItemIds.removeAll()
        DXPlayerLogger.info("🗑️ [彈幕] 清空彈幕")
    }

    /// Seek 後清空彈幕並重設時間同步（快進/快退）
    public func seek(to time: TimeInterval) {
        danmakuOverlay?.clear()
        displayedItemIds.removeAll()
        DXPlayerLogger.info("⏩ [彈幕] Seek 至 \(String(format: "%.1f", time))s，清空彈幕")
        syncDanmaku(at: time)
    }

    // MARK: - 公共方法 - 狀態查詢

    /// 是否正在顯示彈幕覆蓋層
    public func isShowingOverlay() -> Bool {
        return isShowing
    }

    /// 彈幕是否啟用
    public var isEnabled: Bool {
        return currentSettings.isEnabled
    }

    // MARK: - 私有方法 - 記憶體管理

    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        DXPlayerLogger.warning("⚠️ [彈幕] 收到記憶體警告，清理快取")
        danmakuOverlay?.clearPool()
        danmakuOverlay?.trimQueue(keepLast: 10)
    }

    // MARK: - 私有方法 - 時間同步

    /// 啟動時間同步計時器（VOD / 本地資料來源）
    private func startSyncTimer() {
        stopSyncTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.mainPlayer else { return }
            self.syncDanmaku(at: player.currentPlaybackTime)
        }
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
        DXPlayerLogger.debug("⏱ [彈幕] 時間同步計時器已啟動")
    }

    private func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    private func syncDanmaku(at currentTime: TimeInterval) {
        dataSource?.fetchDanmaku(from: currentTime, to: currentTime + 0.1) { [weak self] result in
            guard let self = self, case .success(let items) = result else { return }
            for item in items {
                guard !self.displayedItemIds.contains(item.id) else { continue }
                self.displayedItemIds.insert(item.id)
                self.danmakuOverlay?.enqueueDanmaku(item)
            }
        }
    }
}

// MARK: - DanmakuDataSourceDelegate

extension DanmakuManager: DanmakuDataSourceDelegate {
    public func dataSource(_ dataSource: DanmakuDataSource, didReceive danmaku: DanmakuItem) {
        DXPlayerLogger.debug("📥 [彈幕] 接收到彈幕: \(danmaku.text)")
        danmakuOverlay?.enqueueDanmaku(danmaku)
    }

    public func dataSource(_ dataSource: DanmakuDataSource, didReceive danmakus: [DanmakuItem]) {
        DXPlayerLogger.debug("📥 [彈幕] 接收到 \(danmakus.count) 條彈幕")
        for danmaku in danmakus {
            danmakuOverlay?.enqueueDanmaku(danmaku)
        }
    }

    public func dataSource(_ dataSource: DanmakuDataSource, didFailWithError error: Error) {
        DXPlayerLogger.error("❌ [彈幕] 資料來源錯誤: \(error.localizedDescription)")
    }

    public func dataSource(_ dataSource: DanmakuDataSource, didChangeConnectionState state: DanmakuConnectionState) {
        let stateString: String
        switch state {
        case .disconnected: stateString = "已斷線"
        case .connecting: stateString = "連線中"
        case .connected: stateString = "已連線"
        case .reconnecting: stateString = "重新連線中"
        }
        DXPlayerLogger.info("🔗 [彈幕] 連線狀態: \(stateString)")
    }
}
