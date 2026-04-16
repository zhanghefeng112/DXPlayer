import UIKit
import MediaPlayer
import AVFoundation
@_exported import FSPlayer

/// 全屏状态变化通知
extension Notification.Name {
    static let playerDidEnterFullScreen = Notification.Name("playerDidEnterFullScreen")
    static let playerDidExitFullScreen = Notification.Name("playerDidExitFullScreen")
}

/// 通知的 userInfo key
struct PlayerFullScreenInfo {
    static let isVideoLandscape = "isVideoLandscape"
}

/// IJKPlayer 播放器容器视图
/// 整合播放器和控制层，管理播放器生命周期
public class IJKPlayerContainerView: UIView {

    // MARK: - 私有属性

    private var player: FSPlayer?
    private var controlView: PlayerControlView!
    private var progressTimer: Timer?
    private var subtitleManager: SubtitleManager?
    private var playbackSpeedManager: PlaybackSpeedManager?
    private var aspectRatioManager: AspectRatioManager?
    private var adManager: AdManager?

    private var danmakuManager: DanmakuManager?
    private var isDanmakuStarted: Bool = false  // 標記彈幕是否已啟動

    private var thumbnailPreviewManager: ThumbnailPreviewManager?

    // 音视频分轨：外部音频播放器
    private var externalAudioPlayer: AVAudioPlayer?
    private var externalAudioURL: URL?
    private var audioSyncTimer: Timer?
    private var audioDownloadTask: URLSessionTask?
    private var pendingAudioPlay = false // play() 已调用但音频还没准备好

    // 锁屏/后台暂停：记录进入后台前的播放状态
    private var wasPlayingBeforeResignActive = false

    // 保存當前播放配置，用於重試
    private var currentVideoURLString: String?
    private var currentIsCrypt: Bool = false
    private var currentUseProxy: Bool = false

    // 循环播放
    private var isLooping: Bool = false

    // MARK: - 公開回調

    /// 播放器準備好時的回調（可用於顯示廣告等）
    public var onPlayerReady: (() -> Void)?

