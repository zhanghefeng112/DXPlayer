import Foundation
import UIKit
import FSPlayer

/// 广告管理器
/// 负责控制片头广告和暂停广告的显示和交互
public class AdManager {

    // MARK: - 属性

    private weak var containerView: IJKPlayerContainerView?
    private weak var mainPlayer: FSPlayer?
    private var adPlayer: FSPlayer?

    private var prerollAdOverlay: PrerollAdOverlay?
    private var pauseAdOverlay: PauseAdOverlay?

    private var adCountdownTimer: Timer?
    private var currentPrerollConfig: PrerollAdConfig?
    private var currentPauseConfig: PauseAdConfig?

    private var remainingSeconds: Int = 15
    private var isPrerollAdPlaying: Bool = false
    private var isPauseAdShowing: Bool = false

    // MARK: - 初始化

    public init(containerView: IJKPlayerContainerView, mainPlayer: FSPlayer) {
        self.containerView = containerView
        self.mainPlayer = mainPlayer

        // 监听主播放器暂停/播放事件
        setupPlayerObservers()
    }

    deinit {
        stopAdCountdown()
        midrollCountdownTimer?.invalidate()
        overlayDismissTimer?.invalidate()
        removePlayerObservers()
        cleanupAdPlayer()
        prerollAdOverlay?.removeFromSuperview()
        pauseAdOverlay?.removeFromSuperview()
    }

    // MARK: - 片头广告

