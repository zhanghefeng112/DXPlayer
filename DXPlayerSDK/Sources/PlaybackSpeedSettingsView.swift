import UIKit

/// 播放倍速設定視圖
/// 從右側滑入顯示，包含倍速選項列表
public class PlaybackSpeedSettingsView: UIView {

    // MARK: - 常量

    private let containerWidth: CGFloat = 200
    private var isAnimating: Bool = false

    /// 支持的播放速度列表（設計稿順序：從快到慢）
    private let speedOptions: [Float] = [3.0, 2.0, 1.5, 1.25, 1.0, 0.75]

    // MARK: - UI 組件

    /// 背景遮罩
    private let dimView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.0)
        return view
    }()

    /// 容器視圖（毛玻璃效果）
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        view.clipsToBounds = true
        return view
    }()

    /// 毛玻璃效果視圖
    private let blurEffectView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .dark)
        let view = UIVisualEffectView(effect: blurEffect)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }()

    /// 標題
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "倍速"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        return label
    }()

    /// 選項列表
    private let optionsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .fill
        stack.distribution = .fillEqually
        return stack
    }()

    // MARK: - 屬性

    /// 當前選中的速度
    private var currentSpeed: Float = 1.0

    // MARK: - 回調

    /// 速度變更回調
    public var onSpeedChanged: ((Float) -> Void)?

    /// 關閉回調
    public var onClose: (() -> Void)?

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - UI 設置

    private func setupUI() {
        backgroundColor = .clear

        // 添加背景遮罩
        addSubview(dimView)
        dimView.frame = bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.alpha = 0

        // 添加點擊遮罩關閉的手勢
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dimViewTapped))
        dimView.addGestureRecognizer(tapGesture)

        // 添加容器
        addSubview(containerView)

        // 添加毛玻璃效果
        blurEffectView.frame = containerView.bounds
        containerView.addSubview(blurEffectView)

        // 添加標題
        containerView.addSubview(titleLabel)
        containerView.addSubview(optionsStackView)

        // 構建選項列表
        buildSpeedOptions()
    }

    private func buildSpeedOptions() {
        optionsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for speed in speedOptions {
            let optionView = createOptionView(speed: speed)
            optionsStackView.addArrangedSubview(optionView)
        }
    }

    private func createOptionView(speed: Float) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let button = UIButton(type: .custom)
        button.tag = Int(speed * 100)  // 用於識別

        // 速度文字
        let speedText: String
        if speed.truncatingRemainder(dividingBy: 1.0) == 0 {
            speedText = "\(Int(speed)).0X"
        } else {
            speedText = String(format: "%.2gX", speed)
        }
        button.setTitle(speedText, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.contentHorizontalAlignment = .left
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        // 選中標記
        let checkImageView = UIImageView()
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            checkImageView.image = UIImage(systemName: "checkmark", withConfiguration: config)
        }
        checkImageView.tintColor = .systemBlue
        checkImageView.contentMode = .scaleAspectFit
        checkImageView.isHidden = !isSpeedSelected(speed)
        checkImageView.tag = 1001  // 用於查找

        button.translatesAutoresizingMaskIntoConstraints = false
        checkImageView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(button)
        container.addSubview(checkImageView)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            checkImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            checkImageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            checkImageView.widthAnchor.constraint(equalToConstant: 20),
            checkImageView.heightAnchor.constraint(equalToConstant: 20)
        ])

        button.addTarget(self, action: #selector(speedOptionTapped(_:)), for: .touchUpInside)

        return container
    }

    private func isSpeedSelected(_ speed: Float) -> Bool {
        return abs(speed - currentSpeed) < 0.01
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        guard !isAnimating else { return }

        let width = bounds.width
        let height = bounds.height

        // 容器位置（右側）
        containerView.frame = CGRect(
            x: width - containerWidth,
            y: 0,
            width: containerWidth,
            height: height
        )

        layoutContainerSubviews()
    }

    private func layoutContainerSubviews() {
        let width = containerView.bounds.width
        let height = containerView.bounds.height
        let safeTop: CGFloat = max(safeAreaInsets.top + 10, 20)

        // 標題
        titleLabel.frame = CGRect(x: 16, y: safeTop, width: width - 32, height: 24)

        // 選項列表（使用全部可用高度）
        let optionsTop = safeTop + 40
        let optionHeight: CGFloat = 44
        let totalOptionsHeight = CGFloat(speedOptions.count) * optionHeight + CGFloat(speedOptions.count - 1) * 4
        let safeBottom = max(safeAreaInsets.bottom, 10)
        optionsStackView.frame = CGRect(
            x: 0,
            y: optionsTop,
            width: width,
            height: min(totalOptionsHeight, height - optionsTop - safeBottom)
        )
    }

    // MARK: - 公共方法

    /// 設置當前速度
    public func setCurrentSpeed(_ speed: Float) {
        currentSpeed = speed
        updateCheckmarks()
    }

    private func updateCheckmarks() {
        for arrangedView in optionsStackView.arrangedSubviews {
            if let checkImageView = arrangedView.viewWithTag(1001) as? UIImageView {
                // 從按鈕 tag 獲取速度
                if let button = arrangedView.subviews.first(where: { $0 is UIButton }) as? UIButton {
                    let speed = Float(button.tag) / 100.0
                    checkImageView.isHidden = !isSpeedSelected(speed)
                }
            }
        }
    }

    /// 顯示面板
    public func show(animated: Bool = true) {
        setNeedsLayout()
        layoutIfNeeded()

        // 初始狀態
        dimView.alpha = 0
        containerView.transform = CGAffineTransform(translationX: containerWidth, y: 0)

        if animated {
            isAnimating = true
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
                self.dimView.alpha = 1
                self.containerView.transform = .identity
            }, completion: { _ in
                self.isAnimating = false
            })
        } else {
            dimView.alpha = 1
            containerView.transform = .identity
        }
    }

    /// 隱藏面板
    public func hide(animated: Bool = true) {
        if animated {
            isAnimating = true
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn, animations: {
                self.dimView.alpha = 0
                self.containerView.transform = CGAffineTransform(translationX: self.containerWidth, y: 0)
            }, completion: { _ in
                self.isAnimating = false
                self.removeFromSuperview()
                self.onClose?()
            })
        } else {
            removeFromSuperview()
            onClose?()
        }
    }

    // MARK: - 事件處理

    @objc private func dimViewTapped() {
        hide(animated: true)
    }

    @objc private func speedOptionTapped(_ sender: UIButton) {
        let speed = Float(sender.tag) / 100.0
        currentSpeed = speed
        updateCheckmarks()
        onSpeedChanged?(speed)
        hide(animated: true)
    }
}