    // Loading indicator - 統一管理所有 loading 状态
    private let loadingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .whiteLarge)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    // 播放失敗提示 UI
    private let errorView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.text = "播放失败"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("点击重试", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // 獨立的手勢反饋 UI（不受 controlView 影响）
    // 滑动快进/快退预览 UI
    private let seekPreviewContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        view.layer.cornerRadius = 5
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.alpha = 0
        view.isUserInteractionEnabled = false
        return view
    }()

    private let seekTimeLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 24, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let seekProgressBar: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = .white
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        return progressView
    }()

    // 竖直滑动亮度/音量指示器 UI
    private let volumeBrightnessContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        view.layer.cornerRadius = 5
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.alpha = 0
        view.isUserInteractionEnabled = false
        return view
    }()

    private let volumeBrightnessIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let volumeBrightnessProgressBar: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = .white
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.54)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        return progressView
    }()

    // 双击快进/快退动画图标
    private lazy var forwardSeekIcon: UIImageView = {
        let imageView = UIImageView()
        if #available(iOS 13.0, *) {
            imageView.image = UIImage(systemName: "goforward.10")
        }
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        imageView.alpha = 0
        imageView.isUserInteractionEnabled = false
        return imageView
    }()

    private lazy var backwardSeekIcon: UIImageView = {
        let imageView = UIImageView()
        if #available(iOS 13.0, *) {
            imageView.image = UIImage(systemName: "gobackward.10")
        }
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        imageView.alpha = 0
        imageView.isUserInteractionEnabled = false
        return imageView
    }()

    // 全屏相关
    private var isFullScreen = false
    private var originalFrame: CGRect = .zero
    private var originalSuperview: UIView?
    private var currentRotationAngle: CGFloat = 0  // 當前旋轉角度（0 或 π/2）
    private var originalConstraints: [NSLayoutConstraint] = []  // 父视圖对容器的約束
    private var containerConstraints: [NSLayoutConstraint] = []  // 容器內部的約束（包括 controlView）
    private var fullScreenControlViewConstraints: [NSLayoutConstraint] = []  // 全屏时 controlView 的约束

    // 视频尺寸
    private var videoSize: CGSize = .zero

    // 重播状态标誌
    private var isShowingReplay = false
    private var isUserSeeking = false  // 拖动进度条期间抑制暂停广告

    // 水平滑动（快进/快退）相关
    private var panGestureRecognizer: UIPanGestureRecognizer!
    private var isHorizontalSeeking = false
    private var seekStartPosition: TimeInterval = 0
    private var seekStartPoint: CGPoint = .zero

    // 竖直滑动（亮度/音量）相关
    private var isVerticalAdjusting = false
    private var isAdjustingBrightness = false  // true=亮度, false=音量
    private var adjustStartValue: Float = 0.0
    private var adjustStartPoint: CGPoint = .zero
    private var volumeView: MPVolumeView?  // 必須保持強引用，防止被释放
    private var volumeSlider: UISlider?  // 用于设置音量

    // 双击手势（快进/快退10秒）相关
    private var doubleTapGestureRecognizer: UITapGestureRecognizer!
    private let skipDuration: TimeInterval = 10.0  // 跳转时长：10秒

    // MARK: - 初始化

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        // 播放器視圖填滿容器，畫面比例由 FSPlayer 的 darPreference 處理
        if let playerView = player?.view {
            playerView.frame = bounds
        }

        // #1796 修復：全屏狀態下檢測界面方向變化
        // 模擬器上設備方向通知不會觸發，所以用 layoutSubviews 來檢測
        if isFullScreen {
            // 獲取當前界面方向用於 debug
            var currentOrientation: UIInterfaceOrientation = .portrait
            if #available(iOS 13.0, *) {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    currentOrientation = windowScene.interfaceOrientation
                }
            }
            NSLog("📱 [layoutSubviews] 全屏狀態, bounds: %@, 界面方向: %d, isEntering: %d", NSCoder.string(for: bounds), currentOrientation.rawValue, isEnteringFullScreen ? 1 : 0)
            checkOrientationChangeInFullScreen()
        }
    }

    // MARK: - 设置

    private func setupViews() {
        backgroundColor = .black

        // 创建控制视图
        controlView = PlayerControlView()
        controlView.delegate = self
        controlView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controlView)

        NSLayoutConstraint.activate([
            controlView.topAnchor.constraint(equalTo: topAnchor),
            controlView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // 添加 loading view（放在最上层）
        addSubview(loadingView)
        loadingView.addSubview(loadingIndicator)

        // 添加播放失敗提示 view
        addSubview(errorView)
        errorView.addSubview(errorLabel)
        errorView.addSubview(retryButton)
        retryButton.addTarget(self, action: #selector(retryPlayback), for: .touchUpInside)

        // 添加獨立的手勢反饋 UI（不受 controlView 影响）
        addSubview(seekPreviewContainer)
        seekPreviewContainer.addSubview(seekTimeLabel)
        seekPreviewContainer.addSubview(seekProgressBar)

        addSubview(volumeBrightnessContainer)
        volumeBrightnessContainer.addSubview(volumeBrightnessIcon)
        volumeBrightnessContainer.addSubview(volumeBrightnessProgressBar)

        addSubview(forwardSeekIcon)
        addSubview(backwardSeekIcon)

        NSLayoutConstraint.activate([
            loadingView.topAnchor.constraint(equalTo: topAnchor),
            loadingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            loadingView.bottomAnchor.constraint(equalTo: bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor),

            // 播放失敗提示容器（全屏）
            errorView.topAnchor.constraint(equalTo: topAnchor),
            errorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: bottomAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: errorView.centerYAnchor, constant: -20),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: errorView.leadingAnchor, constant: 20),
            errorView.trailingAnchor.constraint(greaterThanOrEqualTo: errorLabel.trailingAnchor, constant: 20),

            retryButton.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16),
            retryButton.widthAnchor.constraint(equalToConstant: 100),
            retryButton.heightAnchor.constraint(equalToConstant: 36),

            // 滑动快进/快退预览容器（正中央）
            seekPreviewContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            seekPreviewContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            seekPreviewContainer.widthAnchor.constraint(equalToConstant: 200),
            seekPreviewContainer.heightAnchor.constraint(equalToConstant: 60),

            seekTimeLabel.topAnchor.constraint(equalTo: seekPreviewContainer.topAnchor, constant: 8),
            seekTimeLabel.leadingAnchor.constraint(equalTo: seekPreviewContainer.leadingAnchor, constant: 10),
            seekPreviewContainer.trailingAnchor.constraint(equalTo: seekTimeLabel.trailingAnchor, constant: 10),

            seekProgressBar.topAnchor.constraint(equalTo: seekTimeLabel.bottomAnchor, constant: 8),
            seekProgressBar.leadingAnchor.constraint(equalTo: seekPreviewContainer.leadingAnchor, constant: 10),
            seekPreviewContainer.trailingAnchor.constraint(equalTo: seekProgressBar.trailingAnchor, constant: 10),
            seekPreviewContainer.bottomAnchor.constraint(equalTo: seekProgressBar.bottomAnchor, constant: 8),

            // 亮度/音量指示器容器（正中央）
            volumeBrightnessContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            volumeBrightnessContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            volumeBrightnessContainer.widthAnchor.constraint(equalToConstant: 200),
            volumeBrightnessContainer.heightAnchor.constraint(equalToConstant: 40),

            volumeBrightnessIcon.leadingAnchor.constraint(equalTo: volumeBrightnessContainer.leadingAnchor, constant: 10),
            volumeBrightnessIcon.centerYAnchor.constraint(equalTo: volumeBrightnessContainer.centerYAnchor),
            volumeBrightnessIcon.widthAnchor.constraint(equalToConstant: 20),
            volumeBrightnessIcon.heightAnchor.constraint(equalToConstant: 20),

            volumeBrightnessProgressBar.leadingAnchor.constraint(equalTo: volumeBrightnessIcon.trailingAnchor, constant: 8),
            volumeBrightnessContainer.trailingAnchor.constraint(equalTo: volumeBrightnessProgressBar.trailingAnchor, constant: 10),
            volumeBrightnessProgressBar.centerYAnchor.constraint(equalTo: volumeBrightnessContainer.centerYAnchor),

            // 双击快进/快退图标（分別在左右兩側）
            // 後退圖标在左側
            backwardSeekIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 80),
            backwardSeekIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            backwardSeekIcon.widthAnchor.constraint(equalToConstant: 30),
            backwardSeekIcon.heightAnchor.constraint(equalToConstant:30),

            // 前进圖标在右側
            forwardSeekIcon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -80),
            forwardSeekIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            forwardSeekIcon.widthAnchor.constraint(equalToConstant: 30),
            forwardSeekIcon.heightAnchor.constraint(equalToConstant: 30)
        ])

        // 添加手勢到容器层，这樣即使控制层隐藏也能接收事件
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)

        // 配置滑动手势
        setupPanGesture()

        // 配置音量控制
        setupVolumeControl()

        // 配置双击手势
        setupDoubleTapGesture()

        // 初始状态：隐藏控制层，显示 loading
        controlView.alpha = 0
        controlView.isHidden = true
        controlView.isUserInteractionEnabled = false  // 初始状态禁用交互

        // 立即显示 loading，直到有视频开始加载
        loadingView.isHidden = false
        loadingIndicator.startAnimating()

        // #1796 修復：在初始化時就註冊方向通知，支持自動旋轉進入/退出全屏
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )

        // 監聽 statusBar 方向變化（兼容舊版本和模擬器）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceOrientationChange),
            name: UIApplication.didChangeStatusBarOrientationNotification,
            object: nil
        )

        // 监听锁屏/后台：暂停播放，恢复后自动继续
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        print("📱 已註冊方向變化通知")
    }

    /// 記錄進入全屏時的界面方向
    private var fullScreenEntryOrientation: UIInterfaceOrientation = .portrait

    /// 標記是否正在進入全屏（防止 layoutSubviews 誤判）
    private var isEnteringFullScreen: Bool = false

    /// 記錄上一次 layoutSubviews 檢測到的界面方向
    private var lastDetectedInterfaceOrientation: UIInterfaceOrientation = .portrait

    /// #3106 修復：標記是否使用 transform 進入全屏（系統旋轉被鎖定時）
    private var isUsingTransformFullScreen: Bool = false

    /// 全屏狀態下檢查方向是否變化（由 layoutSubviews 調用）
    private func checkOrientationChangeInFullScreen() {
        // 如果正在進入全屏，跳過檢查
        guard !isEnteringFullScreen else {
            NSLog("📱 checkOrientationChangeInFullScreen: 正在進入全屏，跳過檢查")
            return
        }

        var interfaceOrientation: UIInterfaceOrientation = .portrait
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                interfaceOrientation = windowScene.interfaceOrientation
            }
        } else {
            interfaceOrientation = UIApplication.shared.statusBarOrientation
        }

        // 如果方向沒變，跳過
        guard interfaceOrientation != lastDetectedInterfaceOrientation else {
            return
        }

        NSLog("📱 checkOrientationChangeInFullScreen: 方向從 %d 變為 %d", lastDetectedInterfaceOrientation.rawValue, interfaceOrientation.rawValue)
        lastDetectedInterfaceOrientation = interfaceOrientation

        // 根據規格：全屏狀態下，無論設備方向如何變化，都保持橫屏全屏
        // 退出全屏的唯一方式是點擊全屏按鈕
        // 此方法現在只用於更新 lastDetectedInterfaceOrientation，不做任何退出全屏操作
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        NSLog("📱 handleTap 被調用")
        // 如果正在播放廣告，忽略點擊
        if adManager?.isShowingPrerollAd() == true {
            NSLog("📱 handleTap: 正在播放廣告，忽略")
            return
        }

        // 如果弹幕输入框正在编辑，只收起键盘，不切换控制层
        // 这样可以避免横屏模式下反复调起/关闭键盘的问题
        if controlView.isDanmakuTextFieldEditing() {
            NSLog("📱 handleTap: 弹幕输入框正在编辑，收起键盘")
            controlView.dismissDanmakuKeyboard()
            return
        }

        // 如果正在 loading，忽略点击，避免显示控制层造成重疊
        if !loadingView.isHidden {
            NSLog("📱 handleTap: 正在加载中，忽略点击")
            return
        }

        // 获取点击位置
        let location = gesture.location(in: self)
        print("点击位置: \(location), 容器大小: \(bounds)")

        // 检查点击是否在容器范围内
        if bounds.contains(location) {
            // #1808 修復：點擊播放器中間區域暫停/播放
            // 定義中間區域（水平方向中間 60%，垂直方向中間 60%）
            let centerWidth = bounds.width * 0.6
            let centerHeight = bounds.height * 0.6
            let centerRect = CGRect(
                x: (bounds.width - centerWidth) / 2,
                y: (bounds.height - centerHeight) / 2,
                width: centerWidth,
                height: centerHeight
            )

            if centerRect.contains(location) {
                // 點擊中間區域：暫停/播放
                NSLog("📱 handleTap: 點擊中間區域，切換播放狀態")
                if let player = player {
                    if player.isPlaying() {
                        pause()
                        // 顯示控件讓用戶知道已暫停
                        controlView.show(animated: true)
                    } else {
                        play()
                        // 播放後延遲隱藏控件
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            self?.controlView.hide(animated: true)
                        }
                    }
                }
            } else {
                // 點擊邊緣區域：切換控制層顯示/隱藏
                if controlView.alpha > 0 {
                    NSLog("📱 handleTap: 隐藏控制层")
                    controlView.hide(animated: true)
                } else {
                    NSLog("📱 handleTap: 显示控制层")
                    controlView.show(animated: true)
                }
            }
        } else {
            NSLog("📱 handleTap: 点击位置不在容器范围内")
        }
    }

    // MARK: - 手势配置和处理

    private func setupPanGesture() {
        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
        panGestureRecognizer.delegate = self
        addGestureRecognizer(panGestureRecognizer)
    }

    /// 配置双击手势
    private func setupDoubleTapGesture() {
        doubleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        doubleTapGestureRecognizer.delegate = self
        addGestureRecognizer(doubleTapGestureRecognizer)

        // 让单击手势在双击失败后才触发（避免冲突）
        if let tapGestures = gestureRecognizers?.filter({ $0 is UITapGestureRecognizer && ($0 as! UITapGestureRecognizer).numberOfTapsRequired == 1 }) {
            for singleTap in tapGestures {
                singleTap.require(toFail: doubleTapGestureRecognizer)
            }
        }
    }

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        // 如果正在播放廣告，忽略手勢
        if adManager?.isShowingPrerollAd() == true {
            return
        }

        // 如果正在 loading，忽略手势
        if !loadingView.isHidden {
            return
        }

        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)

        // 在手势开始时确定方向
        if gesture.state == .began {
            print("📍 handlePanGesture .began - 重置状态前: isHorizontalSeeking=\(isHorizontalSeeking), isVerticalAdjusting=\(isVerticalAdjusting)")

            // 重置所有标志位（确保干净的状态）
            isHorizontalSeeking = false
            isVerticalAdjusting = false

            // 判断是水平滑动还是竖直滑动
            let isHorizontal = abs(velocity.x) > abs(velocity.y)
            let isVertical = abs(velocity.y) > abs(velocity.x)

            // 设置标志位，整个手势过程保持方向不变
            isHorizontalSeeking = isHorizontal
            isVerticalAdjusting = isVertical

            print("✅ 手勢开始 - velocity: (\(velocity.x), \(velocity.y)), 水平: \(isHorizontal), 竖直: \(isVertical)")
            print("设置後: isHorizontalSeeking=\(isHorizontalSeeking), isVerticalAdjusting=\(isVerticalAdjusting)")
        }

        // 根据开始时确定的方向分发到对应的处理方法
        if isHorizontalSeeking {
            // 处理水平滑动（快进/快退）
            handleHorizontalPan(gesture, translation: translation)
        } else if isVerticalAdjusting {
            // 处理竖直滑动（亮度/音量）
            print("🔄 分發到 handleVerticalPan, state=\(gesture.state.rawValue)")
            handleVerticalPan(gesture, translation: translation)
        }

        // 在手势结束时清理状态（确保下次可以重新开始）
        if gesture.state == .ended || gesture.state == .cancelled {
            print("🛑 handlePanGesture .ended/.cancelled - 清理状态")
            isHorizontalSeeking = false
            isVerticalAdjusting = false
            print("   清理後: isHorizontalSeeking=\(isHorizontalSeeking), isVerticalAdjusting=\(isVerticalAdjusting)")
        }
    }

    /// 处理水平滑动（快进/快退）
    private func handleHorizontalPan(_ gesture: UIPanGestureRecognizer, translation: CGPoint) {
        switch gesture.state {
        case .began:
            // isHorizontalSeeking 已在 handlePanGesture 中设置
            seekStartPoint = gesture.location(in: self)
            seekStartPosition = player?.currentPlaybackTime ?? 0

        case .changed:
            guard let player = player, player.duration > 0 else { return }

            // 计算目标时间
            let targetTime = calculateSeekTime(from: translation, duration: player.duration)

            // 更新 UI 预览
            let progress = Float(targetTime / player.duration)
            showSeekPreview(
                currentTime: targetTime,
                duration: player.duration,
                progress: progress
            )

        case .ended, .cancelled:
            guard let player = player else { return }

            // 计算最终目标时间
            let targetTime = calculateSeekTime(from: translation, duration: player.duration)

            // ✅ 检查是否 seek 到视频末尾
            let actualTime = handleSeekToEnd(targetTime: targetTime, duration: player.duration)

            // 执行 seek
            player.currentPlaybackTime = actualTime

            // 只有不是结束状态才恢复播放
            if !isShowingReplay {
                if !player.isPlaying() {
                    play()
                }
            }

            // 隐藏预览 UI
            hideSeekPreview()

            // 重置状态
            isHorizontalSeeking = false

        default:
            break
        }
    }

    /// 处理竖直滑动（亮度/音量）
    private func handleVerticalPan(_ gesture: UIPanGestureRecognizer, translation: CGPoint) {
        print("🎬 handleVerticalPan - state=\(gesture.state.rawValue), translation.y=\(translation.y)")

        switch gesture.state {
        case .began:
            print("📍 .began - isVerticalAdjusting 已在 handlePanGesture 中设置")
            // isVerticalAdjusting 已在 handlePanGesture 中设置
            adjustStartPoint = gesture.location(in: self)

            // 判断是左半屏（亮度）还是右半屏（音量）
            let screenWidth = bounds.width
            isAdjustingBrightness = adjustStartPoint.x < (screenWidth / 2)

            // 获取当前值
            if isAdjustingBrightness {
                adjustStartValue = Float(UIScreen.main.brightness)
                print("✅ 开始调整亮度，当前值: \(adjustStartValue)")
            } else {
                adjustStartValue = getCurrentVolume()
                print("✅ 开始调整音量，当前值: \(adjustStartValue)")
            }

        case .changed:
            // 防抖：滑动距离需要 > 3 像素
            guard abs(translation.y) > 3 else {
                print("⏭️  .changed 跳过：translation.y 太小 (\(translation.y))")
                return
            }

            // 获取屏幕高度
            let screenHeight = bounds.height

            // 计算滑动距离相对于屏幕高度的比例
            // 向上滑动（translation.y < 0）增加值，向下滑动减少值
            // 乘以2倍系数，提高灵敏度（滑动半个屏幕就能从0到max）
            let ratio = Float(translation.y / screenHeight) * 2.0

            // 新值 = 起始值 - 比例（因为向上是负值，减负得正）
            var newValue = adjustStartValue - ratio

            // 边界限制：0.0 - 1.0
            newValue = max(0.0, min(newValue, 1.0))

            // 应用到系统
            if isAdjustingBrightness {
                UIScreen.main.brightness = CGFloat(newValue)
                print("🔆 调整亮度: \(newValue)")
            } else {
                setVolume(newValue)
                print("🔊 调整音量: \(newValue)")
            }

            // 更新 UI
            showVolumeIndicator(value: newValue, isVolume: !isAdjustingBrightness)

        case .ended, .cancelled:
            print("🛑 .ended/.cancelled - 准备隐藏 UI 并重置状态")
            print("当前 isVerticalAdjusting=\(isVerticalAdjusting)")
            // 隐藏 UI
            hideVolumeIndicator()

            // 重置状态
            isVerticalAdjusting = false
            print("✅ 状态已重置 - isVerticalAdjusting=\(isVerticalAdjusting)")

        default:
            break
        }
    }

    /// 处理双击手势（快进/快退10秒）
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        // 如果正在播放廣告，忽略手勢
        if adManager?.isShowingPrerollAd() == true {
            return
        }

        // 如果正在 loading，忽略手势
        if !loadingView.isHidden {
            return
        }

        // 确保播放器存在且有有效时长
        guard let player = player, player.duration > 0 else {
            return
        }

        // 获取点击位置
        let tapLocation = gesture.location(in: self)
        let screenWidth = bounds.width

        // 判断是左侧（后退10秒）还是右侧（前进10秒）
        let isLeftSide = tapLocation.x < (screenWidth / 2)
        let isForward = !isLeftSide

        // 计算新的播放时间
        let currentTime = player.currentPlaybackTime
        var newTime: TimeInterval

        if isForward {
            // 前进10秒
            newTime = currentTime + skipDuration
            // 边界检查：不超过视频总时长
            newTime = min(newTime, player.duration)
        } else {
            // 后退10秒
            newTime = currentTime - skipDuration
            // 边界检查：不小于0
            newTime = max(newTime, 0)
        }

        print("双击\(isForward ? "前进" : "后退")10秒: \(currentTime) -> \(newTime)")

        // ✅ 检查是否 seek 到视频末尾
        let actualTime = handleSeekToEnd(targetTime: newTime, duration: player.duration)

        // 应用跳转
        player.currentPlaybackTime = actualTime

        // 只有不是结束状态才自動播放
        if !isShowingReplay {
            if !player.isPlaying() {
                play()
            }
        }

        // 显示动画反馈
        if isForward {
            showForwardSeekAnimation()
        } else {
            showBackwardSeekAnimation()
        }
    }

    /// 根据滑动距离计算目标播放时间
    /// - Parameters:
    ///   - translation: 滑动距离
    ///   - duration: 视频总时长
    /// - Returns: 目标时间（已做边界检查）
    private func calculateSeekTime(from translation: CGPoint, duration: TimeInterval) -> TimeInterval {
        // 获取屏幕宽度
        let screenWidth = bounds.width

        // 计算滑动比例（滑动距离 / 屏幕宽度）
        let ratio = Double(translation.x) / Double(screenWidth)

        // 计算时间偏移量（比例 × 视频总时长）
        let timeOffset = ratio * duration

        // 计算新的播放时间
        let newTime = seekStartPosition + timeOffset

        // 边界检查：确保在 [0, duration] 范围内
        return max(0, min(newTime, duration))
    }

    /// 配置音量控制（通过 MPVolumeView 的隐藏 slider）
    private func setupVolumeControl() {
        // 创建 MPVolumeView（必須在视圖范围內才能正确初始化）
        // ⚠️ 关键：frame 必須在视圖范围內，不能太遠
        let view = MPVolumeView(frame: CGRect(x: 0, y: -100, width: 100, height: 100))
        view.clipsToBounds = false  // 允許超出邊界
        view.backgroundColor = .clear
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        view.isUserInteractionEnabled = false
        view.alpha = 0.001  // 设置一个非常小但不是0的值
        addSubview(view)

        // ⚠️ 重要：保存为屬性，防止被释放
        self.volumeView = view

        print("📱 MPVolumeView 已创建，开始查找 slider...")

        // 等待视圖完全布局後再查找
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.findVolumeSlider(attempt: 1, maxAttempts: 10)
        }
    }

    /// 递歸查找音量 slider
    private func findVolumeSlider(attempt: Int, maxAttempts: Int) {
        guard let volumeView = self.volumeView else {
            print("❌ volumeView 为 nil")
            return
        }

        print("🔍 第\(attempt)次查找 slider，subviews 数量: \(volumeView.subviews.count)")

        // 打印所有子视圖类型
        for (index, subview) in volumeView.subviews.enumerated() {
            print("子视圖[\(index)]: \(type(of: subview))")
        }

        // 查找 slider
        for subview in volumeView.subviews {
            if let slider = subview as? UISlider {
                self.volumeSlider = slider
                print("✅✅✅ 音量 slider 已找到！（第\(attempt)次尝试）")
                print("当前音量值: \(slider.value)")
                print("Slider frame: \(slider.frame)")
                return
            }
        }

        // 如果沒找到且尝试次数未達上限，延遲後重试
        if attempt < maxAttempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.findVolumeSlider(attempt: attempt + 1, maxAttempts: maxAttempts)
            }
        } else {
            print("❌❌❌ 警告：尝试\(maxAttempts)次後仍未找到音量 slider")
            print("MPVolumeView 子视圖数量: \(volumeView.subviews.count)")
            print("这是 iOS 系統限制，MPVolumeView 在某些情況下无法获取 slider")
            print("將使用备用方案（显示 UI 但无法实际控制系統音量）")
        }
    }

    /// 获取当前音量
    private func getCurrentVolume() -> Float {
        // 方案1：優先使用 MPVolumeView 的 slider
        if let slider = volumeSlider {
            return slider.value
        }

        // 方案2：使用 AVAudioSession 获取系統音量（只读）
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            let volume = AVAudioSession.sharedInstance().outputVolume
            print("📢 从 AVAudioSession 获取音量: \(volume)")
            return volume
        } catch {
            print("❌ 无法获取系統音量: \(error)")
            return 0.5
        }
    }

    /// 设置音量
    private func setVolume(_ value: Float) {
        let clampedValue = max(0.0, min(value, 1.0))

        if let slider = volumeSlider {
            slider.value = clampedValue
        } else {
            // 备用方案：重新创建 MPVolumeView 并设置
            let tempView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
            addSubview(tempView)
            for subview in tempView.subviews {
                if let slider = subview as? UISlider {
                    slider.value = clampedValue
                    self.volumeSlider = slider
                    break
                }
            }
            tempView.removeFromSuperview()
        }
    }

    // MARK: - 手勢反饋 UI 方法

    /// 格式化时间显示
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 显示快进/快退预覽
    private func showSeekPreview(currentTime: TimeInterval, duration: TimeInterval, progress: Float) {
        let currentTimeStr = formatTime(currentTime)
        let durationStr = formatTime(duration)
        seekTimeLabel.text = "\(currentTimeStr) / \(durationStr)"
        seekProgressBar.progress = progress

        if seekPreviewContainer.isHidden {
            seekPreviewContainer.isHidden = false
            UIView.animate(withDuration: 0.2) {
                self.seekPreviewContainer.alpha = 1.0
            }
        }
    }

    /// 隐藏快进/快退预覽
    private func hideSeekPreview() {
        UIView.animate(withDuration: 0.2, animations: {
            self.seekPreviewContainer.alpha = 0.0
        }) { _ in
            self.seekPreviewContainer.isHidden = true
        }
    }

    /// 显示音量/亮度指示器
    private func showVolumeIndicator(value: Float, isVolume: Bool) {
        // 根据值和类型选择合适的圖标
        let iconName: String
        if isVolume {
            if value <= 0 {
                iconName = "speaker.slash.fill"
            } else if value < 0.33 {
                iconName = "speaker.fill"
            } else if value < 0.66 {
                iconName = "speaker.wave.2.fill"
            } else {
                iconName = "speaker.wave.3.fill"
            }
        } else {
            if value < 0.5 {
                iconName = "sun.min.fill"
            } else {
                iconName = "sun.max.fill"
            }
        }

        if #available(iOS 13.0, *) {
            volumeBrightnessIcon.image = UIImage(systemName: iconName)
        }
        volumeBrightnessProgressBar.progress = value

        if volumeBrightnessContainer.isHidden {
            volumeBrightnessContainer.isHidden = false
            UIView.animate(withDuration: 0.2) {
                self.volumeBrightnessContainer.alpha = 1.0
            }
        }
    }

    /// 隐藏音量/亮度指示器
    private func hideVolumeIndicator() {
        print("hideVolumeIndicator 被调用")
        UIView.animate(withDuration: 0.2, animations: {
            self.volumeBrightnessContainer.alpha = 0.0
        }) { _ in
            self.volumeBrightnessContainer.isHidden = true
            print("音量/亮度指示器已隐藏")
        }
    }

    /// 显示双击前进動画
    private func showForwardSeekAnimation() {
        forwardSeekIcon.isHidden = false
        UIView.animate(withDuration: 0.1, animations: {
            self.forwardSeekIcon.alpha = 1.0
            self.forwardSeekIcon.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }) { _ in
            UIView.animate(withDuration: 0.1, delay: 0.2, options: [], animations: {
                self.forwardSeekIcon.alpha = 0.0
                self.forwardSeekIcon.transform = .identity
            }) { _ in
                self.forwardSeekIcon.isHidden = true
            }
        }
    }

    /// 显示双击後退動画
    private func showBackwardSeekAnimation() {
        backwardSeekIcon.isHidden = false
        UIView.animate(withDuration: 0.1, animations: {
            self.backwardSeekIcon.alpha = 1.0
            self.backwardSeekIcon.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }) { _ in
            UIView.animate(withDuration: 0.1, delay: 0.2, options: [], animations: {
                self.backwardSeekIcon.alpha = 0.0
                self.backwardSeekIcon.transform = .identity
            }) { _ in
                self.backwardSeekIcon.isHidden = true
            }
        }
    }

    // MARK: - 私有輔助方法

    /// 检查并处理 seek 到视频末尾的情況
    /// - Parameters:
    ///   - targetTime: 目标播放时间
    ///   - duration: 视频总时长
    /// - Returns: 实际应該 seek 到的时间
    private func handleSeekToEnd(targetTime: TimeInterval, duration: TimeInterval) -> TimeInterval {
        // 如果目标时间 >= 视频总时长（留一点误差，0.5秒內算作结束）
        if targetTime >= duration - 0.5 {
            print("🎬 Seek 到视频末尾，显示重播圖标")
            // 设置为结束状态
            player?.currentPlaybackTime = duration
            stopProgressTimer()
            isShowingReplay = true
            controlView.updatePlaybackState(isPlaying: false, showReplay: true)
            controlView.show(animated: true, autoHide: false)
            return duration
        }
        return targetTime
    }

    var isCrypt: Bool = false //是否加密（已废弃，现在自动判断）

    // MARK: - 公共方法

    /// 设置播放配置并开始播放（自动判断是否需要解密）
    /// - Parameters:
    ///   - url: 视频 URL
    ///   - useProxy: 是否使用代理播放
    public func setVideoConfig(url: String, useProxy: Bool = false) {
        var url = url
        // ATS: 自动升级 HTTP → HTTPS（localhost 和 127.0.0.1 除外）
        if url.hasPrefix("http://") && !url.hasPrefix("http://127.0.0.1") && !url.hasPrefix("http://localhost") {
            url = url.replacingOccurrences(of: "http://", with: "https://", range: url.range(of: "http://"))
            print("🔒 [ATS] 自动升级 HTTP → HTTPS: \(url)")
        }

        let isCrypt = false  // 已废弃，保留内部兼容
        // 保存當前播放配置，用於重試
        currentVideoURLString = url
        currentIsCrypt = isCrypt
        currentUseProxy = useProxy

        // 创建默认播放器选项
        let options = FSOptions.byDefault()

        // 启用 FFmpeg 调试日誌
        FSPlayer.setLogReport(true)
        FSPlayer.setLogLevel(FS_LOG_DEBUG)

        // 清理现有播放器
        release()

        // 隐藏之前的错误提示
        hideError()

        // 显示 loading
        showLoading()


        guard let url = URL(string: url) else {
            print("无效的视频URL")
            return
        }

        // 检查是否是直接播放的格式（mp4, mkv, avi 等非 m3u8 格式）
        let directPlayExtensions = ["mp4", "mkv", "avi", "mov", "webm", "flv", "wmv", "m4v"]
        let pathExtension = url.pathExtension.lowercased()
        if directPlayExtensions.contains(pathExtension) {
            print("✅ [智能播放] 检测到直接播放格式 (\(pathExtension))，跳过解密")
            DispatchQueue.main.async { [weak self] in
                self?.setupPlayerDirectly(with: url, options: FSOptions.byDefault())
            }
            return
        }

        // 智能播放：自动判断是普通 m3u8 还是加密内容
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rewritten-\(Int(Date().timeIntervalSince1970)).m3u8")

        // 使用智能解密方法，自动判断 URL 类型：
        // 1. 普通 m3u8（以 #EXTM3U 开头）-> 直接播放
        // 2. 重定向 URL（以 http 开头）-> 继续获取下一层
        // 3. JM 加密格式 -> 解密后播放
        // 4. Base64 编码的 m3u8 -> 解码后播放
        Decryptor.shared.smartDecrypt(from: url) {[weak self] result in
            switch result {
            case .success(let info):
                let playURL: URL

                if info.isPlainM3u8 {
                    // 普通 m3u8，直接使用 URL
                    print("✅ [智能播放] 检测到普通 m3u8，直接播放")
                    guard let redirectURL = info.redirectURL else {
                        print("❌ [智能播放] URL 为空")
                        DispatchQueue.main.async {
                            self?.hideLoading()
                            self?.showError(message: "获取播放地址失败")
                        }
                        return
                    }
                    playURL = redirectURL

                    // 如果启用代理播放（仅对普通 m3u8 生效）
                    if useProxy {
                        Task {
                            await self?.setupPlayerWithProxy(url: redirectURL.absoluteString)
                        }
                        return
                    }
                } else {
                    // 加密格式（JM/Base64），使用解密后的内容
                    guard let text = info.decryptedContent else {
                        print("❌ [智能播放] 解密内容为空")
                        DispatchQueue.main.async {
                            self?.hideLoading()
                            self?.showError(message: "解密失败：内容为空")
                        }
                        return
                    }

                    print("🔓 [智能播放] 解密成功，播放清单：\n\(text.prefix(500))...")
                    do {
                        try text.write(to: tmpURL, atomically: true, encoding: .utf8)
                    } catch {
                        print("❌ [智能播放] 写临时 m3u8 失败：\(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self?.hideLoading()
                            self?.showError(message: "临时文件写入失败")
                        }
                        return
                    }
                    playURL = tmpURL
                }

                // 配置播放选项
                options.setOptionIntValue(10000000, forKey: "timeout", of: kIJKFFOptionCategoryFormat)
                options.setOptionIntValue(1, forKey: "reconnect", of: kIJKFFOptionCategoryFormat)

                // 始终设置 protocol_whitelist，因为 HLS 可能包含 AES-128 加密的 ts 片段（需要 crypto 协议）
                // 无论是本地文件还是远程 URL，都需要支持 crypto 协议
                options.setFormatOptionValue("file,http,https,tcp,tls,crypto,data,subfile,concat", forKey: "protocol_whitelist")
                options.protocolWhitelist = "crypto"

                // 必须返回主线程去播放，否则崩溃
                DispatchQueue.main.async {
                    // 创建新播放器
                    self?.player = FSPlayer(contentURL: playURL, with: options)

                    guard let player = self?.player else {
                        self?.hideLoading()
                        self?.showError(message: "播放器创建失败")
                        return
                    }

                    // 配置播放器视图（不設 autoresizingMask，由 layoutSubviews 控制畫面比例）
                    player.view.frame = self!.bounds
                    self?.insertSubview(player.view, at: 0)
                    self?.setNeedsLayout()

                    // 确保控制层在最上层
                    self?.bringSubviewToFront(self!.controlView)

                    // 设置缩放模式
                    player.scalingMode = .aspectFit

                    // 初始化字幕管理器
                    self?.subtitleManager = SubtitleManager(player: player)

                    // 初始化播放速度管理器
                    self?.playbackSpeedManager = PlaybackSpeedManager(player: player)

                    // 初始化画面比例管理器
                    self?.aspectRatioManager = AspectRatioManager(player: player)

                    // 初始化广告管理器
                    self?.adManager = AdManager(containerView: self!, mainPlayer: player)

                    // 初始化彈幕管理器
                    self?.danmakuManager = DanmakuManager(containerView: self!, mainPlayer: player)
                    self?.setupDanmakuSystem()

                    // 初始化缩略图预览管理器（使用原始 URL，不是解密后的临时文件）
                    self?.setupThumbnailPreview(videoURL: url)

                    // 监听播放器通知
                    self?.observePlayerNotifications()

                    // 准备播放
                    player.prepareToPlay()

                    // 注意：控制层会在 loading 完成後自動显示，这裡不需要手動显示
                }
            case .failure(let err):
                print("❌ [智能播放] 获取播放内容失败：\(err)")
                DispatchQueue.main.async {
                    self?.hideLoading()
                    self?.showError(message: "播放失败：\(err.localizedDescription)")
                }
            }
        }
    }

    /// 直接播放（不经过解密，用于 mp4 等格式）
    /// - Parameters:
    ///   - url: 视频 URL
    ///   - options: 播放器选项
    private func setupPlayerDirectly(with url: URL, options: FSOptions) {
        print("🎬 [直接播放] 开始播放: \(url.absoluteString)")

        // 配置播放选项
        options.setOptionIntValue(10000000, forKey: "timeout", of: kIJKFFOptionCategoryFormat)
        options.setOptionIntValue(1, forKey: "reconnect", of: kIJKFFOptionCategoryFormat)
        options.setFormatOptionValue("file,http,https,tcp,tls,crypto,data,subfile,concat", forKey: "protocol_whitelist")
        // 精确 seek（避免跳到最近 keyframe）
        options.setOptionIntValue(1, forKey: "enable-accurate-seek", of: kIJKFFOptionCategoryPlayer)
        // 降温优化：减少 CPU 负担
        options.setOptionIntValue(1, forKey: "framedrop", of: kIJKFFOptionCategoryPlayer)
        options.setOptionIntValue(30, forKey: "max-fps", of: kIJKFFOptionCategoryPlayer)
        options.setOptionIntValue(0, forKey: "packet-buffering", of: kIJKFFOptionCategoryFormat)
        options.setOptionIntValue(1, forKey: "videotoolbox", of: kIJKFFOptionCategoryPlayer)

        // 创建新播放器
        self.player = FSPlayer(contentURL: url, with: options)

        guard let player = self.player else {
            hideLoading()
            showError(message: "播放器创建失败")
            return
        }

        // 配置播放器视图
        player.view.frame = self.bounds
        self.insertSubview(player.view, at: 0)
        self.setNeedsLayout()

        // 确保控制层在最上层
        self.bringSubviewToFront(self.controlView)

        // 设置缩放模式
        player.scalingMode = .aspectFit

        // 初始化字幕管理器
        self.subtitleManager = SubtitleManager(player: player)

        // 初始化播放速度管理器
        self.playbackSpeedManager = PlaybackSpeedManager(player: player)

        // 初始化画面比例管理器
        self.aspectRatioManager = AspectRatioManager(player: player)

        // 初始化广告管理器
        self.adManager = AdManager(containerView: self, mainPlayer: player)

        // 初始化彈幕管理器
        self.danmakuManager = DanmakuManager(containerView: self, mainPlayer: player)
        self.setupDanmakuSystem()

        // 初始化缩略图预览管理器
        self.setupThumbnailPreview(videoURL: url)

        // 監聽播放狀態變化
        self.observePlayerNotifications()

        // 準備播放
        player.prepareToPlay()
    }

    /// 使用代理模式设置播放器
    /// - Parameter url: 视频 URL
    private func setupPlayerWithProxy(url: String) async {
        DXPlayerLogger.info("🟢 [代理播放] 启用代理模式: \(url)")

        // 创建代理服务器
        let proxyResult = await ProxyServer.shared.createServer(for: url)

        guard !proxyResult["localproxy"]!.isEmpty else {
            DXPlayerLogger.error("❌ [代理播放] 启动失败，降级到直接播放")
            await MainActor.run {
                setVideoConfig(url: url, useProxy: false)
            }
            return
        }

        let proxyURL = proxyResult["localproxy"]!
        DXPlayerLogger.info("✅ [代理播放] 代理地址: \(proxyURL)")

        await MainActor.run {
            // 创建播放器选项
            let options = FSOptions.byDefault()

            // 启用 FFmpeg 调试日志
            FSPlayer.setLogReport(true)
            FSPlayer.setLogLevel(FS_LOG_DEBUG)

            // 注意：这里不再调用 release()，因为 setVideoConfig 已经调用过了
            // 只需要确保 loading 正在显示

            // 显示 loading
            showLoading()

            // 解析原始 URL 获取路径
            guard let originalURL = URL(string: url),
                  let path = originalURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                DXPlayerLogger.error("❌ [代理播放] 无效的 URL")
                hideLoading()
                showError(message: "无效的视频地址")
                return
            }

            // 构建代理 URL：http://127.0.0.1:port/original-path
            var proxyVideoURL = "\(proxyURL)\(path)"
            if let query = originalURL.query {
                proxyVideoURL += "?\(query)"
            }

            guard let videoURL = URL(string: proxyVideoURL) else {
                DXPlayerLogger.error("❌ [代理播放] 无效的代理 URL: \(proxyVideoURL)")
                hideLoading()
                showError(message: "代理地址构建失败")
                return
            }

            DXPlayerLogger.info("🔧 [代理播放] 播放 URL: \(proxyVideoURL)")

            // 网络和超时选项
            options.setOptionIntValue(10000000, forKey: "timeout", of: kIJKFFOptionCategoryFormat)
            options.setOptionIntValue(1, forKey: "reconnect", of: kIJKFFOptionCategoryFormat)

            // 创建播放器（使用代理 URL）
            player = FSPlayer(contentURL: videoURL, with: options)

            guard let player = player else {
                DXPlayerLogger.error("❌ [代理播放] 创建播放器失败")
                hideLoading()
                showError(message: "播放器创建失败")
                return
            }

            // 配置播放器视图（不設 autoresizingMask，由 layoutSubviews 控制畫面比例）
            player.view.frame = bounds
            insertSubview(player.view, at: 0)
            setNeedsLayout()

            // 确保控制层在最上层
            bringSubviewToFront(controlView)

            // 设置缩放模式
            player.scalingMode = .aspectFit

            // 初始化字幕管理器
            subtitleManager = SubtitleManager(player: player)

            // 初始化播放速度管理器
            playbackSpeedManager = PlaybackSpeedManager(player: player)

            // 初始化画面比例管理器
            aspectRatioManager = AspectRatioManager(player: player)

            // 初始化广告管理器
            adManager = AdManager(containerView: self, mainPlayer: player)

            // 初始化彈幕管理器
            danmakuManager = DanmakuManager(containerView: self, mainPlayer: player)
            setupDanmakuSystem()

            // 初始化缩略图预览管理器（使用原始 URL）
            setupThumbnailPreview(videoURL: originalURL)

            // 监听播放器通知
            observePlayerNotifications()

            // 准备播放
            player.prepareToPlay()

            DXPlayerLogger.info("✅ [代理播放] 播放器已准备就绪")
        }
    }

    /// 播放
    public func play() {
        player?.play()
        if externalAudioPlayer != nil {
            externalAudioPlayer?.play()
            startAudioSyncTimer()
            pendingAudioPlay = false
        } else if externalAudioURL != nil {
            // 音频还没准备好，标记等准备好后自动播放
            pendingAudioPlay = true
        }
        startProgressTimer()

        // 只在不是 loading 状态时显示控制层
        if loadingView.isHidden {
            controlView.show(animated: false)
        }

        // 如果沒有廣告在播放，首次播放時啟動彈幕系統
        if !(adManager?.isShowingPrerollAd() ?? false) {
            startDanmakuSystem()
        }
    }

    /// 暂停
    public func pause() {
        player?.pause()
        pendingAudioPlay = false
        externalAudioPlayer?.pause()
        stopProgressTimer()
        stopAudioSyncTimer()
    }

    /// 停止
    public func stop() {
        player?.stop()
        stopProgressTimer()
        externalAudioPlayer?.stop()
        stopAudioSyncTimer()
    }

    /// 清理播放器资源
    public func release() {
        // 移除通知
        NotificationCenter.default.removeObserver(self)

        // 停止設備方向通知生成
        UIDevice.current.endGeneratingDeviceOrientationNotifications()

        // 停止定时器
        stopProgressTimer()

        // 清理外部音频
        stopExternalAudio()

        // 清理所有广告（覆盖层、定时器、状态）
        adManager?.clearMidrollAds()
        adManager?.clearOverlayAds()
        adManager?.removePauseAdConfig()
        // 移除中插/浮层广告覆盖层
        viewWithTag(9001)?.removeFromSuperview()
        viewWithTag(9003)?.removeFromSuperview()
        adManager = nil

        // 清理彈幕系統
        danmakuManager?.hide()
        danmakuManager = nil
        isDanmakuStarted = false  // 重置彈幕啟動標記

        // 清理缩略图预览系统
        thumbnailPreviewManager?.clearCache()
        thumbnailPreviewManager = nil

        // 清理播放器
        player?.shutdown()
        player?.view.removeFromSuperview()
        player = nil

        // 清理代理服务器（如果之前使用了代理）
        ProxyServer.shared.stopAll()

        // 重置全屏狀態，確保下次啟動時為正常模式
        UserDefaults.standard.set(false, forKey: "DXPlayerSDK.isPlayerFullScreen")
    }

    /// 设置视频标题
    public func setTitle(_ title: String) {
        controlView.setTitle(title)
    }

    /// #1803 修復：收起彈幕輸入鍵盤
    /// 供外部調用，點擊播放器以外區域時收起鍵盤
    public func dismissDanmakuKeyboard() {
        controlView.dismissDanmakuKeyboard()
    }

    /// #1803 修復：檢查彈幕輸入框是否正在編輯
    public func isDanmakuTextFieldEditing() -> Bool {
        return controlView.isDanmakuTextFieldEditing()
    }

    // MARK: - 字幕控制

    /// 加载字幕文件
    /// - Parameters:
    ///   - url: 字幕文件 URL（支持 file:// 和 http(s)://）
    ///   - autoActivate: 是否自动激活显示（默认 true）
    /// - Returns: 成功返回 true，失败返回 false
    @discardableResult
    public func loadSubtitle(url: URL, autoActivate: Bool = true) -> Bool {
        return subtitleManager?.loadSubtitle(url: url, autoActivate: autoActivate) ?? false
    }

    /// 批量加载字幕文件
    /// - Parameter urls: 字幕文件 URL 数组
    /// - Returns: 成功返回 true，失败返回 false
    @discardableResult
    public func loadSubtitles(urls: [URL]) -> Bool {
        return subtitleManager?.loadSubtitles(urls: urls) ?? false
    }

    /// 激活指定索引的字幕
    /// - Parameter index: 字幕索引（基于已加载的字幕列表）
    public func activateSubtitle(at index: Int) {
        subtitleManager?.activateSubtitle(at: index)
    }

    /// 移除字幕
    public func removeSubtitle() {
        subtitleManager?.removeSubtitle()
        stopSubtitleTimer()
        parsedCaptions.removeAll()
        subtitleLabel.text = nil
    }

    // MARK: - 多语言字幕

    /// 字幕信息
    public struct SubtitleTrack {
        public let lang: String
        public let label: String
        public let url: String
        public init(lang: String, label: String, url: String) {
            self.lang = lang; self.label = label; self.url = url
        }
    }

    private var subtitleTracks: [SubtitleTrack] = []
    private var currentSubtitleLang: String?

    /// 设置多语言字幕列表
    public func setSubtitleTracks(_ tracks: [SubtitleTrack]) {
        subtitleTracks = tracks
        // 读取偏好
        let savedLang = UserDefaults.standard.string(forKey: "DXPlayer_SubtitleLangPref")
        if let saved = savedLang, tracks.contains(where: { $0.lang == saved }) {
            switchSubtitle(to: saved)
        } else if let first = tracks.first {
            switchSubtitle(to: first.lang)
        }
        print("📝 [字幕] 设置 \(tracks.count) 种语言: \(tracks.map { $0.lang }.joined(separator: ", "))")
    }

    // 自渲染字幕相关
    private var parsedCaptions: [(start: Double, end: Double, text: String)] = []
    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 16)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOffset = CGSize(width: 1, height: 1)
        label.layer.shadowOpacity = 1.0
        label.layer.shadowRadius = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private var subtitleTimer: Timer?

    /// 切换字幕语言
    public func switchSubtitle(to lang: String?) {
        currentSubtitleLang = lang
        UserDefaults.standard.set(lang, forKey: "DXPlayer_SubtitleLangPref")

        guard let lang = lang else {
            stopSubtitleTimer()
            parsedCaptions.removeAll()
            subtitleLabel.text = nil
            print("📝 [字幕] 关闭字幕")
            return
        }

        guard let track = subtitleTracks.first(where: { $0.lang == lang }),
              let url = URL(string: track.url) else { return }

        print("📝 [字幕] 切换: \(track.label) (\(track.url))")

        // 下载 SRT → 修复格式 → 解析 → 自渲染
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, let content = String(data: data, encoding: .utf8) else {
                print("❌ [字幕] 下载失败: \(error?.localizedDescription ?? "无数据")")
                return
            }
            let fixed = self.fixSrtContent(content)
            let captions = self.parseSrt(fixed)

            DispatchQueue.main.async {
                self.parsedCaptions = captions
                self.setupSubtitleOverlay()
                self.startSubtitleTimer()
                print("✅ [字幕] 解析完成: \(captions.count) 条字幕 (\(lang))")
            }
        }.resume()
    }

    private func setupSubtitleOverlay() {
        if subtitleLabel.superview == nil {
            addSubview(subtitleLabel)
            NSLayoutConstraint.activate([
                subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -50),
            ])
        }
        bringSubviewToFront(subtitleLabel)
    }

    private func startSubtitleTimer() {
        stopSubtitleTimer()
        subtitleTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateSubtitleDisplay()
        }
        RunLoop.main.add(subtitleTimer!, forMode: .common)
    }

    private func stopSubtitleTimer() {
        subtitleTimer?.invalidate()
        subtitleTimer = nil
    }

    private func updateSubtitleDisplay() {
        guard let player = player else { return }
        let currentTime = player.currentPlaybackTime
        guard currentTime.isFinite && currentTime >= 0 else { return }

        let caption = parsedCaptions.first { currentTime >= $0.start && currentTime <= $0.end }
        subtitleLabel.text = caption?.text
    }

    /// 解析标准 SRT 为 (start, end, text) 数组
    private func parseSrt(_ content: String) -> [(start: Double, end: Double, text: String)] {
        var result: [(Double, Double, String)] = []
        let blocks = content.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard lines.count >= 2 else { continue }
            // 找时间戳行
            for (i, line) in lines.enumerated() {
                if line.contains("-->") {
                    let parts = line.components(separatedBy: "-->")
                    guard parts.count == 2 else { continue }
                    let start = srtTimeToSeconds(parts[0].trimmingCharacters(in: .whitespaces))
                    let end = srtTimeToSeconds(parts[1].trimmingCharacters(in: .whitespaces))
                    let text = lines[(i+1)...].joined(separator: "\n")
                    if !text.isEmpty {
                        result.append((start, end, text))
                    }
                    break
                }
            }
        }
        return result
    }

    private func srtTimeToSeconds(_ time: String) -> Double {
        // 00:00:23,500 or 00:00:23
        let cleaned = time.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count == 3 else { return 0 }
        let h = Double(parts[0]) ?? 0
        let m = Double(parts[1]) ?? 0
        let s = Double(parts[2]) ?? 0
        return h * 3600 + m * 60 + s
    }

    // MARK: - 自渲染字幕样式

    /// 设置字幕字号
    public func setSubtitleFontSize(_ size: CGFloat) {
        subtitleLabel.font = .boldSystemFont(ofSize: size)
    }

    /// 设置字幕颜色
    public func setSubtitleTextColor(_ color: UIColor) {
        subtitleLabel.textColor = color
    }

    /// 设置字幕背景色
    public func setSubtitleBackgroundColor(_ color: UIColor) {
        subtitleLabel.backgroundColor = color
    }

    /// 字幕样式预设
    public enum SubtitleStylePreset {
        case defaultStyle   // 白色 16pt
        case largeWhite     // 白色 22pt
        case mediumYellow   // 黄色 18pt
        case smallCyan      // 青色 14pt
    }

    /// 应用字幕样式预设（自渲染版本）
    public func applySubtitleStylePreset(_ preset: SubtitleStylePreset) {
        switch preset {
        case .defaultStyle:
            subtitleLabel.font = .boldSystemFont(ofSize: 16)
            subtitleLabel.textColor = .white
            subtitleLabel.backgroundColor = .clear
        case .largeWhite:
            subtitleLabel.font = .boldSystemFont(ofSize: 22)
            subtitleLabel.textColor = .white
            subtitleLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        case .mediumYellow:
            subtitleLabel.font = .boldSystemFont(ofSize: 18)
            subtitleLabel.textColor = .yellow
            subtitleLabel.backgroundColor = .clear
        case .smallCyan:
            subtitleLabel.font = .boldSystemFont(ofSize: 14)
            subtitleLabel.textColor = .cyan
            subtitleLabel.backgroundColor = .clear
        }
    }

    /// 修复非标准 SRT 格式（缺序号、不完整时间戳、多余空行等）
    private func fixSrtContent(_ content: String) -> String {
        let timePattern = try! NSRegularExpression(pattern: #"(\d{2}:\d{2}:\d{2}[,\.]?\d{0,3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]?\d{0,3})"#)
        let lines = content.components(separatedBy: "\n")

        // 第一遍：找出所有时间戳行的索引
        var timeLineIndices: [Int] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if timePattern.firstMatch(in: trimmed, range: range) != nil {
                timeLineIndices.append(i)
            }
        }

        // 第二遍：每个时间戳到下一个时间戳之间，非空且非纯数字的行就是字幕文字
        var result = ""
        for (idx, timeIdx) in timeLineIndices.enumerated() {
            let timeLine = lines[timeIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let nextBound = idx + 1 < timeLineIndices.count ? timeLineIndices[idx + 1] : lines.count

            var textLines: [String] = []
            for j in (timeIdx + 1)..<nextBound {
                let trimmed = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if trimmed.allSatisfy({ $0.isNumber }) { continue }
                textLines.append(trimmed)
            }
            if textLines.isEmpty { continue }

            let parts = timeLine.components(separatedBy: " --> ")
            guard parts.count == 2 else { continue }
            let start = fixTimestamp(parts[0].trimmingCharacters(in: .whitespaces))
            let end = fixTimestamp(parts[1].trimmingCharacters(in: .whitespaces))
            result += "\(idx + 1)\n\(start) --> \(end)\n\(textLines.joined(separator: "\n"))\n\n"
        }

        print("📝 [字幕] SRT 修复: \(timeLineIndices.count) 条, 有效 \(result.components(separatedBy: "\n\n").count - 1) 条")
        return result
    }

    /// 补全时间戳 00:00:06 → 00:00:06,000
    private func fixTimestamp(_ ts: String) -> String {
        var t = ts
        if !t.contains(",") && !t.contains(".") {
            t += ",000"
        } else {
            if let sepIdx = t.firstIndex(of: ",") ?? t.firstIndex(of: ".") {
                let ms = t[t.index(after: sepIdx)...]
                if ms.count < 3 {
                    t = String(t[...sepIdx]) + ms.padding(toLength: 3, withPad: "0", startingAt: 0)
                }
            }
            t = t.replacingOccurrences(of: ".", with: ",")
        }
        return t
    }

    /// 获取当前字幕语言
    public func getCurrentSubtitleLang() -> String? {
        return currentSubtitleLang
    }

    /// 获取字幕轨列表
    public func getSubtitleTracks() -> [SubtitleTrack] {
        return subtitleTracks
    }

    /// 配置字幕样式
    /// - Parameters:
    ///   - scale: 字体缩放（默认 1.0）
    ///   - bottomMargin: 距离底部距离 [0.0, 1.0]（默认 0.05）
    ///   - fontName: 字体名称（默认 "Arial"）
    ///   - textColor: 文字颜色 RGBA Hex（默认 0xFFFFFF00 白色）
    ///   - outlineWidth: 边框宽度（默认 2.0）
    ///   - outlineColor: 边框颜色 RGBA Hex（默认 0x00000000 黑色）
    public func configureSubtitleStyle(
        scale: Float = 1.0,
        bottomMargin: Float = 0.05,
        fontName: String = "Arial",
        textColor: UInt32 = 0xFFFFFF00,
        outlineWidth: Float = 2.0,
        outlineColor: UInt32 = 0x00000000
    ) {
        subtitleManager?.configureStyle(
            scale: scale,
            bottomMargin: bottomMargin,
            fontName: fontName,
            textColor: textColor,
            outlineWidth: outlineWidth,
            outlineColor: outlineColor
        )
    }

    /// 应用预设字幕样式
    /// - Parameter style: 预设样式枚举
    public func applyPresetSubtitleStyle(_ style: SubtitleManager.SubtitleStyle) {
        subtitleManager?.applyPresetStyle(style)
    }

    /// 设置字幕延迟
    /// - Parameter delay: 延迟时间（秒），正值延迟显示，负值提前显示
    public func setSubtitleDelay(_ delay: Float) {
        subtitleManager?.setSubtitleDelay(delay)
    }

    /// 获取当前字幕延迟
    /// - Returns: 延迟时间（秒）
    public func getSubtitleDelay() -> Float {
        return subtitleManager?.getSubtitleDelay() ?? 0.0
    }

    /// 获取已加载的字幕列表
    /// - Returns: 字幕 URL 数组
    public func getLoadedSubtitles() -> [URL] {
        return subtitleManager?.getLoadedSubtitles() ?? []
    }

    // MARK: - 播放速度控制

    /// 设置播放速度
    /// - Parameter speed: 播放速度倍率（0.5 ~ 2.0）
    public func setSpeed(_ speed: Float) {
        playbackSpeedManager?.setPlaybackSpeed(speed)
    }

    /// 获取当前播放速度
    /// - Returns: 当前速度倍率
    public func getSpeed() -> Float {
        return playbackSpeedManager?.getCurrentSpeed() ?? 1.0
    }

    /// 切换到下一个速度
    /// 按照支持的速度列表循环切换：0.5x → 0.75x → 1.0x → 1.25x → 1.5x → 2.0x → 0.5x ...
    public func switchToNextPlaybackSpeed() {
        playbackSpeedManager?.switchToNextSpeed()
    }

    /// 重置为正常速度（1.0x）
    public func resetPlaybackSpeed() {
        playbackSpeedManager?.resetToNormalSpeed()
    }

    /// 应用播放速度预设
    /// - Parameter preset: 速度预设枚举
    public func applyPlaybackSpeedPreset(_ preset: PlaybackSpeedManager.SpeedPreset) {
        playbackSpeedManager?.applySpeedPreset(preset)
    }

    /// 获取速度描述文本
    /// - Returns: 描述文本（如 "正常"、"1.5x 快速"）
    public func getPlaybackSpeedDescription() -> String {
        let speed = getSpeed()
        return playbackSpeedManager?.getSpeedDescription(speed) ?? "正常"
    }

    // MARK: - 画面比例控制

    /// 设置画面比例模式
    /// - Parameter mode: 画面比例模式
    public func setAspectRatio(_ mode: AspectRatioManager.AspectRatioMode) {
        aspectRatioManager?.setAspectRatio(mode)
    }

    /// 获取当前画面比例模式
    /// - Returns: 当前画面比例模式
    public func getCurrentAspectRatio() -> AspectRatioManager.AspectRatioMode {
        return aspectRatioManager?.getCurrentAspectRatio() ?? .original
    }

    /// 切换到下一个画面比例模式
    /// 循环顺序：原始尺寸 → 16:9 → 4:3 → 鋪滿全屏 → 原始尺寸
    public func switchToNextAspectRatio() {
        aspectRatioManager?.switchToNextAspectRatio()
    }

    /// 重置为原始尺寸模式
    public func resetAspectRatio() {
        aspectRatioManager?.resetToFitMode()
    }

    /// 获取画面比例描述文本
    /// - Returns: 描述文本（如 "原始尺寸"、"16:9"）
    public func getAspectRatioDescription() -> String {
        return aspectRatioManager?.getAspectRatioDescription() ?? "原始尺寸"
    }

    // MARK: - 播放時間

    /// 获取当前播放位置
    /// - Returns: 当前播放位置（秒）
    public func getPosition() -> TimeInterval {
        return player?.currentPlaybackTime ?? 0
    }

    /// 获取视频总时长
    /// - Returns: 视频总时长（秒）
    public func getDuration() -> TimeInterval {
        return player?.duration ?? 0
    }

    /// 跳转到指定位置
    /// - Parameter ms: 目标位置（毫秒）
    public func seekTo(_ ms: Int) {
        let seconds = TimeInterval(ms) / 1000.0
        player?.currentPlaybackTime = seconds
        // 同步外部音频
        if let audioPlayer = externalAudioPlayer {
            if seconds >= 0 && seconds < audioPlayer.duration {
                audioPlayer.currentTime = seconds
            } else if seconds >= audioPlayer.duration {
                audioPlayer.pause()
            }
        }
    }

    /// 切换播放/暂停状态
    public func togglePlay() {
        if player?.isPlaying() == true {
            pause()
        } else {
            play()
        }
    }

    /// 设置循环播放
    /// - Parameter looping: 是否循环播放
    public func setLooping(_ looping: Bool) {
        isLooping = looping
    }

    /// 获取循环播放状态
    /// - Returns: 是否循环播放
    public func getLooping() -> Bool {
        return isLooping
    }

    /// 获取播放状态
    /// - Returns: 是否正在播放
    public func isPlaying() -> Bool {
        return player?.isPlaying() ?? false
    }

    /// 设置播放音量
    /// - Parameter volume: 音量值（0.0 ~ 1.0）
    public func setPlaybackVolume(_ volume: Float) {
        player?.playbackVolume = volume
    }

    // MARK: - 公开回调

    /// 播放完成时的回调
    public var onCompleted: (() -> Void)?

    /// 播放错误时的回调
    /// - Parameter: 错误信息
    public var onError: ((String) -> Void)?

    /// 缓冲进度更新时的回调
    /// - Parameter: 缓冲位置（秒）
    public var onBuffering: ((TimeInterval) -> Void)?

    // MARK: - Deprecated API（旧方法名兼容）

    /// 已废弃，请使用 `setVideoConfig(url:useProxy:)`
    @available(*, deprecated, renamed: "setVideoConfig(url:useProxy:)")
    public func setupPlayer(with url: String, isCrypt: Bool = false, useProxy: Bool = false) {
        setVideoConfig(url: url, useProxy: useProxy)
    }

    /// 已废弃，请使用 `release()`
    @available(*, deprecated, renamed: "release()")
    public func shutdown() {
        release()
    }

    /// 已废弃，请使用 `getPosition()`
    @available(*, deprecated, renamed: "getPosition()")
    public func getCurrentTime() -> TimeInterval {
        return getPosition()
    }

    /// 已废弃，请使用 `setSpeed(_:)`
    @available(*, deprecated, renamed: "setSpeed(_:)")
    public func setPlaybackSpeed(_ speed: Float) {
        setSpeed(speed)
    }

    /// 已废弃，请使用 `getSpeed()`
    @available(*, deprecated, renamed: "getSpeed()")
    public func getCurrentPlaybackSpeed() -> Float {
        return getSpeed()
    }

    // MARK: - 广告控制

    /// 显示片头广告
    /// - Parameter config: 片头广告配置
    public func showPrerollAd(config: PrerollAdConfig) {
        // 隐藏控制视图
        controlView.hide(animated: false)
        // 停止进度更新
        stopProgressTimer()
        // 重置进度显示为 0
        controlView.updateProgress(current: 0, duration: player?.duration ?? 0)

        // 包裝原始的 onCompleted 回調，在廣告結束後啟動彈幕
        var wrappedConfig = config
        let originalOnCompleted = config.onCompleted
        wrappedConfig.onCompleted = { [weak self] in
            // 廣告結束後啟動彈幕系統
            self?.startDanmakuSystem()
            // 調用原始回調
            originalOnCompleted?()
        }

        // 显示广告
        adManager?.showPrerollAd(config: wrappedConfig)
    }

    /// 跳过片头广告（VIP 功能）
    public func skipPrerollAd() {
        adManager?.skipPrerollAd()
    }

    /// 配置暂停广告（不立即显示，暂停时自动显示，播放时自动隐藏）
    /// - Parameter config: 暂停广告配置
    public func configurePauseAd(config: PauseAdConfig) {
        adManager?.configurePauseAd(config: config)
    }

    /// 显示暂停广告
    /// - Parameter config: 暂停广告配置
    public func showPauseAd(config: PauseAdConfig) {
        adManager?.showPauseAd(config: config)
    }

    /// 隐藏暂停广告
    public func hidePauseAd() {
        adManager?.hidePauseAd()
    }

    /// 是否正在播放片头广告
    /// - Returns: true 表示正在播放片头广告
    public func isShowingPrerollAd() -> Bool {
        return adManager?.isShowingPrerollAd() ?? false
    }

    /// 是否正在显示暂停广告
    /// - Returns: true 表示正在显示暂停广告
    public func isShowingPauseAd() -> Bool {
        return adManager?.isShowingPauseAd() ?? false
    }

    // MARK: - 中插广告

    /// 添加中插广告（在指定时间暂停视频，全屏显示广告）
    public func addMidrollAd(config: MidrollAdConfig) {
        adManager?.addMidrollAd(config: config)
    }

    /// 清除所有中插广告
    public func clearMidrollAds() {
        adManager?.clearMidrollAds()
    }

    // MARK: - 浮层广告

    /// 添加浮层广告（在指定时间淡入显示，不暂停视频）
    public func addOverlayAd(config: OverlayAdConfig) {
        adManager?.addOverlayAd(config: config)
    }

    /// 清除所有浮层广告
    public func clearOverlayAds() {
        adManager?.clearOverlayAds()
    }

    // MARK: - 音视频分轨

    /// 设置外部音频 URL（音视频分轨播放）
    /// - Parameter audioURL: 音频文件 URL（mp3/aac 等）
    public func setExternalAudio(url: String) {
        // HTTP → HTTPS 升级（ATS 要求）
        var url = url
        if url.hasPrefix("http://") && !url.hasPrefix("http://127.0.0.1") && !url.hasPrefix("http://localhost") {
            url = url.replacingOccurrences(of: "http://", with: "https://")
        }
        guard let audioURL = URL(string: url) else {
            print("❌ [分轨] 无效的音频 URL: \(url)")
            return
        }
        // 释放旧的外部音频
        stopExternalAudio()
        externalAudioURL = audioURL
        print("🎵 [分轨] 设置外部音频: \(url)")

        // 下载到临时文件，避免整个音频占用内存
        audioDownloadTask = URLSession.shared.downloadTask(with: audioURL) { [weak self] localURL, _, error in
            guard let self = self, let localURL = localURL else {
                print("❌ [分轨] 音频下载失败: \(error?.localizedDescription ?? "无数据")")
                return
            }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("split_audio_\(UUID().uuidString).mp3")
            do {
                try FileManager.default.moveItem(at: localURL, to: tempURL)
            } catch {
                print("❌ [分轨] 音频文件移动失败: \(error)")
                return
            }

            DispatchQueue.main.async {
                // 检查是否已释放或 URL 已变更
                guard self.externalAudioURL == audioURL else { return }
                do {
                    // 设置音频会话
                    try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
                    try AVAudioSession.sharedInstance().setActive(true)

                    self.externalAudioPlayer = try AVAudioPlayer(contentsOf: tempURL)
                    self.externalAudioPlayer?.prepareToPlay()
                    let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path)
                    let fileSize = (attrs?[.size] as? UInt64) ?? 0
                    print("✅ [分轨] 音频准备就绪 (\(fileSize / 1024)KB)")

                    // 视频已在播放或已调用过 play()，立即开始音频
                    if self.player?.isPlaying() == true || self.pendingAudioPlay {
                        self.externalAudioPlayer?.play()
                        self.syncAudioToVideo()
                        self.startAudioSyncTimer()
                        self.pendingAudioPlay = false
                    }
                } catch {
                    print("❌ [分轨] 音频初始化失败: \(error)")
                }
            }
        }
        audioDownloadTask?.resume()
    }

    /// 同步音频位置到视频
    private func syncAudioToVideo() {
        guard let player = player, let audioPlayer = externalAudioPlayer else { return }
        let videoTime = player.currentPlaybackTime
        if videoTime.isFinite && videoTime >= 0 && videoTime < audioPlayer.duration {
            let diff = abs(audioPlayer.currentTime - videoTime)
            // 偏差超过 0.3 秒才校准，避免频繁跳转
            if diff > 0.3 {
                audioPlayer.currentTime = videoTime
                print("🔄 [分轨] 音频同步校准: video=\(String(format: "%.2f", videoTime))s audio=\(String(format: "%.2f", audioPlayer.currentTime))s")
            }
        }
    }

    private func startAudioSyncTimer() {
        stopAudioSyncTimer()
        guard externalAudioPlayer != nil else { return }
        audioSyncTimer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.syncAudioToVideo()
        }
        RunLoop.main.add(audioSyncTimer!, forMode: .common)
    }

    private func stopAudioSyncTimer() {
        audioSyncTimer?.invalidate()
        audioSyncTimer = nil
    }

    private func stopExternalAudio() {
        audioDownloadTask?.cancel()
        audioDownloadTask = nil
        externalAudioPlayer?.stop()
        externalAudioPlayer = nil
        stopAudioSyncTimer()
        externalAudioURL = nil
    }

    // MARK: - 彈幕系統

    /// 設置彈幕系統（僅設置 UI，不啟動彈幕）
    private func setupDanmakuSystem() {
        guard let danmakuManager = danmakuManager else { return }

        // 使用 PlayerControlView 内建的弹幕控制
        // 設置回調
        controlView.onDanmakuToggle = { [weak danmakuManager] enabled in
            danmakuManager?.setEnabled(enabled)
        }

        controlView.onSendDanmaku = { [weak danmakuManager] text in
            danmakuManager?.sendDanmaku(text: text) { result in
                switch result {
                case .success:
                    DXPlayerLogger.info("✅ [彈幕] 發送成功")
                case .failure(let error):
                    DXPlayerLogger.error("❌ [彈幕] 發送失敗: \(error.localizedDescription)")
                }
            }
        }

        controlView.onDanmakuSettings = { [weak self] in
            self?.showDanmakuSettings()
        }

        // 注意：不在這裡啟動彈幕，等廣告結束後再啟動
        DXPlayerLogger.info("📺 [彈幕] 彈幕系統 UI 已設置，等待啟動")
    }

    /// 啟動彈幕系統（廣告結束後調用）
    public func startDanmakuSystem() {
        guard let danmakuManager = danmakuManager else { return }

        // 避免重複啟動
        guard !isDanmakuStarted else {
            DXPlayerLogger.debug("📺 [彈幕] 彈幕系統已啟動，跳過")
            return
        }

        isDanmakuStarted = true
        DXPlayerLogger.info("🚀 [彈幕] 啟動彈幕系統")

        // 顯示彈幕覆蓋層
        danmakuManager.show()

        // 確保彈幕初始為開啟狀態（applySettings 可能從 UserDefaults 讀到過期的 false 值）
        danmakuManager.setEnabled(true)
        controlView.setDanmakuEnabled(true)

        // 設置本地測試資料來源
        let dataSource = LocalDanmakuDataSource()
        danmakuManager.setDataSource(dataSource)
        dataSource.start(context: [:])
    }

    /// 顯示彈幕設定面板
    private func showDanmakuSettings() {
        guard let danmakuManager = danmakuManager else { return }

        // 獲取 window 來顯示全螢幕彈窗
        guard let window = self.window else {
            DXPlayerLogger.warning("⚠️ [彈幕設定] 無法獲取 window")
            return
        }

        let settingsView = DanmakuSettingsView(frame: window.bounds)

        // 添加到 window 上，覆蓋整個畫面
        window.addSubview(settingsView)

        // 載入當前設定
        let currentSettings = DanmakuSettings.load()
        settingsView.loadSettings(currentSettings)

        // 設定變更回調
        settingsView.onSettingsChanged = { [weak danmakuManager] newSettings in
            danmakuManager?.updateSettings(newSettings)
            newSettings.save()
        }

        // 顯示設定面板
        settingsView.show(animated: true)
    }

    /// 設定彈幕資料來源
    /// - Parameter dataSource: 彈幕資料來源
    public func setDanmakuDataSource(_ dataSource: DanmakuDataSource) {
        danmakuManager?.setDataSource(dataSource)
    }

    /// 發送彈幕
    /// - Parameters:
    ///   - text: 彈幕文字
    ///   - completion: 完成回調
    public func sendDanmaku(text: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        danmakuManager?.sendDanmaku(text: text, completion: completion)
    }

    /// 設定彈幕開關
    /// - Parameter enabled: 是否啟用
    public func setDanmakuEnabled(_ enabled: Bool) {
        danmakuManager?.setEnabled(enabled)
        controlView.setDanmakuEnabled(enabled)
    }

    /// 更新彈幕設定
    /// - Parameter settings: 彈幕設定
    public func updateDanmakuSettings(_ settings: DanmakuSettings) {
        danmakuManager?.updateSettings(settings)
    }

    /// 清空彈幕
    public func clearDanmaku() {
        danmakuManager?.clear()
    }

    /// 彈幕是否啟用
    public var isDanmakuEnabled: Bool {
        return danmakuManager?.isEnabled ?? false
    }

    // MARK: - 缩略图预览系统

    /// 设置缩略图预览
    /// - Parameters:
    ///   - videoURL: 视频 URL
    ///   - metadataURL: 元数据 URL（可选）
    private func setupThumbnailPreview(videoURL: URL, metadataURL: URL? = nil) {
        DXPlayerLogger.info("🖼️ [缩略图预览] 开始初始化")
        DXPlayerLogger.info("🖼️ [缩略图预览] 视频 URL: \(videoURL)")
        DXPlayerLogger.info("🖼️ [缩略图预览] 元数据 URL: \(metadataURL?.absoluteString ?? "无")")

        // 初始化缩略图预览管理器
        let manager = ThumbnailPreviewManager()
        manager.configure(videoURL: videoURL, metadataURL: metadataURL)
        thumbnailPreviewManager = manager

        DXPlayerLogger.info("🖼️ [缩略图预览] 管理器已创建并配置")

        // 将管理器传递给控制视图
        controlView.thumbnailPreviewManager = manager

        DXPlayerLogger.info("🖼️ [缩略图预览] 已传递给 controlView")
        DXPlayerLogger.info("🖼️ [缩略图预览] controlView.thumbnailPreviewManager: \(controlView.thumbnailPreviewManager != nil ? "✅" : "❌")")
        DXPlayerLogger.info("🖼️ [缩略图预览] 初始化完成")
    }

    /// 设置缩略图元数据 URL（用于雪碧图模式）
    /// - Parameter metadataURL: 元数据 URL
    public func setThumbnailMetadata(url: URL) {
        guard let videoURL = player?.contentURL() else {
            DXPlayerLogger.warning("⚠️ [缩略图预览] 视频 URL 未设置")
            return
        }

        // 重新配置管理器
        thumbnailPreviewManager?.configure(videoURL: videoURL, metadataURL: url)
        DXPlayerLogger.info("🖼️ [缩略图预览] 已更新元数据 URL")
    }

    /// 清除缩略图预览缓存
    public func clearThumbnailCache() {
        thumbnailPreviewManager?.clearCache()
        DXPlayerLogger.info("🖼️ [缩略图预览] 已清除缓存")
    }

    /// 设置外部解析器（用于本地 VTT + Sprite 文件）
    /// - Parameter parser: 已解析好的雪碧图解析器
    public func setThumbnailParser(_ parser: ThumbnailSpriteParser) {
        thumbnailPreviewManager?.setParser(parser)
        DXPlayerLogger.info("🖼️ [缩略图预览] 已设置外部解析器")
    }

    // MARK: - 全屏控制

    /// 判斷视频是否为橫向（寬 > 高）
    private func isVideoLandscape() -> Bool {
        guard videoSize.width > 0 && videoSize.height > 0 else {
            // 如果还没有获取到视频尺寸，默认为橫向
            return true
        }
        return videoSize.width > videoSize.height
    }

    /// 进入全屏
    public func enterFullScreen() {
        print("enterFullScreen 被调用")
        guard !isFullScreen else {
            print("已經是全屏状态，返回")
            return
        }

        // ✅ 如果播放器处于暂停状态，进入全屏时自動播放
        let wasPlaying = player?.isPlaying() ?? false
        if !wasPlaying && !isShowingReplay {
            print("📺 播放器暂停中，进入全屏时自動播放")
            play()
        }

        // 判斷视频方向
        let isLandscape = isVideoLandscape()
        print("视频是橫向：\(isLandscape), 视频尺寸：\(videoSize)")

        // 發送进入全屏通知，攜帶视频方向信息
        NotificationCenter.default.post(
            name: .playerDidEnterFullScreen,
            object: nil,
            userInfo: [PlayerFullScreenInfo.isVideoLandscape: isLandscape]
        )
        
        // ✅ 通过 UserDefaults 或通知机制传递状态，避免直接引用 AppDelegate
        // 注意：使用 SDK 的 App 需要在 AppDelegate 中監聽这些通知并更新方向设置
        UserDefaults.standard.set(true, forKey: "DXPlayerSDK.isPlayerFullScreen")
        UserDefaults.standard.set(isLandscape, forKey: "DXPlayerSDK.isVideoLandscape")

        // 通知系統尝试旋转（尊重系統方向锁定设置）
        UIViewController.attemptRotationToDeviceOrientation()

        // 監聽设备旋转通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )

        // 保存原始状态
        originalFrame = frame
        originalSuperview = superview

        // 保存并停用父视圖对这个视圖的約束
        if let superview = superview {
            originalConstraints = superview.constraints.filter { constraint in
                (constraint.firstItem as? UIView) == self || (constraint.secondItem as? UIView) == self
            }
            NSLayoutConstraint.deactivate(originalConstraints)
            print("保存了 \(originalConstraints.count) 个約束")
        }

        print("保存原始状态：frame = \(originalFrame), superview = \(String(describing: originalSuperview))")

        // 获取 Window - 尝试多種方式
        var window: UIWindow?
        if #available(iOS 13.0, *) {
            window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }

        if window == nil {
            window = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
        }

        if window == nil {
            window = UIApplication.shared.keyWindow
        }

        guard let window = window else {
            print("错误：无法获取 window")
            return
        }

        print("获取到 window: \(window), bounds = \(window.bounds)")

        // 转换坐标到 window
        let frameInWindow = convert(bounds, to: window)
        print("转换後的 frame: \(frameInWindow)")

        // ✅ 保存容器內部的約束（controlView 的定位約束）
        // 这些約束在全屏时需要停用，退出时重新激活
        containerConstraints = constraints.filter { constraint in
            (constraint.firstItem as? UIView) == controlView || (constraint.secondItem as? UIView) == controlView
        }
        NSLayoutConstraint.deactivate(containerConstraints)
        print("保存了 \(containerConstraints.count) 个容器內部約束（controlView）")

        // 关键修復：禁用 Auto Layout，使用手動布局
        translatesAutoresizingMaskIntoConstraints = true

        // 关键修復：禁用 autoresizingMask，防止自動调整
        autoresizingMask = []

        // 控制层保持 Auto Layout，使用约束填充整个容器
        // 这样可以正确处理横屏时的 safe area insets
        controlView.translatesAutoresizingMaskIntoConstraints = false
        fullScreenControlViewConstraints = [
            controlView.topAnchor.constraint(equalTo: topAnchor),
            controlView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(fullScreenControlViewConstraints)

        // ✅ 保持手勢反饋 UI 的 Auto Layout 約束有效
        // 这些视圖使用約束保持居中，不要改变它們的布局方式
        seekPreviewContainer.translatesAutoresizingMaskIntoConstraints = false
        volumeBrightnessContainer.translatesAutoresizingMaskIntoConstraints = false
        forwardSeekIcon.translatesAutoresizingMaskIntoConstraints = false
        backwardSeekIcon.translatesAutoresizingMaskIntoConstraints = false
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        // 移除并添加到 window
        removeFromSuperview()
        window.addSubview(self)
        frame = frameInWindow
        print("已添加到 window，开始動画")
        print("当前 autoresizingMask: \(autoresizingMask), translatesAutoresizingMaskIntoConstraints: \(translatesAutoresizingMaskIntoConstraints)")

        // 动画到全屏
        UIView.animate(withDuration: 0.3, animations: {
            self.frame = window.bounds
            // controlView 使用 autoresizingMask，会自動调整
            print("動画中，目标 frame: \(window.bounds)")
            print("動画执行时的实际 frame: \(self.frame)")
        }) { finished in
            self.isFullScreen = true

            // 強制设置一次，确保正确
            if self.frame.size != window.bounds.size {
                print("警告：frame 不正确，強制修正")
                self.frame = window.bounds
            }

            // 确保 controlView 填滿容器
            self.controlView.frame = self.bounds
            print("已进入全屏模式，finished = \(finished), frame = \(self.frame)")
            print("控制层 frame: \(self.controlView.frame)")

            self.controlView.updateFullScreenState(isFullScreen: true)

            // 显示控制层
            self.controlView.show(animated: true, autoHide: true)
        }
    }

    /// 退出全屏
    public func exitFullScreen() {
        guard isFullScreen else { return }

        // 發送退出全屏通知，通知 ViewController 锁定方向
        NotificationCenter.default.post(name: .playerDidExitFullScreen, object: nil)

        // ✅ 通过 UserDefaults 清除全屏状态
        UserDefaults.standard.set(false, forKey: "DXPlayerSDK.isPlayerFullScreen")
        
        // 通知系統尝试旋转回豎向（尊重系統方向锁定设置）
        UIViewController.attemptRotationToDeviceOrientation()

        // 移除旋转監聽
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )

        // 先移除视圖并恢復到原始父视圖
        removeFromSuperview()
        if let originalSuperview = self.originalSuperview {
            originalSuperview.addSubview(self)
        }

        // 停用全屏时的 controlView 约束
        NSLayoutConstraint.deactivate(fullScreenControlViewConstraints)
        fullScreenControlViewConstraints = []

        // 恢復容器的 Auto Layout
        self.translatesAutoresizingMaskIntoConstraints = false
        self.autoresizingMask = []

        // 控制层也恢復 Auto Layout
        self.controlView.translatesAutoresizingMaskIntoConstraints = false
        self.controlView.autoresizingMask = []

        // ✅ 确保手勢反饋 UI 和 loading 保持 Auto Layout（它們一直都使用約束）
        self.seekPreviewContainer.translatesAutoresizingMaskIntoConstraints = false
        self.volumeBrightnessContainer.translatesAutoresizingMaskIntoConstraints = false
        self.forwardSeekIcon.translatesAutoresizingMaskIntoConstraints = false
        self.backwardSeekIcon.translatesAutoresizingMaskIntoConstraints = false
        self.loadingView.translatesAutoresizingMaskIntoConstraints = false
        self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        // 重新激活保存的約束（父视圖对容器的約束）
        NSLayoutConstraint.activate(self.originalConstraints)
        print("重新激活了 \(self.originalConstraints.count) 个父视圖約束")

        // 重新激活容器內部的約束（只有 controlView 的定位約束需要重新激活）
        NSLayoutConstraint.activate(self.containerConstraints)
        print("重新激活了 \(self.containerConstraints.count) 个容器內部約束")

        // 強制布局更新，讓 Auto Layout 计算正确的 frame
        self.setNeedsLayout()
        self.layoutIfNeeded()

        self.isFullScreen = false
        self.controlView.updateFullScreenState(isFullScreen: false)
        print("已退出全屏模式，frame = \(self.frame)")
    }

    /// 处理设备旋转
    /// 根據 spec/fullscreen-behavior.md 規格：
    ///
    /// 非全屏狀態（無旋轉鎖定時才會觸發此方法）：
    /// - 橫放手機：播放器內容跟隨旋轉為橫屏顯示（但不進入全屏模式）
    /// - 豎放手機：播放器內容跟隨旋轉為豎屏顯示
    ///
    /// 全屏狀態（無旋轉鎖定時才會觸發此方法）：
    /// - 180° 橫屏（左右翻轉）：橫屏全屏改變方向，但仍是橫屏全屏
    /// - 豎屏：依然保持橫屏全屏（不退出全屏）
    ///
    // MARK: - 锁屏/后台暂停

    @objc private func handleAppWillResignActive() {
        if player?.isPlaying() == true {
            wasPlayingBeforeResignActive = true
            pause()
            print("⏸️ [生命周期] 进入后台/锁屏，暂停播放")
        } else {
            wasPlayingBeforeResignActive = false
        }
    }

    @objc private func handleAppDidBecomeActive() {
        if wasPlayingBeforeResignActive {
            wasPlayingBeforeResignActive = false
            play()
            print("▶️ [生命周期] 回到前台，恢复播放")
        }
    }

    /// 注意：有旋轉鎖定時，此方法不會被調用（或設備方向不會改變）
    @objc private func handleDeviceOrientationChange() {
        let deviceOrientation = UIDevice.current.orientation

        // 獲取界面方向（更可靠，特別是在模擬器上）
        var interfaceOrientation: UIInterfaceOrientation = .portrait
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                interfaceOrientation = windowScene.interfaceOrientation
            }
        } else {
            interfaceOrientation = UIApplication.shared.statusBarOrientation
        }

        NSLog("📱 方向變化通知 - 設備方向: %d, 界面方向: %d", deviceOrientation.rawValue, interfaceOrientation.rawValue)
        NSLog("📱 當前全屏: %d, 當前角度: %f", isFullScreen ? 1 : 0, currentRotationAngle)

        // 使用設備方向來判斷（實機上更準確）
        // 注意：界面方向可能因 App 不支援橫屏而始終為 portrait
        let isDeviceLandscape = deviceOrientation == .landscapeLeft || deviceOrientation == .landscapeRight
        let isDevicePortrait = deviceOrientation == .portrait

        // 忽略 faceUp, faceDown, unknown, portraitUpsideDown 等無效方向
        guard isDeviceLandscape || isDevicePortrait else {
            NSLog("📱 無效的設備方向，跳過")
            return
        }

        NSLog("📱 isDeviceLandscape: %d, isDevicePortrait: %d", isDeviceLandscape ? 1 : 0, isDevicePortrait ? 1 : 0)

        // 根據規格：
        // - 非全屏時：不響應設備旋轉（因為 App 只支援豎屏，用 transform 旋轉會破圖）
        // - 全屏時：不響應設備旋轉（全屏使用 transform 實現，保持固定方向）
        //
        // 如果未來需要支援非全屏時的橫屏顯示，應該讓 App 支援橫屏方向，
        // 而不是用 transform 旋轉播放器視圖。
        NSLog("📱 忽略設備旋轉通知（isFullScreen: %d）", isFullScreen ? 1 : 0)
    }

    // MARK: - 播放器通知

    private func observePlayerNotifications() {
        guard let player = player else { return }

        // 播放状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackStateChange),
            name: .FSPlayerPlaybackStateDidChange,
            object: player
        )

        // 加载状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLoadStateChange),
            name: .FSPlayerLoadStateDidChange,
            object: player
        )

        // 播放完成
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackFinished),
            name: .FSPlayerDidFinish,
            object: player
        )
    }

    @objc private func handlePlaybackStateChange() {
        guard let player = player else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 如果正在播放廣告，忽略主播放器的狀態變化
            if self.adManager?.isShowingPrerollAd() == true {
                return
            }

            let isPlaying = player.isPlaying()
            print("📺 handlePlaybackStateChange - isPlaying: \(isPlaying), isShowingReplay: \(self.isShowingReplay)")

            // 如果正在显示重播圖标，不要覆蓋它
            if !self.isShowingReplay {
                self.controlView.updatePlaybackState(isPlaying: isPlaying)
            } else {
                print(" ⏭️  跳过更新：正在显示重播状态")
            }

            if isPlaying {
                // 如果开始播放，清除重播状态
                self.isShowingReplay = false
                self.startProgressTimer()
                // 自动隐藏暂停广告
                self.adManager?.handlePlayerPlaying()
            } else {
                self.stopProgressTimer()
                // 拖动进度条期间不显示暂停广告，只有真正暂停时才显示
                if !self.isUserSeeking {
                    self.adManager?.handlePlayerPaused()
                }
            }
        }
    }

    @objc private func handleLoadStateChange() {
        guard let player = player else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 如果正在播放廣告，忽略主播放器的加載狀態變化
            if self.adManager?.isShowingPrerollAd() == true {
                return
            }

            let isStalled = player.loadState.contains(.stalled)
            self.controlView.updateBuffering(isBuffering: isStalled)

            // 当视频可播放时，隐藏 loading
            if player.loadState.contains(.playable) {
                self.hideLoading()

                // 获取视频尺寸
                self.videoSize = player.naturalSize
                print("视频尺寸：\(player.naturalSize)")

                // 觸發播放器準備好的回調（只觸發一次）
                if let onReady = self.onPlayerReady {
                    self.onPlayerReady = nil  // 清除回調，避免重複觸發
                    onReady()
                }
            }
        }
    }

    @objc private func handlePlaybackFinished(notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 如果正在播放廣告，忽略主播放器的完成/錯誤通知
            if self.adManager?.isShowingPrerollAd() == true {
                print("⚠️ handlePlaybackFinished - 廣告播放中，忽略主播放器通知")
                return
            }

            self.stopProgressTimer()
            // 停止外部音频
            self.externalAudioPlayer?.pause()
            self.stopAudioSyncTimer()

            if let reason = notification.userInfo?[FSPlayerDidFinishReasonUserInfoKey] as? Int {
                switch reason {
                case FSFinishReason.playbackEnded.rawValue:
                    // 循环播放：直接重头播放
                    if self.isLooping {
                        self.player?.currentPlaybackTime = 0
                        self.externalAudioPlayer?.currentTime = 0
                        self.play()
                        print("🔁 循环播放：自动重头播放")
                        return
                    }
                    // 播放结束，重置到开始并显示重播圖标
                    self.player?.currentPlaybackTime = 0
                    self.isShowingReplay = true
                    self.controlView.updatePlaybackState(isPlaying: false, showReplay: true)
                    // 显示控制层，讓用戶看到重播按鈕（不自動隐藏）
                    self.controlView.show(animated: true, autoHide: false)
                    print("✅ 视频播放完畢，显示重播圖标和控制层")
                    self.onCompleted?()

                case FSFinishReason.playbackError.rawValue:
                    // 播放错误，顯示錯誤提示
                    print("❌ 播放错误")
                    self.showError(message: "播放失败\n请检查网络连接")
                    self.onError?("播放失败")

                default:
                    break
                }
            }
        }
    }

    // MARK: - 进度更新
    private func startProgressTimer() {
        stopProgressTimer()

        progressTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player = player else { return }

        // 广告播放期间不更新主视频进度
        if adManager?.isShowingPrerollAd() == true || adManager?.isShowingMidrollAd() == true {
            return
        }

        let current = player.currentPlaybackTime
        let duration = player.duration

        // 检查中插广告和浮层广告触发
        adManager?.checkMidrollTrigger(at: current)
        adManager?.checkOverlayTrigger(at: current)

        // 更新播放进度
        controlView.updateProgress(current: current, duration: duration)

        // 更新缓冲进度
        if duration > 0 {
            let playable = player.playableDuration
            let buffer = Float(playable / duration)
            controlView.updateBufferProgress(buffer)
            onBuffering?(playable)
        }
    }

    // MARK: - Loading 管理

    /// 显示 loading 指示器
    private func showLoading() {
        DispatchQueue.main.async { [weak self] in
            self?.loadingView.isHidden = false
            self?.loadingIndicator.startAnimating()
            // 确保 loading view 在最上层
            if let loadingView = self?.loadingView {
                self?.bringSubviewToFront(loadingView)
            }
            // 立即隐藏控制层（包括播放按鈕），避免與 loading 重疊
            self?.controlView.isHidden = true
            self?.controlView.alpha = 0
            self?.controlView.isUserInteractionEnabled = false  // 禁用交互
            // ✅ 強制隐藏中央播放按鈕，避免與 loading indicator 重疊
            self?.controlView.hideCenterPlayButton()
            print("🔄 showLoading - 已隐藏控制层和中央播放按鈕")
        }
    }

    /// 隐藏 loading 指示器
    private func hideLoading() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.loadingView.isHidden = true
            self.loadingIndicator.stopAnimating()

            // 显示控制层
            self.controlView.show(animated: true, autoHide: true)

            // ✅ 根据播放状态显示中央播放按鈕
            // 如果正在播放中，中央按鈕应該隐藏
            // 如果暂停或重播状态，中央按鈕应該显示
            self.controlView.showCenterPlayButtonIfNeeded()
            print("🔄 hideLoading - 已显示控制层，中央播放按鈕状态已更新")
        }
    }

    // MARK: - 錯誤處理

    /// 顯示播放錯誤提示
    private func showError(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 隱藏 loading
            self.loadingView.isHidden = true
            self.loadingIndicator.stopAnimating()

            // 設置錯誤信息並顯示
            self.errorLabel.text = message
            self.errorView.isHidden = false

            // 確保錯誤視圖在最上層
            self.bringSubviewToFront(self.errorView)

            // 隱藏控制層
            self.controlView.isHidden = true

            print("❌ showError - 顯示錯誤提示: \(message)")
        }
    }

    /// 隱藏播放錯誤提示
    private func hideError() {
        DispatchQueue.main.async { [weak self] in
            self?.errorView.isHidden = true
            print("✅ hideError - 隱藏錯誤提示")
        }
    }

    /// 重試播放
    @objc private func retryPlayback() {
        print("🔄 retryPlayback - 用戶點擊重試")

        // 如果正在播放廣告，不執行重試
        if adManager?.isShowingPrerollAd() == true {
            print("⚠️ retryPlayback - 廣告播放中，忽略重試")
            return
        }

        // 隱藏錯誤提示
        hideError()

        // 使用保存的配置重新設置播放器
        if let urlString = currentVideoURLString {
            print("🔄 retryPlayback - 重新設置播放器: \(urlString)")
            setVideoConfig(url: urlString, useProxy: currentUseProxy)
        } else {
            print("⚠️ retryPlayback - 沒有可用的視頻 URL")
        }
    }

    // MARK: - 清理

    deinit {
        release()
    }
}