    /// 显示片头广告
    /// - Parameter config: 片头广告配置
    public func showPrerollAd(config: PrerollAdConfig) {
        guard let containerView = containerView else {
            DXPlayerLogger.warning("⚠️ [广告] 容器视图未初始化")
            config.onError?(NSError(domain: "AdManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "容器视图未初始化"]))
            return
        }

        guard !isPrerollAdPlaying else {
            DXPlayerLogger.warning("⚠️ [广告] 片头广告正在播放中")
            return
        }

        DXPlayerLogger.info("📺 [广告] 开始显示片头广告")

        currentPrerollConfig = config
        isPrerollAdPlaying = true

        // 暂停主播放器並隱藏其視圖
        mainPlayer?.pause()
        mainPlayer?.currentPlaybackTime = 0  // 重置到開始位置
        mainPlayer?.view.isHidden = true

        // 设置倒计时（必须在创建覆盖层之前）
        remainingSeconds = Int(config.duration)

        // 创建广告播放器
        setupAdPlayer(videoURL: config.videoURL)

        // 创建覆盖层
        createPrerollAdOverlay(config: config)

        // 开始倒计时
        startAdCountdown()

        // 播放广告视频
        adPlayer?.prepareToPlay()
        adPlayer?.play()
    }

    /// 跳过片头广告（VIP 功能）
    public func skipPrerollAd() {
        guard isPrerollAdPlaying, let config = currentPrerollConfig else {
            return
        }

        DXPlayerLogger.info("⏩ [广告] VIP 跳过片头广告")

        config.onSkipped?(.vipSkip)
        endPrerollAd()
    }

    /// 点击了解详情按钮
    private func handlePrerollDetailClick() {
        guard let config = currentPrerollConfig, let detailURL = config.detailURL else {
            return
        }

        DXPlayerLogger.info("🔗 [广告] 点击了解详情")

        config.onDetailClicked?(detailURL)
        config.onSkipped?(.detailClick)
        endPrerollAd()
    }

    /// 结束片头广告
    private func endPrerollAd() {
        DXPlayerLogger.info("✅ [广告] 片头广告结束")

        stopAdCountdown()
        cleanupAdPlayer()
        removePrerollAdOverlay()

        isPrerollAdPlaying = false

        let config = currentPrerollConfig
        currentPrerollConfig = nil

        // 恢复主播放器：顯示視圖、重置位置、開始播放
        mainPlayer?.view.isHidden = false
        mainPlayer?.currentPlaybackTime = 0  // 確保從頭開始
        mainPlayer?.play()

        // 通知完成
        config?.onCompleted?()
    }

    // MARK: - 暂停广告

    /// 已配置但未显示的暂停广告（等待暂停时自动显示）
    private var pendingPauseConfig: PauseAdConfig?
    /// 已预加载的暂停广告图片
    private var preloadedPauseAdImage: UIImage?

    /// 配置暂停广告（不立即显示，暂停时自动显示，播放时自动隐藏）
    /// - Parameter config: 暂停广告配置
    public func configurePauseAd(config: PauseAdConfig) {
        pendingPauseConfig = config
        preloadedPauseAdImage = nil
        preloadedPauseAdVideoURL = nil

        switch config.imageSource {
        case .video(let url):
            // 视频格式：直接保存 URL，显示时再播放
            preloadedPauseAdVideoURL = url
            DXPlayerLogger.info("✅ [广告] 暂停广告视频 URL 已配置")
        default:
            // 图片格式：预加载图片
            loadPauseAdImage(source: config.imageSource, size: config.size) { [weak self] image in
                self?.preloadedPauseAdImage = image
                if image != nil {
                    DXPlayerLogger.info("✅ [广告] 暂停广告图片预加载成功")
                } else {
                    DXPlayerLogger.warning("⚠️ [广告] 暂停广告图片预加载失败")
                }
            }
        }
    }

    /// 显示暂停广告
    /// - Parameter config: 暂停广告配置
    public func showPauseAd(config: PauseAdConfig) {
        guard let containerView = containerView else {
            DXPlayerLogger.warning("⚠️ [广告] 容器视图未初始化")
            config.onError?(NSError(domain: "AdManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "容器视图未初始化"]))
            return
        }

        guard !isPauseAdShowing else {
            DXPlayerLogger.warning("⚠️ [广告] 暂停广告已显示")
            return
        }

        DXPlayerLogger.info("🖼️ [广告] 显示暂停广告")

        currentPauseConfig = config
        isPauseAdShowing = true

        // 创建暂停广告覆盖层
        createPauseAdOverlay(config: config)

        // 通知已显示
        config.onShown?()
    }

    /// 隐藏暂停广告（不清除配置，下次暂停仍会显示）
    public func hidePauseAd() {
        guard isPauseAdShowing else {
            return
        }

        DXPlayerLogger.info("👋 [广告] 隐藏暂停广告")

        pauseAdOverlay?.stopAdVideo()
        removePauseAdOverlay()

        isPauseAdShowing = false

        let config = currentPauseConfig
        currentPauseConfig = nil

        // 通知已隐藏
        config?.onHidden?()
    }

    /// 播放器暂停时调用（自动显示已配置的暂停广告）
    public func handlePlayerPaused() {
        guard let config = pendingPauseConfig, !isPauseAdShowing, !isPrerollAdPlaying, !isMidrollAdShowing else {
            return
        }
        showPauseAd(config: config)
        // 如果有预加载的视频，设置视频播放
        if let videoURL = preloadedPauseAdVideoURL {
            pauseAdOverlay?.setAdVideo(url: videoURL)
        }
        // 如果有预加载的图片，直接设置
        else if let image = preloadedPauseAdImage {
            pauseAdOverlay?.setAdImage(image)
        }
    }

    /// 播放器播放时调用（自动隐藏暂停广告）
    public func handlePlayerPlaying() {
        if isPauseAdShowing {
            hidePauseAd()
        }
    }

    /// 移除暂停广告配置
    public func removePauseAdConfig() {
        pendingPauseConfig = nil
        preloadedPauseAdImage = nil
        hidePauseAd()
    }

    /// 点击暂停广告
    private func handlePauseAdClick() {
        guard let config = currentPauseConfig else {
            return
        }

        DXPlayerLogger.info("🔗 [广告] 点击暂停广告")

        config.onClicked?(config.detailURL)
    }

    /// 关闭暂停广告
    private func handlePauseAdClose() {
        guard let config = currentPauseConfig else {
            return
        }

        DXPlayerLogger.info("❌ [广告] 关闭暂停广告")

        config.onClosed?()
        hidePauseAd()
    }

    // MARK: - 私有方法 - 片头广告覆盖层

    private func createPrerollAdOverlay(config: PrerollAdConfig) {
        guard let containerView = containerView else { return }

        let overlay = PrerollAdOverlay(frame: containerView.bounds)
        overlay.configure(
            countdown: remainingSeconds,
            isVIP: config.isVIP,
            hasDetailButton: config.detailURL != nil,
            canSkip: config.canSkip,
            allowSkipTime: config.allowSkipTime
        )

        overlay.onClose = { [weak self] in
            self?.skipPrerollAd()
        }

        overlay.onDetailClick = { [weak self] in
            self?.handlePrerollDetailClick()
        }

        containerView.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        prerollAdOverlay = overlay
    }

    private func removePrerollAdOverlay() {
        prerollAdOverlay?.removeFromSuperview()
        prerollAdOverlay = nil
    }

    // MARK: - 私有方法 - 暂停广告覆盖层

    private func createPauseAdOverlay(config: PauseAdConfig) {
        guard let containerView = containerView else { return }

        let overlay = PauseAdOverlay(frame: containerView.bounds)

        overlay.onAdClick = { [weak self] in
            self?.handlePauseAdClick()
        }

        overlay.onClose = { [weak self] in
            self?.handlePauseAdClose()
        }

        containerView.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        pauseAdOverlay = overlay

        // 加载图片
        loadPauseAdImage(source: config.imageSource, size: config.size) { [weak overlay] image in
            overlay?.setAdImage(image)
        }
    }

    private func removePauseAdOverlay() {
        pauseAdOverlay?.removeFromSuperview()
        pauseAdOverlay = nil
    }

    private func loadPauseAdImage(source: ImageSource, size: CGSize?, completion: @escaping (UIImage?) -> Void) {
        switch source {
        case .url(let url):
            // 先尝试直接下载，如果不是有效图片则尝试解密
            Decryptor.shared.fetchAndDecryptMediaImage(from: url) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let imageData):
                        if let image = UIImage(data: imageData) {
                            completion(image)
                        } else {
                            DXPlayerLogger.warning("⚠️ [广告] 解密后无法创建 UIImage")
                            completion(nil)
                        }
                    case .failure(let error):
                        DXPlayerLogger.error("❌ [广告] 图片加载失败: \(error.localizedDescription)")
                        completion(nil)
                    }
                }
            }

        case .image(let image):
            completion(image)

        case .asset(let name):
            completion(UIImage(named: name))

        case .video:
            // 视频格式不走图片加载
            completion(nil)
        }
    }

