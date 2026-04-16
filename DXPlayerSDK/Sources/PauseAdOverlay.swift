import UIKit
@_exported import FSPlayer

/// 暂停广告覆盖层
/// 显示中央广告图片或视频，和关闭按钮
class PauseAdOverlay: UIView {

    // MARK: - UI 组件

    private let backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0, alpha: 0.7)
        return view
    }()

    private let adContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 10
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.3
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 10
        return view
    }()

    private let adLabel: UILabel = {
        let label = UILabel()
        label.text = "广告"
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = UIColor(white: 0.4, alpha: 1.0)
        label.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        label.textAlignment = .center
        label.layer.cornerRadius = 3
        label.clipsToBounds = true
        return label
    }()

    private let closeButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setTitle("✕", for: .normal)
        button.setTitleColor(UIColor(white: 0.3, alpha: 1.0), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        button.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        button.layer.cornerRadius = 15
        button.clipsToBounds = true
        return button
    }()

    private let adImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 0.98, alpha: 1.0)
        return imageView
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .gray
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - 回调

    var onAdClick: (() -> Void)?
    var onClose: (() -> Void)?

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - UI 设置

    private func setupUI() {
        backgroundColor = .clear

        // 添加子视图
        addSubview(backgroundView)
        addSubview(adContainer)
        adContainer.addSubview(adImageView)
        adContainer.addSubview(adLabel)
        adContainer.addSubview(closeButton)
        adContainer.addSubview(loadingIndicator)

        // 设置约束
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        adContainer.translatesAutoresizingMaskIntoConstraints = false
        adImageView.translatesAutoresizingMaskIntoConstraints = false
        adLabel.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // 背景视图 - 填充整个覆盖层
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 广告容器 - 居中显示
            adContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            adContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            adContainer.widthAnchor.constraint(equalToConstant: 300),
            adContainer.heightAnchor.constraint(equalToConstant: 200),

            // 广告标签 - 左上角
            adLabel.topAnchor.constraint(equalTo: adContainer.topAnchor, constant: 8),
            adLabel.leadingAnchor.constraint(equalTo: adContainer.leadingAnchor, constant: 8),
            adLabel.widthAnchor.constraint(equalToConstant: 40),
            adLabel.heightAnchor.constraint(equalToConstant: 20),

            // 关闭按钮 - 右上角
            closeButton.topAnchor.constraint(equalTo: adContainer.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: adContainer.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            // 广告图片 - 填充容器（留出顶部空间给标签和按钮）
            adImageView.topAnchor.constraint(equalTo: adLabel.bottomAnchor, constant: 8),
            adImageView.leadingAnchor.constraint(equalTo: adContainer.leadingAnchor, constant: 10),
            adImageView.trailingAnchor.constraint(equalTo: adContainer.trailingAnchor, constant: -10),
            adImageView.bottomAnchor.constraint(equalTo: adContainer.bottomAnchor, constant: -10),

            // 加载指示器 - 中央
            loadingIndicator.centerXAnchor.constraint(equalTo: adImageView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: adImageView.centerYAnchor)
        ])

        // 设置 accessibility
        closeButton.accessibilityIdentifier = "pauseAdCloseButton"
        closeButton.accessibilityLabel = "关闭暂停广告"
        closeButton.isAccessibilityElement = true
        adContainer.accessibilityIdentifier = "pauseAdContainer"
        adContainer.accessibilityLabel = "暂停广告容器"
        adContainer.isAccessibilityElement = false // 让子元素可被发现
        adLabel.accessibilityIdentifier = "pauseAdLabel"
        adLabel.isAccessibilityElement = true

        // 整个 overlay 也标记为可访问
        self.accessibilityIdentifier = "pauseAdOverlay"

        // 添加手势识别
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(adContainerTapped))
        adContainer.addGestureRecognizer(tapGesture)

        // 添加按钮事件
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)

        // 显示加载指示器
        loadingIndicator.startAnimating()
    }

    // MARK: - 视频播放器

    private var adPlayer: FSPlayer?

    // MARK: - 配置

    func setAdImage(_ image: UIImage?) {
        loadingIndicator.stopAnimating()

        if let image = image {
            adImageView.image = image
            DXPlayerLogger.debug("🎨 [广告覆盖层] 暂停广告图片加载成功")
        } else {
            adImageView.image = nil
            adImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
            DXPlayerLogger.warning("⚠️ [广告覆盖层] 暂停广告图片加载失败")
        }
    }

    /// 设置视频广告（替换图片区域为视频播放器）
    func setAdVideo(url: URL) {
        loadingIndicator.stopAnimating()
        adImageView.isHidden = true

        let options = FSOptions.byDefault()
        options.setFormatOptionValue("file,http,https,tcp,tls,crypto,data,subfile,concat", forKey: "protocol_whitelist")
        let player = FSPlayer(contentURL: url, with: options)
        player.scalingMode = .aspectFit
        player.shouldAutoplay = true

        if let playerView = player.view {
            playerView.translatesAutoresizingMaskIntoConstraints = false
            adContainer.insertSubview(playerView, belowSubview: adLabel)
            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: adLabel.bottomAnchor, constant: 8),
                playerView.leadingAnchor.constraint(equalTo: adContainer.leadingAnchor, constant: 10),
                playerView.trailingAnchor.constraint(equalTo: adContainer.trailingAnchor, constant: -10),
                playerView.bottomAnchor.constraint(equalTo: adContainer.bottomAnchor, constant: -10)
            ])
        }

        adPlayer = player
        player.prepareToPlay()
        player.play()

        DXPlayerLogger.debug("🎬 [广告覆盖层] 暂停广告视频开始播放")
    }

    /// 停止视频播放并清理
    func stopAdVideo() {
        adPlayer?.stop()
        adPlayer?.view?.removeFromSuperview()
        adPlayer = nil
    }

    func updateAdContainerSize(_ size: CGSize) {
        // 更新广告容器尺寸
        adContainer.constraints.forEach { constraint in
            if constraint.firstAttribute == .width {
                constraint.constant = size.width
            } else if constraint.firstAttribute == .height {
                constraint.constant = size.height
            }
        }
        layoutIfNeeded()
    }

    // MARK: - 事件处理

    @objc private func adContainerTapped() {
        DXPlayerLogger.debug("👆 [广告覆盖层] 暂停广告点击")
        onAdClick?()
    }

    @objc private func closeButtonTapped() {
        DXPlayerLogger.debug("👆 [广告覆盖层] 关闭按钮点击")
        onClose?()
    }
}
