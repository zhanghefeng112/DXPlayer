import UIKit
import FSPlayer

/// 播放器控制视图委托协议
protocol PlayerControlViewDelegate: AnyObject {
    func controlViewDidTapPlayPause()
    func controlViewDidTapFullScreen()
    func controlViewDidSeek(to time: TimeInterval)
    func controlViewDidRequestCurrentTime() -> TimeInterval
    func controlViewDidRequestDuration() -> TimeInterval

    // 播放状态查詢和控制
    func controlViewDidRequestPlaybackState() -> Bool  // 查詢当前是否正在播放
    func controlViewDidPause()  // 暂停播放
    func controlViewDidResume()  // 恢復播放
    func controlViewDidSeekToEnd()  // Seek 到视频末尾，触发结束邏輯
    func controlViewDidBeginDrag()  // 开始拖动进度条
    func controlViewDidEndDrag()    // 结束拖动进度条
}

/// 播放器控制视图
/// 包含播放/暂停按钮、进度条、时间显示、全屏按钮等
class PlayerControlView: UIView {

    // MARK: - 代理
    weak var delegate: PlayerControlViewDelegate?

    // MARK: - UI 组件
    // 顶部容器
    private let topContainerView = UIView()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.text = "视频播放"
        return label
    }()

    // 中间大播放按钮
    let centerPlayButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 25
        button.layer.masksToBounds = true

        // 使用图片资源
        let playImage = UIImage.dxPlayerImage(named: "play_icon", renderingMode: .alwaysTemplate)
        button.setImage(playImage, for: .normal)
        button.tintColor = .white
        button.imageView?.contentMode = .scaleAspectFit
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        return button
    }()

    // 底部容器（包含上下两列）
    private let bottomContainerView = UIView()

    // 上列：进度条
    private let progressRowView = UIView()
    private let progressSlider = PlayerProgressSlider()

    // 下列：控制按钮和弹幕
    private let controlRowView = UIView()

    private let playPauseButton: UIButton = {
        let button = UIButton(type: .custom)
        let playImage = UIImage.dxPlayerImage(named: "play_icon", renderingMode: .alwaysTemplate)
        button.setImage(playImage, for: .normal)
        button.tintColor = .white
        button.imageView?.contentMode = .scaleAspectFit
        return button
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 12)
        label.text = "00:00 / 00:00"
        return label
    }()

    // 弹幕按钮容器
    private let danmakuButtonContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.3, alpha: 0.8)
        view.layer.cornerRadius = 14
        view.clipsToBounds = true
        return view
    }()

    private let danmakuToggleButton: UIButton = {
        let button = UIButton(type: .custom)
        // 使用新的彈幕開關 icon（不需要 tint，直接使用原圖）
        let onImage = UIImage.dxPlayerImage(named: "danmaku_on")
        let offImage = UIImage.dxPlayerImage(named: "danmaku_off")
        button.setImage(onImage, for: .normal)
        button.setImage(offImage, for: .selected)
        button.backgroundColor = .clear
        return button
    }()

    private let danmakuSeparatorView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        return view
    }()

    private let danmakuSettingsButton: UIButton = {
        let button = UIButton(type: .custom)
        let image = UIImage.dxPlayerImage(named: "danmaku_settings")?.withRenderingMode(.alwaysTemplate)
        button.setImage(image, for: .normal)
        button.tintColor = .white
        button.backgroundColor = .clear
        return button
    }()

    // 弹幕输入框
    private let danmakuTextField: UITextField = {
        let textField = UITextField()
        textField.textColor = .white
        textField.font = UIFont.systemFont(ofSize: 13)
        textField.backgroundColor = UIColor(white: 0.3, alpha: 0.8)
        textField.layer.cornerRadius = 14
        textField.returnKeyType = .send
        textField.attributedPlaceholder = NSAttributedString(
            string: "快来参与弹幕讨论吧~",
            attributes: [
                .foregroundColor: UIColor.white.withAlphaComponent(0.6),
                .font: UIFont.systemFont(ofSize: 13)
            ]
        )
        let leftPadding = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 28))
        textField.leftView = leftPadding
        textField.leftViewMode = .always
        let rightPadding = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 28))
        textField.rightView = rightPadding
        textField.rightViewMode = .always
        return textField
    }()


    /// 弹幕发送按钮
    private let danmakuSendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("发送", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        button.backgroundColor = UIColor(red: 0xFF/255.0, green: 0x6B/255.0, blue: 0x00/255.0, alpha: 1.0)
        button.layer.cornerRadius = 14
        return button
    }()

    // 全屏按钮
    private let fullScreenButton: UIButton = {
        let button = UIButton(type: .custom)
        let fullscreenImage = UIImage.dxPlayerImage(named: "fullscreen_icon", renderingMode: .alwaysTemplate)
        button.setImage(fullscreenImage, for: .normal)
        button.tintColor = .white
        button.imageView?.contentMode = .scaleAspectFit
        return button
    }()

    // 兼容旧代码的属性
    private var currentTimeLabel: UILabel { timeLabel }
    private var totalTimeLabel: UILabel { timeLabel }

    // 加载指示器
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .whiteLarge)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // 滑动快进/快退预览 UI
    private let seekPreviewContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        view.layer.cornerRadius = 5
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.alpha = 0
        view.isUserInteractionEnabled = false  // 禁用交互，避免阻擋触摸事件
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
        view.isUserInteractionEnabled = false  // 禁用交互，避免阻擋触摸事件
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
        imageView.isUserInteractionEnabled = false  // 禁用交互，避免阻擋触摸事件
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
        imageView.isUserInteractionEnabled = false  // 禁用交互，避免阻擋触摸事件
        return imageView
    }()

    // MARK: - 弹幕回调

    /// 弹幕开关回调
    var onDanmakuToggle: ((Bool) -> Void)?

    /// 弹幕设定回调
    var onDanmakuSettings: (() -> Void)?

    /// 发送弹幕回调
    var onSendDanmaku: ((String) -> Void)?

    // MARK: - 私有属性

    private var autoHideTimer: Timer?
    private let autoHideDelay: TimeInterval = 5.0
    private var isVisible = true

    private var viewModel = PlayerControlViewModel()

    // 进度条拖动标志
    private var isSliderDragging = false
    // Seek 操作标志 - 防止 seek 期间被自動更新覆蓋
    private var isSeeking = false

    // 弹幕开关状态
    private var isDanmakuEnabled = true

    // 全屏状态
    private var isInFullScreen = false

    // 保存底部容器的底部约束，用于全屏时调整
    private var bottomContainerBottomConstraint: NSLayoutConstraint?

    // 缩略图预览管理器（弱引用，由外部管理）
    weak var thumbnailPreviewManager: ThumbnailPreviewManager? {
        didSet {
            DXPlayerLogger.info("🖼️ [控制视图] thumbnailPreviewManager didSet 被触发")
            DXPlayerLogger.info("🖼️ [控制视图] 新值: \(thumbnailPreviewManager != nil ? "✅" : "❌")")

            // 将管理器传递给进度条
            progressSlider.thumbnailManager = thumbnailPreviewManager

            DXPlayerLogger.info("🖼️ [控制视图] 已传递给 progressSlider")
            DXPlayerLogger.info("🖼️ [控制视图] progressSlider.thumbnailManager: \(progressSlider.thumbnailManager != nil ? "✅" : "❌")")
        }
    }

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupConstraints()
        setupGestures()
        setupActions()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupConstraints()
        setupGestures()
        setupActions()
    }

    // MARK: - 设置

    private func setupUI() {
        backgroundColor = .clear

        // 确保控制层可见
        alpha = 1.0

        // 添加渐变背景（提升可读性）
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0.7).cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.7).cgColor
        ]
        gradientLayer.locations = [0, 0.2, 0.8, 1.0]
        gradientLayer.frame = bounds
        layer.insertSublayer(gradientLayer, at: 0)

        // 顶部容器
        topContainerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topContainerView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        topContainerView.addSubview(titleLabel)

        // 中间播放按钮
        centerPlayButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerPlayButton)

        // 底部容器
        bottomContainerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomContainerView)

        // 上列：进度条
        progressRowView.translatesAutoresizingMaskIntoConstraints = false
        bottomContainerView.addSubview(progressRowView)

        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressRowView.addSubview(progressSlider)

        // 下列：控制按钮
        controlRowView.translatesAutoresizingMaskIntoConstraints = false
        bottomContainerView.addSubview(controlRowView)

        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        controlRowView.addSubview(playPauseButton)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        controlRowView.addSubview(timeLabel)

        // 弹幕按钮容器
        danmakuButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        controlRowView.addSubview(danmakuButtonContainer)

        danmakuToggleButton.translatesAutoresizingMaskIntoConstraints = false
        danmakuButtonContainer.addSubview(danmakuToggleButton)

        danmakuSeparatorView.translatesAutoresizingMaskIntoConstraints = false
        danmakuButtonContainer.addSubview(danmakuSeparatorView)

        danmakuSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        danmakuButtonContainer.addSubview(danmakuSettingsButton)

        // 弹幕输入框
        danmakuTextField.translatesAutoresizingMaskIntoConstraints = false
        controlRowView.addSubview(danmakuTextField)

        // 弹幕发送按钮
        danmakuSendButton.translatesAutoresizingMaskIntoConstraints = false
        controlRowView.addSubview(danmakuSendButton)

        fullScreenButton.translatesAutoresizingMaskIntoConstraints = false
        controlRowView.addSubview(fullScreenButton)

        // 加载指示器
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)

        // 滑动快进/快退预览容器
        addSubview(seekPreviewContainer)
        seekPreviewContainer.addSubview(seekTimeLabel)
        seekPreviewContainer.addSubview(seekProgressBar)

        // 亮度/音量指示器容器
        addSubview(volumeBrightnessContainer)
        volumeBrightnessContainer.addSubview(volumeBrightnessIcon)
        volumeBrightnessContainer.addSubview(volumeBrightnessProgressBar)

        // 双击快进/快退动画图标
        addSubview(forwardSeekIcon)
        addSubview(backwardSeekIcon)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // 顶部容器
            topContainerView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            topContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            topContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topContainerView.heightAnchor.constraint(equalToConstant: 44),

            // 标题
            titleLabel.centerYAnchor.constraint(equalTo: topContainerView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: topContainerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: topContainerView.trailingAnchor, constant: -16),

            // 中间播放按钮
            centerPlayButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerPlayButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            centerPlayButton.widthAnchor.constraint(equalToConstant: 50),
            centerPlayButton.heightAnchor.constraint(equalToConstant: 50),

            // 底部容器（两列）
            bottomContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomContainerView.heightAnchor.constraint(equalToConstant: 70),

            // 上列：进度条
            progressRowView.topAnchor.constraint(equalTo: bottomContainerView.topAnchor),
            progressRowView.leadingAnchor.constraint(equalTo: bottomContainerView.leadingAnchor),
            progressRowView.trailingAnchor.constraint(equalTo: bottomContainerView.trailingAnchor),
            progressRowView.heightAnchor.constraint(equalToConstant: 30),

            progressSlider.leadingAnchor.constraint(equalTo: progressRowView.leadingAnchor, constant: 12),
            progressSlider.trailingAnchor.constraint(equalTo: progressRowView.trailingAnchor, constant: -12),
            progressSlider.centerYAnchor.constraint(equalTo: progressRowView.centerYAnchor),
            progressSlider.heightAnchor.constraint(equalToConstant: 30),

            // 下列：控制按钮
            controlRowView.topAnchor.constraint(equalTo: progressRowView.bottomAnchor),
            controlRowView.leadingAnchor.constraint(equalTo: bottomContainerView.leadingAnchor),
            controlRowView.trailingAnchor.constraint(equalTo: bottomContainerView.trailingAnchor),
            controlRowView.bottomAnchor.constraint(equalTo: bottomContainerView.bottomAnchor),

            // 播放/暂停按钮
            playPauseButton.leadingAnchor.constraint(equalTo: controlRowView.leadingAnchor, constant: 8),
            playPauseButton.centerYAnchor.constraint(equalTo: controlRowView.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 28),
            playPauseButton.heightAnchor.constraint(equalToConstant: 28),

            // 时间标签
            timeLabel.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 4),
            timeLabel.centerYAnchor.constraint(equalTo: controlRowView.centerYAnchor),

            // 弹幕按钮容器
            danmakuButtonContainer.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 12),
            danmakuButtonContainer.centerYAnchor.constraint(equalTo: controlRowView.centerYAnchor),
            danmakuButtonContainer.heightAnchor.constraint(equalToConstant: 28),

            // 弹幕开关按钮 - 增加左边距和宽度，避免与设定按钮重叠
            danmakuToggleButton.leadingAnchor.constraint(equalTo: danmakuButtonContainer.leadingAnchor, constant: 6),
            danmakuToggleButton.centerYAnchor.constraint(equalTo: danmakuButtonContainer.centerYAnchor),
            danmakuToggleButton.widthAnchor.constraint(equalToConstant: 28),
            danmakuToggleButton.heightAnchor.constraint(equalToConstant: 28),

            // 分隔线 - 增加左边距
            danmakuSeparatorView.leadingAnchor.constraint(equalTo: danmakuToggleButton.trailingAnchor, constant: 4),
            danmakuSeparatorView.centerYAnchor.constraint(equalTo: danmakuButtonContainer.centerYAnchor),
            danmakuSeparatorView.widthAnchor.constraint(equalToConstant: 1),
            danmakuSeparatorView.heightAnchor.constraint(equalToConstant: 14),

            // 弹幕设定按钮 - 增加左边距和右边距
            danmakuSettingsButton.leadingAnchor.constraint(equalTo: danmakuSeparatorView.trailingAnchor, constant: 4),
            danmakuSettingsButton.centerYAnchor.constraint(equalTo: danmakuButtonContainer.centerYAnchor),
            danmakuSettingsButton.trailingAnchor.constraint(equalTo: danmakuButtonContainer.trailingAnchor, constant: -6),
            danmakuSettingsButton.widthAnchor.constraint(equalToConstant: 28),
            danmakuSettingsButton.heightAnchor.constraint(equalToConstant: 28),

            // 弹幕输入框
            danmakuTextField.leadingAnchor.constraint(equalTo: danmakuButtonContainer.trailingAnchor, constant: 8),
            danmakuTextField.trailingAnchor.constraint(equalTo: danmakuSendButton.leadingAnchor, constant: -6),
            danmakuTextField.centerYAnchor.constraint(equalTo: controlRowView.centerYAnchor),
            danmakuTextField.heightAnchor.constraint(equalToConstant: 28),

            // 弹幕发送按钮
            danmakuSendButton.trailingAnchor.constraint(equalTo: fullScreenButton.leadingAnchor, constant: -8),
            danmakuSendButton.centerYAnchor.constraint(equalTo: controlRowView.centerYAnchor),
            danmakuSendButton.widthAnchor.constraint(equalToConstant: 48),
            danmakuSendButton.heightAnchor.constraint(equalToConstant: 28),

            // 全屏按钮
            fullScreenButton.trailingAnchor.constraint(equalTo: controlRowView.trailingAnchor, constant: -12),
            fullScreenButton.centerYAnchor.constraint(equalTo: controlRowView.centerYAnchor),
            fullScreenButton.widthAnchor.constraint(equalToConstant: 28),
            fullScreenButton.heightAnchor.constraint(equalToConstant: 28),

            // 加载指示器
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 滑动快进/快退预览容器（屏幕中央偏上）
            seekPreviewContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            seekPreviewContainer.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -30),
            seekPreviewContainer.widthAnchor.constraint(equalToConstant: 200),
            seekPreviewContainer.heightAnchor.constraint(equalToConstant: 60),

            // 时间标签
            seekTimeLabel.topAnchor.constraint(equalTo: seekPreviewContainer.topAnchor, constant: 8),
            seekTimeLabel.leadingAnchor.constraint(equalTo: seekPreviewContainer.leadingAnchor, constant: 10),
            seekPreviewContainer.trailingAnchor.constraint(equalTo: seekTimeLabel.trailingAnchor, constant: 10),

            // 进度条
            seekProgressBar.topAnchor.constraint(equalTo: seekTimeLabel.bottomAnchor, constant: 8),
            seekProgressBar.leadingAnchor.constraint(equalTo: seekPreviewContainer.leadingAnchor, constant: 10),
            seekPreviewContainer.trailingAnchor.constraint(equalTo: seekProgressBar.trailingAnchor, constant: 10),
            seekPreviewContainer.bottomAnchor.constraint(equalTo: seekProgressBar.bottomAnchor, constant: 8),

            // 亮度/音量指示器容器（屏幕中央偏上）
            volumeBrightnessContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            volumeBrightnessContainer.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -30),
            volumeBrightnessContainer.widthAnchor.constraint(equalToConstant: 200),
            volumeBrightnessContainer.heightAnchor.constraint(equalToConstant: 40),

            // 图标
            volumeBrightnessIcon.leadingAnchor.constraint(equalTo: volumeBrightnessContainer.leadingAnchor, constant: 10),
            volumeBrightnessIcon.centerYAnchor.constraint(equalTo: volumeBrightnessContainer.centerYAnchor),
            volumeBrightnessIcon.widthAnchor.constraint(equalToConstant: 20),
            volumeBrightnessIcon.heightAnchor.constraint(equalToConstant: 20),

            // 进度条
            volumeBrightnessProgressBar.leadingAnchor.constraint(equalTo: volumeBrightnessIcon.trailingAnchor, constant: 8),
            volumeBrightnessContainer.trailingAnchor.constraint(equalTo: volumeBrightnessProgressBar.trailingAnchor, constant: 10),
            volumeBrightnessProgressBar.centerYAnchor.constraint(equalTo: volumeBrightnessContainer.centerYAnchor),

            // 双击快进图标（屏幕中央）
            forwardSeekIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            forwardSeekIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            forwardSeekIcon.widthAnchor.constraint(equalToConstant: 30),
            forwardSeekIcon.heightAnchor.constraint(equalToConstant: 30),

            // 双击快退图标（屏幕中央）
            backwardSeekIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            backwardSeekIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            backwardSeekIcon.widthAnchor.constraint(equalToConstant: 30),
            backwardSeekIcon.heightAnchor.constraint(equalToConstant: 30)
        ])

        // 单独设置底部容器的底部约束，往上移 8pt 避免太贴底
        bottomContainerBottomConstraint = bottomContainerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8)
        bottomContainerBottomConstraint?.isActive = true
    }

    private func setupGestures() {
        // 注意：单击手勢已移至容器层处理，以确保隐藏时也能接收事件
    }

    // MARK: - 触摸处理優化

    /// 重写 hitTest 以确保各控件能正确接收触摸事件
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // 检查播放/暂停按钮
        let playPausePoint = convert(point, to: playPauseButton)
        if playPauseButton.point(inside: playPausePoint, with: event) {
            return playPauseButton
        }

        // 检查中央播放按钮
        if !centerPlayButton.isHidden {
            let centerPlayPoint = convert(point, to: centerPlayButton)
            if centerPlayButton.point(inside: centerPlayPoint, with: event) {
                return centerPlayButton
            }
        }

        // 检查弹幕输入框
        let textFieldPoint = convert(point, to: danmakuTextField)
        if danmakuTextField.point(inside: textFieldPoint, with: event) {
            return danmakuTextField
        }

        // 检查弹幕按钮容器
        let buttonContainerPoint = convert(point, to: danmakuButtonContainer)
        if danmakuButtonContainer.point(inside: buttonContainerPoint, with: event) {
            // 检查具体是哪个按钮
            let togglePoint = convert(point, to: danmakuToggleButton)
            if danmakuToggleButton.point(inside: togglePoint, with: event) {
                return danmakuToggleButton
            }
            let settingsPoint = convert(point, to: danmakuSettingsButton)
            if danmakuSettingsButton.point(inside: settingsPoint, with: event) {
                return danmakuSettingsButton
            }
            return danmakuButtonContainer
        }

        // 检查全屏按钮
        let fullScreenPoint = convert(point, to: fullScreenButton)
        if fullScreenButton.point(inside: fullScreenPoint, with: event) {
            return fullScreenButton
        }

        // 检查弹幕发送按钮（优先于进度条，避免触摸区域冲突）
        let sendButtonPoint = convert(point, to: danmakuSendButton)
        if danmakuSendButton.point(inside: sendButtonPoint, with: event) {
            return danmakuSendButton
        }

        // 检查进度条
        let sliderPoint = convert(point, to: progressSlider)
        if progressSlider.point(inside: sliderPoint, with: event) {
            return progressSlider
        }

        // 否则使用默认的 hitTest 邏輯
        return super.hitTest(point, with: event)
    }

    private func setupActions() {
        // 设置 accessibility 用于 UI 测试
        centerPlayButton.accessibilityIdentifier = "centerPlayButton"
        centerPlayButton.accessibilityLabel = "播放暂停"
        playPauseButton.accessibilityIdentifier = "playPauseButton"
        playPauseButton.accessibilityLabel = "播放暂停"

        centerPlayButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        fullScreenButton.addTarget(self, action: #selector(fullScreenTapped), for: .touchUpInside)

        // 弹幕按钮事件
        danmakuToggleButton.addTarget(self, action: #selector(danmakuToggleTapped), for: .touchUpInside)
        danmakuSettingsButton.addTarget(self, action: #selector(danmakuSettingsTapped), for: .touchUpInside)
        danmakuSendButton.addTarget(self, action: #selector(danmakuSendTapped), for: .touchUpInside)
        danmakuTextField.delegate = self

        // 进度条事件
        progressSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(sliderTouchBegan), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(sliderTouchEnded), for: [.touchUpInside, .touchUpOutside])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 更新渐变层大小
        if let gradientLayer = layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = bounds
        }
    }

    // MARK: - 公共方法

    /// 更新播放状态
    func updatePlaybackState(isPlaying: Bool, showReplay: Bool = false) {
        print("🎬 updatePlaybackState - isPlaying: \(isPlaying), showReplay: \(showReplay)")
        viewModel.isPlaying = isPlaying

        // 使用图片资源
        let playImage = UIImage.dxPlayerImage(named: "play_icon", renderingMode: .alwaysTemplate)
        let pauseImage = UIImage.dxPlayerImage(named: "pause_icon", renderingMode: .alwaysTemplate)
        let replayImage = UIImage.dxPlayerImage(named: "replay_icon", renderingMode: .alwaysTemplate)

        print("   图片加载状态 - play: \(playImage != nil), pause: \(pauseImage != nil), replay: \(replayImage != nil)")

        // 如果需要显示重播圖标
        if showReplay {
            print("   ✅ 设置重播圖标")
            centerPlayButton.setImage(replayImage, for: .normal)
            centerPlayButton.isHidden = false
            playPauseButton.setImage(replayImage, for: .normal)
            print("   centerPlayButton.isHidden = \(centerPlayButton.isHidden)")
            print("   centerPlayButton 图片已设置: \(centerPlayButton.image(for: .normal) != nil)")
        } else {
            print("   ℹ️  正常播放/暂停状态")
            playPauseButton.setImage(isPlaying ? pauseImage : playImage, for: .normal)
            centerPlayButton.setImage(isPlaying ? pauseImage : playImage, for: .normal)
            centerPlayButton.isHidden = isPlaying
        }

        if isPlaying {
            resetAutoHideTimer()
        }
    }

    /// 更新播放进度
    func updateProgress(current: TimeInterval, duration: TimeInterval) {
        viewModel.updateProgress(current: current, duration: duration)

        // 只有在用戶沒有拖动进度条且沒有正在 seek 时才更新时间标籤和进度条
        // 如果用戶正在拖动或正在 seek，时间标籤会由 sliderValueChanged 更新
        if !isSliderDragging && !isSeeking {
            // 更新时间显示为 "当前 / 总时长" 格式
            let currentStr = viewModel.formatTime(current)
            let durationStr = viewModel.formatTime(duration)
            timeLabel.text = "\(currentStr) / \(durationStr)"
            let progress = viewModel.progressPercentage()
            progressSlider.progress = progress
        }

        // 同步 duration 到进度条（用于缩略图预览计算）
        if progressSlider.duration != duration {
            DXPlayerLogger.debug("🖼️ [控制视图] 更新 progressSlider.duration: \(duration)")
            progressSlider.duration = duration
        }
    }

    /// 更新缓冲进度
    func updateBufferProgress(_ buffer: Float) {
        progressSlider.bufferProgress = buffer
    }

    /// 更新缓冲状态
    func updateBuffering(isBuffering: Bool) {
        if isBuffering {
            activityIndicator.startAnimating()
            playPauseButton.isEnabled = false
        } else {
            activityIndicator.stopAnimating()
            playPauseButton.isEnabled = true
        }
    }

    /// 更新全屏状态
    func updateFullScreenState(isFullScreen: Bool) {
        isInFullScreen = isFullScreen

        // 使用相同圖标（可以將来添加不同的全屏/退出全屏圖标）
        let fullscreenImage = UIImage.dxPlayerImage(named: "fullscreen_icon", renderingMode: .alwaysTemplate)
        fullScreenButton.setImage(fullscreenImage, for: .normal)

        // 全屏时需要重新设置约束以适应横屏模式的 safe area
        // 触发布局更新
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// 重写 safeAreaInsetsDidChange 以处理横屏时 Home Indicator 区域的变化
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()

        // 当 safe area 改变时（例如横屏），更新底部容器的位置
        if isInFullScreen {
            // 在全屏横屏模式下，确保底部控制条在 safe area 内
            let bottomInset = safeAreaInsets.bottom
            print("🎬 [控制视图] safeAreaInsetsDidChange - bottom: \(bottomInset), isFullScreen: \(isInFullScreen)")

            // 强制触发布局更新
            setNeedsLayout()
        }
    }

    /// 检查弹幕输入框是否正在编辑
    func isDanmakuTextFieldEditing() -> Bool {
        return danmakuTextField.isFirstResponder
    }

    /// 收起弹幕输入键盘
    func dismissDanmakuKeyboard() {
        danmakuTextField.resignFirstResponder()
    }

    /// 设置视频标题
    func setTitle(_ title: String) {
        titleLabel.text = title
    }

    /// 显示滑动快进/快退预览
    /// - Parameters:
    ///   - currentTime: 目标播放时间
    ///   - duration: 视频总时长
    ///   - progress: 播放进度（0.0-1.0）
    func showSeekPreview(currentTime: TimeInterval, duration: TimeInterval, progress: Float) {
        // 格式化时间显示
        let currentTimeStr = viewModel.formatTime(currentTime)
        let durationStr = viewModel.formatTime(duration)
        seekTimeLabel.text = "\(currentTimeStr) / \(durationStr)"

        // 更新进度条
        seekProgressBar.progress = progress

        // 显示容器
        if seekPreviewContainer.isHidden {
            seekPreviewContainer.isHidden = false
            UIView.animate(withDuration: 0.2) {
                self.seekPreviewContainer.alpha = 1.0
            }
        }
    }

    /// 隐藏滑动快进/快退预览
    func hideSeekPreview() {
        UIView.animate(withDuration: 0.2, animations: {
            self.seekPreviewContainer.alpha = 0.0
        }) { _ in
            self.seekPreviewContainer.isHidden = true
        }
    }

    /// 显示音量/亮度指示器
    /// - Parameters:
    ///   - value: 当前值（0.0-1.0）
    ///   - isVolume: true表示音量，false表示亮度
    func showVolumeIndicator(value: Float, isVolume: Bool) {
        // 根据值和类型选择合适的图标
        let iconName: String
        if isVolume {
            // 音量图标
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
            // 亮度图标
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

        // 显示容器
        if volumeBrightnessContainer.isHidden {
            volumeBrightnessContainer.isHidden = false
            UIView.animate(withDuration: 0.2) {
                self.volumeBrightnessContainer.alpha = 1.0
            }
        }
    }

    /// 隐藏音量/亮度指示器
    func hideVolumeIndicator() {
        print("hideVolumeIndicator 被调用")
        UIView.animate(withDuration: 0.2, animations: {
            self.volumeBrightnessContainer.alpha = 0.0
        }) { _ in
            self.volumeBrightnessContainer.isHidden = true
            print("音量/亮度指示器已隐藏")
        }
    }

    /// 显示双击快进动画（前进10秒）
    func showForwardSeekAnimation() {
        // 确保图标可见
        forwardSeekIcon.isHidden = false

        // 淡入动画（100ms）
        UIView.animate(withDuration: 0.1, animations: {
            self.forwardSeekIcon.alpha = 1.0
            // 添加轻微缩放效果
            self.forwardSeekIcon.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }) { _ in
            // 保持可见200ms后淡出
            UIView.animate(withDuration: 0.1, delay: 0.2, options: [], animations: {
                self.forwardSeekIcon.alpha = 0.0
                self.forwardSeekIcon.transform = .identity
            }) { _ in
                self.forwardSeekIcon.isHidden = true
            }
        }
    }

    /// 显示双击快退动画（后退10秒）
    func showBackwardSeekAnimation() {
        // 确保图标可见
        backwardSeekIcon.isHidden = false

        // 淡入动画（100ms）
        UIView.animate(withDuration: 0.1, animations: {
            self.backwardSeekIcon.alpha = 1.0
            // 添加轻微缩放效果
            self.backwardSeekIcon.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }) { _ in
            // 保持可见200ms后淡出
            UIView.animate(withDuration: 0.1, delay: 0.2, options: [], animations: {
                self.backwardSeekIcon.alpha = 0.0
                self.backwardSeekIcon.transform = .identity
            }) { _ in
                self.backwardSeekIcon.isHidden = true
            }
        }
    }

    /// 显示控制层
    func show(animated: Bool = true, autoHide: Bool = true) {
        isVisible = true
        isHidden = false
        isUserInteractionEnabled = true  // 显示时启用交互
        let duration = animated ? 0.3 : 0

        UIView.animate(withDuration: duration) {
            self.alpha = 1.0
        }

        if autoHide {
            resetAutoHideTimer()
        } else {
            // 如果不需要自動隐藏，仍然取消现有的计时器
            autoHideTimer?.invalidate()
        }
    }

    /// 隐藏控制层
    func hide(animated: Bool = true) {
        guard isVisible else { return }

        isVisible = false
        autoHideTimer?.invalidate()
        isUserInteractionEnabled = false  // 隐藏时禁用交互，讓手勢穿透到下层

        let duration = animated ? 0.3 : 0

        UIView.animate(withDuration: duration, animations: {
            self.alpha = 0.0
        }) { _ in
            // 動画结束後才设置 isHidden，确保動画流暢
            self.isHidden = true
        }
    }

    /// 強制隐藏中央播放按鈕（用于显示 loading 时避免重疊）
    func hideCenterPlayButton() {
        centerPlayButton.isHidden = true
    }

    /// 根据播放状态显示中央播放按鈕
    func showCenterPlayButtonIfNeeded() {
        // 只有暂停或重播状态才显示中央按鈕
        // 播放中时应該隐藏
        centerPlayButton.isHidden = viewModel.isPlaying
    }

    // MARK: - 私有方法

    private func resetAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(
            withTimeInterval: autoHideDelay,
            repeats: false
        ) { [weak self] _ in
            if self?.viewModel.isPlaying == true {
                self?.hide(animated: true)
            }
        }
    }

    // MARK: - 按钮事件

    @objc private func playPauseTapped() {
        delegate?.controlViewDidTapPlayPause()
        resetAutoHideTimer()
    }

    @objc private func fullScreenTapped() {
        delegate?.controlViewDidTapFullScreen()
        resetAutoHideTimer()
    }

    // MARK: - 进度条事件

    @objc private func sliderTouchBegan() {
        isSliderDragging = true
        autoHideTimer?.invalidate()
        delegate?.controlViewDidBeginDrag()

        // 暂停播放（如果正在播放）
        if delegate?.controlViewDidRequestPlaybackState() ?? false {
            delegate?.controlViewDidPause()
        }
    }

    @objc private func sliderTouchEnded() {
        // 先设置 seeking 标誌，防止 seek 期间被自動更新覆蓋
        isSeeking = true
        isSliderDragging = false

        let duration = delegate?.controlViewDidRequestDuration() ?? 0
        let targetTime = TimeInterval(progressSlider.progress) * duration

        print("📍 进度条拖曳结束 - targetTime: \(targetTime), duration: \(duration)")

        // ✅ 检查是否拖到视频末尾（留 0.5 秒误差）
        if targetTime >= duration - 0.5 {
            print("🎬 进度条拖到视频末尾，直接触发结束邏輯")
            // seek 到末尾（controlViewDidSeek 內部会直接设置 replay 状态）
            delegate?.controlViewDidSeek(to: duration)

            // 立即同步触发播放结束邏輯（不延遲，避免中间状态闪爍）
            delegate?.controlViewDidSeekToEnd()
            isSeeking = false
        } else {
            // 正常 seek
            delegate?.controlViewDidSeek(to: targetTime)

            // seek 後自動播放（无論之前是否在播放）
            delegate?.controlViewDidResume()

            // 延遲 0.5 秒後重新允許自動更新，給 seek 操作足夠的时间
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isSeeking = false
            }
        }

        delegate?.controlViewDidEndDrag()
        resetAutoHideTimer()
    }

    @objc private func sliderValueChanged() {
        let duration = delegate?.controlViewDidRequestDuration() ?? 0
        let targetTime = TimeInterval(progressSlider.progress) * duration
        let currentStr = viewModel.formatTime(targetTime)
        let durationStr = viewModel.formatTime(duration)
        timeLabel.text = "\(currentStr) / \(durationStr)"
    }

    // MARK: - 弹幕控制

    @objc private func danmakuToggleTapped() {
        isDanmakuEnabled.toggle()
        updateDanmakuToggleAppearance()
        onDanmakuToggle?(isDanmakuEnabled)
        resetAutoHideTimer()
    }

    @objc private func danmakuSettingsTapped() {
        onDanmakuSettings?()
        resetAutoHideTimer()
    }

    @objc private func danmakuSendTapped() {
        guard let text = danmakuTextField.text, !text.isEmpty else { return }
        onSendDanmaku?(text)
        danmakuTextField.text = ""
        danmakuTextField.resignFirstResponder()
        resetAutoHideTimer()
    }

    private func updateDanmakuToggleAppearance() {
        // 使用 selected 狀態切換 icon
        danmakuToggleButton.isSelected = !isDanmakuEnabled
    }

    /// 设置弹幕开关状态（外部调用）
    func setDanmakuEnabled(_ enabled: Bool) {
        isDanmakuEnabled = enabled
        updateDanmakuToggleAppearance()
    }

    // MARK: - 清理

    deinit {
        autoHideTimer?.invalidate()
    }
}

// MARK: - UITextFieldDelegate

extension PlayerControlView: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        if textField == danmakuTextField {
            // 用户开始输入时，停止自动隐藏
            autoHideTimer?.invalidate()
        }
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField == danmakuTextField {
            // 用户结束输入时，重新开始自动隐藏计时
            resetAutoHideTimer()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == danmakuTextField {
            if let text = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                onSendDanmaku?(text)
                textField.text = nil
            }
            textField.resignFirstResponder()
            resetAutoHideTimer()
        }
        return true
    }
}