    /// 预加载的暂停广告视频 URL（解密后）
    private var preloadedPauseAdVideoURL: URL?

    // MARK: - 私有方法 - 广告播放器

    private func setupAdPlayer(videoURL: URL) {
        cleanupAdPlayer()

        guard let containerView = containerView else { return }

        let options = FSOptions.byDefault()
        // 本地 m3u8 含远端 TS URL 和 AES-128 加密，需要设置 protocol_whitelist
        options.setFormatOptionValue("file,http,https,tcp,tls,crypto,data,subfile,concat", forKey: "protocol_whitelist")
        options.setOptionIntValue(10000000, forKey: "timeout", of: kIJKFFOptionCategoryFormat)
        options.setOptionIntValue(1, forKey: "reconnect", of: kIJKFFOptionCategoryFormat)
        let player = FSPlayer(contentURL: videoURL, with: options)
        player.scalingMode = .aspectFit
        player.shouldAutoplay = true

        if let playerView = player.view {
            // 插入到主播放器视图上方（prerollAdOverlay 会在最上层）
            if let mainPlayerView = mainPlayer?.view {
                containerView.insertSubview(playerView, aboveSubview: mainPlayerView)
            } else {
                containerView.insertSubview(playerView, at: 0)
            }
            playerView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: containerView.topAnchor),
                playerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                playerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }

        adPlayer = player