// MARK: - PlayerControlViewDelegate

extension IJKPlayerContainerView: PlayerControlViewDelegate {

    func controlViewDidTapPlayPause() {
        guard let player = player else { return }

        // 检查是否处于重播状态
        if isShowingReplay {
            // 重播模式：重置到开始并播放
            print("点击重播按鈕，重新开始播放")
            isShowingReplay = false
            player.currentPlaybackTime = 0
            play()
        } else {
            // 正常播放/暂停切换
            if player.isPlaying() {
                pause()
            } else {
                play()
            }
        }
    }

    func controlViewDidTapFullScreen() {
        NSLog("🔄 全屏按鈕被点击，当前 isFullScreen: %d, isUsingTransformFullScreen: %d", isFullScreen ? 1 : 0, isUsingTransformFullScreen ? 1 : 0)

        // 切換旋轉狀態
        isFullScreen.toggle()

        if isFullScreen {
            // 進入全屏：旋轉到橫屏
            NSLog("🔄 準備進入全屏")
            rotateToLandscape()
        } else {
            // 退出全屏：旋轉回豎屏
            NSLog("🔄 準備退出全屏，isUsingTransformFullScreen: %d", isUsingTransformFullScreen ? 1 : 0)
            rotateToPortrait()
        }
    }

    /// 進入橫屏全屏
    /// 使用系統方向 API 強制旋轉到橫屏，不使用 CGAffineTransform
    /// 這樣鍵盤、Home Indicator 等系統 UI 會正確跟隨方向
    private func rotateToLandscape() {
        // 設置進入全屏標記
        isEnteringFullScreen = true

        // 設置全屏狀態
        UserDefaults.standard.set(true, forKey: "DXPlayerSDK.isPlayerFullScreen")

        // 不使用 transform 旋轉
        currentRotationAngle = 0

        NSLog("🔄 開始進入全屏（使用系統方向旋轉）")

        // 記錄進入全屏時的界面方向
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                fullScreenEntryOrientation = windowScene.interfaceOrientation
                lastDetectedInterfaceOrientation = windowScene.interfaceOrientation
            }
        } else {
            fullScreenEntryOrientation = UIApplication.shared.statusBarOrientation
            lastDetectedInterfaceOrientation = UIApplication.shared.statusBarOrientation
        }
        NSLog("📱 進入全屏，記錄界面方向: %d", fullScreenEntryOrientation.rawValue)

        // 獲取 window
        var window: UIWindow?
        if #available(iOS 13.0, *) {
            window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }
        if window == nil {
            window = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
        }
        if window == nil {
            window = UIApplication.shared.keyWindow
        }

        guard let window = window else {
            NSLog("❌ 無法獲取 window")
            return
        }

        // #3106 修復：記錄旋轉前的 window bounds，用於判斷系統是否真的旋轉了
        let windowBoundsBeforeRotation = window.bounds
        NSLog("📐 [DEBUG] 旋轉前 window bounds: %@", NSCoder.string(for: windowBoundsBeforeRotation))

        // 強制系統旋轉到橫屏
        forceRotateToLandscape()

        // 保存原始狀態
        if originalSuperview == nil {
            originalFrame = frame
            originalSuperview = superview
            NSLog("💾 保存原始狀態：frame = %@", NSCoder.string(for: originalFrame))

            if let superview = superview {
                originalConstraints = superview.constraints.filter { constraint in
                    (constraint.firstItem as? UIView) == self || (constraint.secondItem as? UIView) == self
                }
                NSLayoutConstraint.deactivate(originalConstraints)
            }

            containerConstraints = constraints.filter { constraint in
                (constraint.firstItem as? UIView) == controlView || (constraint.secondItem as? UIView) == controlView
            }
            NSLayoutConstraint.deactivate(containerConstraints)
        }

        // 禁用 Auto Layout，使用手動布局
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        controlView.translatesAutoresizingMaskIntoConstraints = true
        controlView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if let playerView = player?.view {
            playerView.translatesAutoresizingMaskIntoConstraints = true
            playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }

        // 移除並添加到 window
        removeFromSuperview()
        window.addSubview(self)

        // 強制顯示 controlView
        controlView.isHidden = false
        controlView.alpha = 1.0
        controlView.isUserInteractionEnabled = true

        // 延遲執行全屏動畫，等待系統方向旋轉完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }

            // 重新獲取 window（系統旋轉後尺寸會變化）
            var currentWindow: UIWindow?
            if #available(iOS 13.0, *) {
                currentWindow = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first { $0.isKeyWindow }
            }
            if currentWindow == nil {
                currentWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
            }
            guard let finalWindow = currentWindow else { return }

            let windowBoundsAfterRotation = finalWindow.bounds
            NSLog("📐 [DEBUG] 旋轉後 window bounds: %@", NSCoder.string(for: windowBoundsAfterRotation))

            // #3106 修復：比較旋轉前後的 bounds 是否改變
            // 如果 bounds 沒有改變（或只是從豎屏變到另一個豎屏尺寸），表示系統旋轉被鎖定
            let boundsChanged = abs(windowBoundsAfterRotation.width - windowBoundsBeforeRotation.width) > 1 ||
                               abs(windowBoundsAfterRotation.height - windowBoundsBeforeRotation.height) > 1
            let isWindowLandscape = windowBoundsAfterRotation.width > windowBoundsAfterRotation.height

            NSLog("📐 [DEBUG] boundsChanged: %d, isWindowLandscape: %d", boundsChanged ? 1 : 0, isWindowLandscape ? 1 : 0)

            if boundsChanged && isWindowLandscape {
                // 系統確實旋轉到了橫屏，使用正常的全屏模式
                self.isUsingTransformFullScreen = false
                NSLog("📐 [全屏] 系統已旋轉到橫屏，使用正常全屏模式")

                UIView.animate(withDuration: 0.3) {
                    self.frame = finalWindow.bounds
                    self.transform = .identity

                    if let playerView = self.player?.view {
                        playerView.frame = self.bounds
                    }
                    self.controlView.frame = self.bounds
                } completion: { _ in
                    self.finishFullScreenTransition(window: finalWindow)
                }
            } else {
                // 系統旋轉被鎖定，使用 transform 旋轉實現橫屏全屏
                self.isUsingTransformFullScreen = true
                NSLog("📐 [全屏] 系統旋轉被鎖定，使用 transform 旋轉，isUsingTransformFullScreen 設為 true")

                // 使用 transform 旋轉 90 度，並交換寬高
                let landscapeWidth = windowBoundsAfterRotation.height
                let landscapeHeight = windowBoundsAfterRotation.width

                UIView.animate(withDuration: 0.3) {
                    self.bounds = CGRect(x: 0, y: 0, width: landscapeWidth, height: landscapeHeight)
                    self.center = CGPoint(x: windowBoundsAfterRotation.midX, y: windowBoundsAfterRotation.midY)
                    self.transform = CGAffineTransform(rotationAngle: .pi / 2)  // 順時針 90 度

                    if let playerView = self.player?.view {
                        playerView.frame = self.bounds
                    }
                    self.controlView.frame = self.bounds
                } completion: { _ in
                    self.finishFullScreenTransition(window: finalWindow)
                }
            }
        }
    }

    /// 強制系統旋轉到橫屏
    private func forceRotateToLandscape() {
        if #available(iOS 16.0, *) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
                NSLog("📱 requestGeometryUpdate error: %@", error.localizedDescription)
            }
            if let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
        NSLog("📱 已請求系統旋轉到橫屏")
    }

    /// 完成全屏過渡（舊版 rotateToLandscape 的動畫完成部分，現在共用）
    /// #1800 修復：舊版使用 transform 旋轉，但鍵盤不會跟隨
    /// 保留此方法作為備用，但新版使用系統方向旋轉
    private func rotateToLandscapeLegacy() {
        // 設置進入全屏標記，防止 layoutSubviews 誤判
        isEnteringFullScreen = true

        // #3106 修復：舊版使用 transform，設置標記
        isUsingTransformFullScreen = true

        currentRotationAngle = .pi / 2  // 90 度

        print("🔄 [Legacy] 開始旋轉到橫屏（90°）並全屏（使用 transform）")

        // 記錄當前界面方向
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                lastDetectedInterfaceOrientation = windowScene.interfaceOrientation
            }
        } else {
            lastDetectedInterfaceOrientation = UIApplication.shared.statusBarOrientation
        }

        var window: UIWindow?
        if #available(iOS 13.0, *) {
            window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }
        if window == nil {
            window = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
        }
        if window == nil {
            window = UIApplication.shared.keyWindow
        }

        guard let window = window else {
            print("❌ 無法獲取 window")
            return
        }

        if originalSuperview == nil {
            originalFrame = frame
            originalSuperview = superview

            if let superview = superview {
                originalConstraints = superview.constraints.filter { constraint in
                    (constraint.firstItem as? UIView) == self || (constraint.secondItem as? UIView) == self
                }
                NSLayoutConstraint.deactivate(originalConstraints)
            }

            containerConstraints = constraints.filter { constraint in
                (constraint.firstItem as? UIView) == controlView || (constraint.secondItem as? UIView) == controlView
            }
            NSLayoutConstraint.deactivate(containerConstraints)
        }

        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = []

        controlView.translatesAutoresizingMaskIntoConstraints = true
        controlView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if let playerView = player?.view {
            playerView.translatesAutoresizingMaskIntoConstraints = true
            playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }

        removeFromSuperview()
        window.addSubview(self)

        controlView.isHidden = false
        controlView.alpha = 1.0
        controlView.isUserInteractionEnabled = true

        UIView.animate(withDuration: 0.3) {
            self.bounds = CGRect(x: 0, y: 0, width: window.bounds.height, height: window.bounds.width)
            self.center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
            self.transform = CGAffineTransform(rotationAngle: self.currentRotationAngle)

            // 立即更新所有子視圖的 frame（基於新的 bounds）
            if let playerView = self.player?.view {
                playerView.frame = self.bounds
                print("📐 [動畫中] 設置 playerView.frame = \(self.bounds)")
            }
            self.controlView.frame = self.bounds
            print("📐 [動畫中] 設置 controlView.frame = \(self.bounds)")
        } completion: { _ in
            // 再次確保所有視圖正確
            if let playerView = self.player?.view {
                playerView.frame = self.bounds
                print("📐 playerView 更新為: \(playerView.frame)")
            }

            self.controlView.frame = self.bounds

            // 強制 controlView 進行佈局，確保其內部子視圖（按鈕、進度條等）正確顯示
            self.controlView.setNeedsLayout()
            self.controlView.layoutIfNeeded()

            self.bringSubviewToFront(self.controlView)

            // 確保所有手勢反饋 UI 也在正確位置
            self.bringSubviewToFront(self.loadingView)
            self.bringSubviewToFront(self.seekPreviewContainer)
            self.bringSubviewToFront(self.volumeBrightnessContainer)
            self.bringSubviewToFront(self.forwardSeekIcon)
            self.bringSubviewToFront(self.backwardSeekIcon)

            print("✅ 旋轉到橫屏並全屏完成")
            print("📐 [完成後] container frame: \(self.frame)")
            print("📐 [完成後] container bounds: \(self.bounds)")
            print("📐 [完成後] container center: \(self.center)")
            print("📐 [完成後] container transform: \(self.transform)")
            print("📐 [完成後] window bounds: \(window.bounds)")
            print("📐 [完成後] controlView frame: \(self.controlView.frame)")
            print("📐 [完成後] controlView bounds: \(self.controlView.bounds)")
            print("📐 [完成後] controlView superview: \(String(describing: self.controlView.superview))")
            print("📐 [完成後] controlView isHidden: \(self.controlView.isHidden), alpha: \(self.controlView.alpha)")
            print("📐 [完成後] controlView backgroundColor: \(String(describing: self.controlView.backgroundColor))")

            print("📐 [完成後] 所有子視圖數量: \(self.subviews.count)")
            print("📐 [完成後] 子視圖順序:")
            for (index, subview) in self.subviews.enumerated() {
                print("   [\(index)] \(type(of: subview)), frame: \(subview.frame), alpha: \(subview.alpha), hidden: \(subview.isHidden)")
            }

            print("📐 [完成後] controlView 內部子視圖數量: \(self.controlView.subviews.count)")
            print("📐 [完成後] controlView 內部子視圖:")
            for (index, subview) in self.controlView.subviews.enumerated() {
                print("   [\(index)] \(type(of: subview)), frame: \(subview.frame), alpha: \(subview.alpha), hidden: \(subview.isHidden)")
            }

            // 再次強制設置
            self.controlView.isHidden = false
            self.controlView.alpha = 1.0

            self.controlView.updateFullScreenState(isFullScreen: true)
            self.controlView.show(animated: false, autoHide: false)  // 不要動畫，不要自動隱藏

            print("📐 controlView.show() 調用後: isHidden: \(self.controlView.isHidden), alpha: \(self.controlView.alpha)")

            // 強制觸發 layoutSubviews 確保所有視圖正確佈局
            self.setNeedsLayout()
            self.layoutIfNeeded()

            // 清除進入全屏標記
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isEnteringFullScreen = false
                print("📱 [Legacy] 進入全屏完成，開始監聽方向變化")
            }
        }
    }

    /// 完成全屏過渡的共用邏輯
    /// #1805 修復：確保 controlView 使用 Auto Layout 以正確響應 safe area
    private func finishFullScreenTransition(window: UIWindow) {
        if let playerView = player?.view {
            playerView.frame = bounds
        }

        // #1805 修復：恢復 controlView 的 Auto Layout，讓 safe area 正確應用
        // 這樣底部控件欄才會在橫屏時正確顯示在底部（避開 safe area）
        controlView.translatesAutoresizingMaskIntoConstraints = false

        // 移除舊的約束
        controlView.removeFromSuperview()
        addSubview(controlView)

        // 使用 Auto Layout 約束，讓 controlView 填滿整個容器
        NSLayoutConstraint.activate([
            controlView.topAnchor.constraint(equalTo: topAnchor),
            controlView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        controlView.setNeedsLayout()
        controlView.layoutIfNeeded()

        bringSubviewToFront(controlView)
        bringSubviewToFront(loadingView)
        bringSubviewToFront(seekPreviewContainer)
        bringSubviewToFront(volumeBrightnessContainer)
        bringSubviewToFront(forwardSeekIcon)
        bringSubviewToFront(backwardSeekIcon)

        print("✅ 全屏過渡完成")
        print("📐 [完成後] container bounds: \(bounds)")
        print("📐 [完成後] window bounds: \(window.bounds)")
        print("📐 [完成後] safeAreaInsets: \(safeAreaInsets)")

        controlView.isHidden = false
        controlView.alpha = 1.0

        controlView.updateFullScreenState(isFullScreen: true)
        controlView.show(animated: false, autoHide: false)

        setNeedsLayout()
        layoutIfNeeded()

        // 清除進入全屏標記，允許 layoutSubviews 檢測方向變化
        // 延遲一點執行，確保佈局完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isEnteringFullScreen = false
            print("📱 進入全屏完成，開始監聽方向變化")
        }
    }

    /// #1796 修復：根據當前設備方向進入橫屏全屏（不強制旋轉視圖）
    /// - Parameter orientation: 當前設備方向
    private func rotateToLandscapeWithOrientation(_ orientation: UIDeviceOrientation) {
        // 設置進入全屏標記，防止 layoutSubviews 誤判
        isEnteringFullScreen = true

        // 根據設備方向決定旋轉角度
        // landscapeLeft = Home 鍵在右邊，需要順時針旋轉 90 度（但設備已經是橫屏，所以不需要旋轉）
        // landscapeRight = Home 鍵在左邊，需要逆時針旋轉 90 度（但設備已經是橫屏，所以不需要旋轉）
        currentRotationAngle = 0  // 不需要額外旋轉，因為設備已經是橫屏

        print("🔄 設備已是橫屏，直接進入全屏模式（不旋轉視圖）")

        // 設置全屏狀態
        UserDefaults.standard.set(true, forKey: "DXPlayerSDK.isPlayerFullScreen")

        // 記錄進入全屏時的界面方向
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                lastDetectedInterfaceOrientation = windowScene.interfaceOrientation
            }
        } else {
            lastDetectedInterfaceOrientation = UIApplication.shared.statusBarOrientation
        }

        // 獲取 window
        var window: UIWindow?
        if #available(iOS 13.0, *) {
            window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        }
        if window == nil {
            window = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
        }
        if window == nil {
            window = UIApplication.shared.keyWindow
        }

        guard let window = window else {
            print("❌ 無法獲取 window")
            return
        }

        print("📐 [DEBUG] window bounds: \(window.bounds)")

        // 保存原始狀態
        if originalSuperview == nil {
            originalFrame = frame
            originalSuperview = superview
            print("💾 保存原始狀態：frame = \(originalFrame)")

            if let superview = superview {
                originalConstraints = superview.constraints.filter { constraint in
                    (constraint.firstItem as? UIView) == self || (constraint.secondItem as? UIView) == self
                }
                NSLayoutConstraint.deactivate(originalConstraints)
            }

            containerConstraints = constraints.filter { constraint in
                (constraint.firstItem as? UIView) == controlView || (constraint.secondItem as? UIView) == controlView
            }
            NSLayoutConstraint.deactivate(containerConstraints)
        }

        // 禁用 Auto Layout，使用手動布局
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = []

        controlView.translatesAutoresizingMaskIntoConstraints = true
        controlView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if let playerView = player?.view {
            playerView.translatesAutoresizingMaskIntoConstraints = true
            playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }

        // 移除並添加到 window
        removeFromSuperview()
        window.addSubview(self)

        // 強制顯示 controlView
        controlView.isHidden = false
        controlView.alpha = 1.0
        controlView.isUserInteractionEnabled = true

        // #3106 修復：設備已經是橫屏，不需要使用 transform
        isUsingTransformFullScreen = false

        // 動畫：直接全屏（不旋轉，因為設備已經是橫屏）
        UIView.animate(withDuration: 0.3) {
            // 設備已經是橫屏，直接使用 window 的 bounds
            self.bounds = window.bounds
            self.center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
            self.transform = .identity  // 不需要旋轉

            if let playerView = self.player?.view {
                playerView.frame = self.bounds
            }
            self.controlView.frame = self.bounds
        } completion: { _ in
            // #1805 修復：使用共用方法確保 controlView 正確響應 safe area
            self.finishFullScreenTransition(window: window)
        }
    }

    /// 退出全屏並旋轉回豎屏
    /// 使用系統方向 API 旋轉回豎屏，或清除 transform（如果使用了 transform 全屏）
    private func rotateToPortrait() {
        currentRotationAngle = 0

        // #3106 修復：根據進入全屏的方式決定退出方式
        let wasUsingTransform = isUsingTransformFullScreen
        NSLog("🔄 開始退出全屏並旋轉回豎屏 (wasUsingTransform: %d)", wasUsingTransform ? 1 : 0)

        // 清除全屏狀態
        UserDefaults.standard.set(false, forKey: "DXPlayerSDK.isPlayerFullScreen")

        // #3106 修復：保存原始狀態用於恢復
        let targetFrame = self.originalFrame
        let savedOriginalSuperview = self.originalSuperview
        let savedOriginalConstraints = self.originalConstraints
        let savedContainerConstraints = self.containerConstraints

        // 獲取當前 window bounds（用於判斷系統是否成功旋轉）
        var currentWindowBounds: CGRect = .zero
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                currentWindowBounds = window.bounds
            }
        }
        NSLog("📐 [退出全屏] 當前 window bounds: %@", NSCoder.string(for: currentWindowBounds))

        // 請求系統旋轉回豎屏
        forceRotateToPortrait()

        // 延遲執行，等待系統旋轉
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }

            // 獲取原始父視圖
            guard let originalSuperview = savedOriginalSuperview else {
                NSLog("❌ [退出全屏] 無法獲取原始父視圖")
                return
            }

            // #3106 修復：檢查系統是否成功旋轉回豎屏
            var newWindowBounds: CGRect = .zero
            if #available(iOS 13.0, *) {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                    newWindowBounds = window.bounds
                }
            }

            let windowIsPortrait = newWindowBounds.width < newWindowBounds.height
            let windowRotatedBack = abs(newWindowBounds.width - currentWindowBounds.height) < 1 &&
                                   abs(newWindowBounds.height - currentWindowBounds.width) < 1

            NSLog("📐 [退出全屏] 新 window bounds: %@, windowIsPortrait: %d, windowRotatedBack: %d",
                  NSCoder.string(for: newWindowBounds), windowIsPortrait ? 1 : 0, windowRotatedBack ? 1 : 0)

            // 清除 transform
            self.transform = .identity

            // 從 window 移除並添加回原始父視圖
            self.removeFromSuperview()
            originalSuperview.addSubview(self)

            // 恢復容器的 Auto Layout
            self.translatesAutoresizingMaskIntoConstraints = false
            self.autoresizingMask = []

            // 控制層也恢復 Auto Layout
            self.controlView.translatesAutoresizingMaskIntoConstraints = false

            // 恢復原始 frame
            self.frame = targetFrame

            // 重新激活約束
            NSLayoutConstraint.activate(savedOriginalConstraints)
            NSLayoutConstraint.activate(savedContainerConstraints)

            // 確保播放器視圖也正確恢復
            if let playerView = self.player?.view {
                playerView.frame = self.bounds
                NSLog("📐 [退出全屏] playerView 恢復為: %@", NSCoder.string(for: playerView.frame))
            }
            self.controlView.frame = self.bounds

            // 清空保存的狀態
            self.originalSuperview = nil
            self.originalConstraints = []
            self.containerConstraints = []

            // #3106 修復：清除 transform 全屏標記
            self.isUsingTransformFullScreen = false

            NSLog("✅ 退出全屏並旋轉回豎屏完成, frame: %@", NSCoder.string(for: self.frame))
            self.controlView.updateFullScreenState(isFullScreen: false)

            // 強制觸發 layoutSubviews
            self.setNeedsLayout()
            self.layoutIfNeeded()

            // #3106 修復：如果系統沒有成功旋轉回豎屏，持續嘗試
            if !windowIsPortrait {
                NSLog("⚠️ [退出全屏] 系統未成功旋轉回豎屏，持續嘗試")
                self.forceRotateToPortraitRepeatedly()
            }
        }
    }

    /// #3106 修復：重複嘗試旋轉回豎屏，直到成功
    private func forceRotateToPortraitRepeatedly(attempts: Int = 0) {
        // 最多嘗試 10 次，每次間隔 0.2 秒
        guard attempts < 10 else {
            NSLog("⚠️ [旋轉] 嘗試 10 次後仍未成功旋轉回豎屏")
            return
        }

        // 檢查當前 window 是否已經是豎屏
        var isPortrait = false
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                isPortrait = window.bounds.width < window.bounds.height
            }
        }

        if isPortrait {
            NSLog("✅ [旋轉] 已成功旋轉回豎屏（第 %d 次嘗試）", attempts + 1)
            return
        }

        // 再次請求旋轉
        forceRotateToPortrait()

        // 延遲後再次檢查
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.forceRotateToPortraitRepeatedly(attempts: attempts + 1)
        }
    }

    /// 強制系統旋轉回豎屏
    private func forceRotateToPortrait() {
        if #available(iOS 16.0, *) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                NSLog("📱 requestGeometryUpdate (portrait) error: %@", error.localizedDescription)
            }
            if let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
        NSLog("📱 已請求系統旋轉回豎屏")
    }

    /// 獲取旋轉目標視圖（優先使用 navigationController.view，否則使用 window）
    private func getRotationTargetView() -> UIView? {
        // 嘗試獲取 viewController 的 navigationController
        if let viewController = self.findViewController(),
           let navView = viewController.navigationController?.view {
            print("📐 使用 navigationController.view 作為旋轉目標")
            return navView
        }

        // 備選：使用 window
        if let window = self.window {
            print("📐 使用 window 作為旋轉目標")
            return window
        }

        return nil
    }

    /// 查找當前 view 所屬的 ViewController
    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let viewController = nextResponder as? UIViewController {
                return viewController
            }
            responder = nextResponder
        }
        return nil
    }

    func controlViewDidSeek(to time: TimeInterval) {
        // 廣告播放期間忽略 seek 操作
        if adManager?.isShowingPrerollAd() == true {
            return
        }

        let duration = player?.duration ?? 0
        let isSeekingToEnd = time >= duration - 0.5

        // ✅ 如果从 replay 状态 seek，只有在 seek 到非末尾位置时才清除 replay 状态
        if isShowingReplay && !isSeekingToEnd {
            print("🎬 从 replay 状态 seek 到中间位置，清除 replay 状态")
            isShowingReplay = false
            // 立即隐藏 replay icon，显示正常的播放/暂停 icon
            let isPlaying = player?.isPlaying() ?? false
            controlView.updatePlaybackState(isPlaying: isPlaying, showReplay: false)
        } else if isSeekingToEnd {
            print("🎬 seek 到末尾，保持或设置 replay 状态")
            // 如果 seek 到末尾，确保是 replay 状态（避免中间状态闪爍）
            if !isShowingReplay {
                isShowingReplay = true
                controlView.updatePlaybackState(isPlaying: false, showReplay: true)
            }
        }

        player?.currentPlaybackTime = time
        updateProgress()

        // 彈幕：seek 後清空舊彈幕並從新位置重新同步
        danmakuManager?.seek(to: time)
    }

    func controlViewDidRequestCurrentTime() -> TimeInterval {
        return player?.currentPlaybackTime ?? 0
    }

    func controlViewDidRequestDuration() -> TimeInterval {
        return player?.duration ?? 0
    }

    // MARK: - 播放状态查詢和控制

    func controlViewDidRequestPlaybackState() -> Bool {
        return player?.isPlaying() ?? false
    }

    func controlViewDidBeginDrag() {
        isUserSeeking = true
    }

    func controlViewDidEndDrag() {
        isUserSeeking = false
    }

    func controlViewDidPause() {
        // 廣告播放期間忽略暫停操作
        if adManager?.isShowingPrerollAd() == true {
            return
        }
        pause()
    }

    func controlViewDidResume() {
        // 廣告播放期間忽略播放操作
        if adManager?.isShowingPrerollAd() == true {
            return
        }
        play()
    }

    func controlViewDidSeekToEnd() {
        // 廣告播放期間忽略 seek 操作
        if adManager?.isShowingPrerollAd() == true {
            return
        }
        print("🎬 controlViewDidSeekToEnd - 触发播放结束邏輯")
        // 停止计时器
        stopProgressTimer()
        // ✅ 确保是重播状态（controlViewDidSeek 可能已經设置了，这裡再确认一次）
        if !isShowingReplay {
            isShowingReplay = true
            controlView.updatePlaybackState(isPlaying: false, showReplay: true)
        }
        // 显示控制层（不自動隐藏）
        controlView.show(animated: true, autoHide: false)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension IJKPlayerContainerView: UIGestureRecognizerDelegate {

    /// 判断手势是否应该开始
    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 如果正在播放廣告，禁用所有手勢
        if adManager?.isShowingPrerollAd() == true {
            return false
        }

        // 如果正在 loading，禁用所有手势
        if !loadingView.isHidden {
            print("🚫 手勢被拒絕：正在 loading")
            return false
        }

        // 如果是滑动手势，判断滑动方向
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: self)

            print("🎯 shouldBegin - velocity: (\(velocity.x), \(velocity.y))")

            // ✅ 修復：在手勢开始时，translation 总是 (0,0) 或很小，不能用来判斷
            // 只要有明显的速度，就允許手勢开始
            // 防抖閾值：速度至少要 > 50 点/秒
            let minVelocity: CGFloat = 50.0
            let hasSignificantVelocity = abs(velocity.x) > minVelocity || abs(velocity.y) > minVelocity

            if !hasSignificantVelocity {
                print("🚫 手勢被拒絕：速度太小")
                return false
            }

            // 判断是水平还是竖直滑动
            // 允许明确的水平或竖直滑动
            let isHorizontal = abs(velocity.x) > abs(velocity.y)
            let isVertical = abs(velocity.y) > abs(velocity.x)
            let shouldBegin = isHorizontal || isVertical

            print("✅ 手勢\(shouldBegin ? "允許" : "被拒絕")：水平=\(isHorizontal), 竖直=\(isVertical)")
            return shouldBegin
        }

        return true
    }

    /// 允許手勢和其他触摸同时識別
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    /// 只在点击空白區域时識別手勢，不攔截按鈕和进度条
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // 如果触摸的是 UIControl（按鈕、滑桿等），不处理手勢
        if touch.view is UIControl {
            return false
        }

        // 如果触摸的是按鈕的父视圖（UIButton 內部的子视圖），也不处理
        var view = touch.view
        while view != nil {
            if view is UIControl {
                return false
            }
            view = view?.superview
        }

        return true
    }
}