        // 监听播放完成
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(adPlayerDidFinishPlaying),
            name: .FSPlayerDidFinish,
            object: player
        )

        // 监听加载状态
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(adPlayerLoadStateChanged),
            name: .FSPlayerLoadStateDidChange,
            object: player
        )
    }

    private func cleanupAdPlayer() {
        if let player = adPlayer {
            NotificationCenter.default.removeObserver(self, name: .FSPlayerDidFinish, object: player)
            NotificationCenter.default.removeObserver(self, name: .FSPlayerLoadStateDidChange, object: player)
            player.stop()
            player.view?.removeFromSuperview()
        }
        adPlayer = nil
    }

    @objc private func adPlayerDidFinishPlaying() {
        DXPlayerLogger.info("🎬 [广告] 广告视频播放完成")

        if isPrerollAdPlaying {
            currentPrerollConfig?.onSkipped?(.completed)
            endPrerollAd()
        }
    }

    @objc private func adPlayerLoadStateChanged() {
        guard let player = adPlayer else { return }
        let loadState = player.loadState
        DXPlayerLogger.debug("🎬 [广告] 广告视频加载状态: \(loadState.rawValue)")

        // 当缓冲足够时确保播放
        if loadState.contains(.playthroughOK) || loadState.contains(.playable) {
            if !player.isPlaying() {
                player.play()
                DXPlayerLogger.info("🎬 [广告] 广告视频缓冲完成，开始播放")
            }
        }
    }

    // MARK: - 私有方法 - 倒计时

    private func startAdCountdown() {
        stopAdCountdown()

        adCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateAdCountdown()
        }
    }

    private func stopAdCountdown() {
        adCountdownTimer?.invalidate()
        adCountdownTimer = nil
    }

    private func updateAdCountdown() {
        remainingSeconds -= 1

        prerollAdOverlay?.updateCountdown(remainingSeconds)

        if remainingSeconds <= 0 {
            stopAdCountdown()
            // 倒计时结束，自动结束广告并播放视频
            DXPlayerLogger.info("⏰ [广告] 倒计时结束，自动播放视频")
            currentPrerollConfig?.onSkipped?(.completed)
            endPrerollAd()
        }
    }

    // MARK: - 私有方法 - 播放器监听

    private func setupPlayerObservers() {
        // 监听主播放器状态变化（可选：自动显示/隐藏暂停广告）
    }

    private func removePlayerObservers() {
        // 移除观察者
    }

    // MARK: - 中插广告

    private var midrollConfigs: [MidrollAdConfig] = []
    private var triggeredMidrollTimes = Set<Int>()  // 已触发的秒数（防重复）
    private var isMidrollAdShowing: Bool = false
    private var currentMidrollConfig: MidrollAdConfig?
    private var midrollCountdownTimer: Timer?
    private var midrollRemainingSeconds: Int = 0

    /// 添加中插广告配置
    public func addMidrollAd(config: MidrollAdConfig) {
        midrollConfigs.append(config)
        DXPlayerLogger.info("📺 [广告] 添加中插广告: at=\(config.triggerTime)s duration=\(config.duration)s")
    }

    /// 清除所有中插广告
    public func clearMidrollAds() {
        midrollConfigs.removeAll()
        triggeredMidrollTimes.removeAll()
    }

    /// 检查是否需要触发中插广告（由 updateProgress 每 0.5 秒调用）
    public func checkMidrollTrigger(at currentTime: TimeInterval) {
        guard !isMidrollAdShowing, !isPrerollAdPlaying else { return }

        let currentSecond = Int(currentTime)
        for config in midrollConfigs {
            if config.triggerTime == currentSecond && !triggeredMidrollTimes.contains(currentSecond) {
                triggeredMidrollTimes.insert(currentSecond)
                showMidrollAd(config: config)
                break
            }
        }
    }

    private func showMidrollAd(config: MidrollAdConfig) {
        guard let containerView = containerView else { return }

        DXPlayerLogger.info("📺 [中插广告] 触发 at=\(config.triggerTime)s")

        currentMidrollConfig = config
        isMidrollAdShowing = true
        midrollRemainingSeconds = Int(config.duration)

        // 暂停主视频
        mainPlayer?.pause()

        // 创建全屏覆盖层（复用 PrerollAdOverlay UI）
        let overlay = PrerollAdOverlay(frame: containerView.bounds)
        overlay.configure(
            countdown: midrollRemainingSeconds,
            isVIP: true,
            hasDetailButton: false,
            canSkip: config.canSkip,
            allowSkipTime: config.allowSkipTime
        )
        overlay.onClose = { [weak self] in
            self?.endMidrollAd()
        }

        containerView.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        overlay.tag = 9001  // 用 tag 标记中插覆盖层

        // 如果是图片/GIF，加载并显示在覆盖层中
        if config.format != "video", let src = config.src {
            let imgURL: URL?
            if src.hasPrefix("/") {
                imgURL = URL(string: "https://new.wbsatn.cn\(src)")
            } else {
                imgURL = URL(string: src)
            }
            if let url = imgURL {
                loadMidrollImage(url: url, overlay: overlay)
            }
        }

        // 开始倒计时
        midrollCountdownTimer?.invalidate()
        midrollCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMidrollCountdown()
        }

        config.onShown?()
    }

    private func loadMidrollImage(url: URL, overlay: PrerollAdOverlay) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else { return }
            // 支持 GIF 动画：解析所有帧
            let image: UIImage?
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               CGImageSourceGetCount(source) > 1 {
                // GIF：提取所有帧生成动画图片
                let frameCount = CGImageSourceGetCount(source)
                var images: [UIImage] = []
                var totalDuration: Double = 0
                for i in 0..<frameCount {
                    if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                        images.append(UIImage(cgImage: cgImage))
                        // 获取帧延迟
                        if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                           let gifProps = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any],
                           let delay = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double ?? gifProps[kCGImagePropertyGIFDelayTime as String] as? Double {
                            totalDuration += delay
                        } else {
                            totalDuration += 0.1
                        }
                    }
                }
                image = UIImage.animatedImage(with: images, duration: totalDuration)
            } else {
                image = UIImage(data: data)
            }
            guard let finalImage = image else { return }
            DispatchQueue.main.async {
                let imageView = UIImageView(image: finalImage)
                imageView.contentMode = .scaleAspectFit
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.tag = 9002
                overlay.insertSubview(imageView, at: 0)
                NSLayoutConstraint.activate([
                    imageView.topAnchor.constraint(equalTo: overlay.topAnchor),
                    imageView.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
                    imageView.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
                    imageView.bottomAnchor.constraint(equalTo: overlay.bottomAnchor)
                ])
            }
        }.resume()
    }

    private func updateMidrollCountdown() {
        midrollRemainingSeconds -= 1

        if let overlay = containerView?.viewWithTag(9001) as? PrerollAdOverlay {
            overlay.updateCountdown(midrollRemainingSeconds)
        }

        if midrollRemainingSeconds <= 0 {
            endMidrollAd()
        }
    }

    private func endMidrollAd() {
        DXPlayerLogger.info("✅ [中插广告] 结束，恢复播放")

        midrollCountdownTimer?.invalidate()
        midrollCountdownTimer = nil
        isMidrollAdShowing = false

        // 移除覆盖层
        containerView?.viewWithTag(9001)?.removeFromSuperview()

        let config = currentMidrollConfig
        currentMidrollConfig = nil

        // 恢复主视频
        mainPlayer?.play()

        config?.onCompleted?()
    }

    // MARK: - 浮层广告

    private var overlayConfigs: [OverlayAdConfig] = []
    private var triggeredOverlayTimes = Set<Int>()
    private var isOverlayAdShowing: Bool = false
    private var overlayDismissTimer: Timer?

    /// 添加浮层广告配置
    public func addOverlayAd(config: OverlayAdConfig) {
        overlayConfigs.append(config)
        DXPlayerLogger.info("🔲 [广告] 添加浮层广告: at=\(config.triggerTime)s duration=\(config.duration)s")
    }

    /// 清除所有浮层广告
    public func clearOverlayAds() {
        overlayConfigs.removeAll()
        triggeredOverlayTimes.removeAll()
    }

    /// 检查是否需要触发浮层广告（由 updateProgress 每 0.5 秒调用）
    public func checkOverlayTrigger(at currentTime: TimeInterval) {
        guard !isOverlayAdShowing else { return }

        let currentSecond = Int(currentTime)
        for config in overlayConfigs {
            if config.triggerTime == currentSecond && !triggeredOverlayTimes.contains(currentSecond) {
                triggeredOverlayTimes.insert(currentSecond)
                showOverlayAd(config: config)
                break
            }
        }
    }

    private func showOverlayAd(config: OverlayAdConfig) {
        guard let containerView = containerView else { return }

        DXPlayerLogger.info("🔲 [浮层广告] 触发 at=\(config.triggerTime)s")

        isOverlayAdShowing = true

        // 创建浮层视图
        let overlayView = UIView()
        overlayView.tag = 9003
        overlayView.alpha = 0
        overlayView.layer.cornerRadius = 8
        overlayView.layer.shadowColor = UIColor.black.cgColor
        overlayView.layer.shadowOpacity = 0.5
        overlayView.layer.shadowRadius = 8
        overlayView.clipsToBounds = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 60),
            overlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            overlayView.widthAnchor.constraint(equalToConstant: 160),
            overlayView.heightAnchor.constraint(equalToConstant: 90)
        ])

        // 图片
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: overlayView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor)
        ])

        // 关闭按钮
        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("✕", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeBtn.layer.cornerRadius = 10
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(overlayAdCloseButtonTapped), for: .touchUpInside)
        overlayView.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 4),
            closeBtn.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -4),
            closeBtn.widthAnchor.constraint(equalToConstant: 20),
            closeBtn.heightAnchor.constraint(equalToConstant: 20)
        ])

        // "广告" 标签
        let adLabel = UILabel()
        adLabel.text = "广告"
        adLabel.font = .systemFont(ofSize: 9)
        adLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        adLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        adLabel.textAlignment = .center
        adLabel.layer.cornerRadius = 2
        adLabel.clipsToBounds = true
        adLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(adLabel)
        NSLayoutConstraint.activate([
            adLabel.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: -4),
            adLabel.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 4),
            adLabel.widthAnchor.constraint(equalToConstant: 28),
            adLabel.heightAnchor.constraint(equalToConstant: 16)
        ])

        // 加载图片
        if let src = config.src {
            let imgURL: URL?
            if src.hasPrefix("/") {
                imgURL = URL(string: "https://new.wbsatn.cn\(src)")
            } else {
                imgURL = URL(string: src)
            }
            if let url = imgURL {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    DispatchQueue.main.async {
                        imageView.image = image
                    }
                }.resume()
            }
        }

        // 淡入
        UIView.animate(withDuration: 0.5) {
            overlayView.alpha = 1.0
        }

        // 定时淡出
        overlayDismissTimer?.invalidate()
        overlayDismissTimer = Timer.scheduledTimer(withTimeInterval: config.duration, repeats: false) { [weak self] _ in
            self?.dismissOverlayAd()
        }
    }

    @objc private func overlayAdCloseButtonTapped() {
        dismissOverlayAd()
    }

    private func dismissOverlayAd() {
        overlayDismissTimer?.invalidate()
        overlayDismissTimer = nil

        guard let overlayView = containerView?.viewWithTag(9003) else {
            isOverlayAdShowing = false
            return
        }

        UIView.animate(withDuration: 0.3, animations: {
            overlayView.alpha = 0
        }, completion: { _ in
            overlayView.removeFromSuperview()
            self.isOverlayAdShowing = false
            DXPlayerLogger.info("🔲 [浮层广告] 已关闭")
        })
    }

    // MARK: - 公共方法 - 状态查询

    /// 是否正在播放片头广告
    public func isShowingPrerollAd() -> Bool {
        return isPrerollAdPlaying
    }

    /// 是否正在显示暂停广告
    public func isShowingPauseAd() -> Bool {
        return isPauseAdShowing
    }

    /// 是否正在显示中插广告
    public func isShowingMidrollAd() -> Bool {
        return isMidrollAdShowing
    }

    /// 是否正在显示浮层广告
    public func isShowingOverlayAd() -> Bool {
        return isOverlayAdShowing
    }
}

// MARK: - 数据模型

/// 片头广告配置
public struct PrerollAdConfig {
    /// 广告视频 URL
    public let videoURL: URL

    /// 广告时长（秒）
    public let duration: TimeInterval

    /// 是否为 VIP 用户（显示跳过按钮）
    public let isVIP: Bool

    /// 详情页 URL（可选）
    public let detailURL: URL?

    /// 是否允许跳过
    public var canSkip: Bool

    /// 几秒后可跳过（0=随时）
    public var allowSkipTime: Int

    /// 完成回调
    public var onCompleted: (() -> Void)?

    /// 跳过回调
    public var onSkipped: ((SkipReason) -> Void)?

    /// 点击详情回调
    public var onDetailClicked: ((URL) -> Void)?

    /// 错误回调
    public var onError: ((Error) -> Void)?

    public init(
        videoURL: URL,
        duration: TimeInterval,
        isVIP: Bool = false,
        detailURL: URL? = nil,
        canSkip: Bool = true,
        allowSkipTime: Int = 0,
        onCompleted: (() -> Void)? = nil,
        onSkipped: ((SkipReason) -> Void)? = nil,
        onDetailClicked: ((URL) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.videoURL = videoURL
        self.duration = duration
        self.isVIP = isVIP
        self.detailURL = detailURL
        self.canSkip = canSkip
        self.allowSkipTime = allowSkipTime
        self.onCompleted = onCompleted
        self.onSkipped = onSkipped
        self.onDetailClicked = onDetailClicked
        self.onError = onError
    }
}

/// 暂停广告配置
public struct PauseAdConfig {
    /// 图片/视频源
    public var imageSource: ImageSource

    /// 详情页 URL（可选）
    public let detailURL: URL?

    /// 广告图片尺寸（默认 300x200）
    public var size: CGSize?

    /// 显示回调
    public var onShown: (() -> Void)?

    /// 隐藏回调
    public var onHidden: (() -> Void)?

    /// 点击回调
    public var onClicked: ((URL?) -> Void)?

    /// 关闭回调
    public var onClosed: (() -> Void)?

    /// 错误回调
    public var onError: ((Error) -> Void)?

    public init(
        imageSource: ImageSource,
        detailURL: URL? = nil,
        size: CGSize? = CGSize(width: 300, height: 200),
        onShown: (() -> Void)? = nil,
        onHidden: (() -> Void)? = nil,
        onClicked: ((URL?) -> Void)? = nil,
        onClosed: (() -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.imageSource = imageSource
        self.detailURL = detailURL
        self.size = size
        self.onShown = onShown
        self.onHidden = onHidden
        self.onClicked = onClicked
        self.onClosed = onClosed
        self.onError = onError
    }
}

/// 图片源类型
public enum ImageSource {
    /// 网络 URL
    case url(URL)

    /// 本地图片
    case image(UIImage)

    /// Asset 资源
    case asset(String)

    /// 视频 URL（需解密后的可播放 URL）
    case video(URL)
}

/// 中插广告配置
public struct MidrollAdConfig {
    /// 触发时间（秒）
    public let triggerTime: Int

    /// 广告格式（image / gif / video）
    public let format: String

    /// 资源 URL
    public let src: String?

    /// 显示持续时间（秒）
    public let duration: TimeInterval

    /// 是否允许跳过
    public var canSkip: Bool

    /// 几秒后可跳过（0=随时）
    public var allowSkipTime: Int

    /// 显示回调
    public var onShown: (() -> Void)?

    /// 完成回调
    public var onCompleted: (() -> Void)?

    public init(
        triggerTime: Int,
        format: String = "image",
        src: String? = nil,
        duration: TimeInterval = 15,
        canSkip: Bool = true,
        allowSkipTime: Int = 0,
        onShown: (() -> Void)? = nil,
        onCompleted: (() -> Void)? = nil
    ) {
        self.triggerTime = triggerTime
        self.format = format
        self.src = src
        self.duration = duration
        self.canSkip = canSkip
        self.allowSkipTime = allowSkipTime
        self.onShown = onShown
        self.onCompleted = onCompleted
    }
}

/// 浮层广告配置
public struct OverlayAdConfig {
    /// 触发时间（秒）
    public let triggerTime: Int

    /// 资源 URL
    public let src: String?

    /// 显示持续时间（秒）
    public let duration: TimeInterval

    public init(
        triggerTime: Int,
        src: String? = nil,
        duration: TimeInterval = 8
    ) {
        self.triggerTime = triggerTime
        self.src = src
        self.duration = duration
    }
}

/// 跳过原因
public enum SkipReason {
    /// VIP 跳过
    case vipSkip

    /// 点击详情
    case detailClick

    /// 播放完成
    case completed
}
