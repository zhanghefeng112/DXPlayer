import UIKit

/// 片头广告覆盖层
/// 显示倒计时、VIP 跳过按钮、了解详情按钮
class PrerollAdOverlay: UIView {

    // MARK: - UI 组件

    // 右上角控制容器
    private let topRightContainer: UIView = {
        let container = UIView()
        container.backgroundColor = UIColor(white: 0, alpha: 0.6)
        container.layer.cornerRadius = 20
        container.clipsToBounds = true
        return container
    }()

    // 倒数秒数按钮（圆形蓝色）
    private let countdownButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        button.backgroundColor = UIColor(red: 0x00/255.0, green: 0x95/255.0, blue: 0xFF/255.0, alpha: 1.0)
        button.layer.cornerRadius = 15 // 圓形（直徑30）
        button.clipsToBounds = true
        return button
    }()

    // VIP 跳过文字
    private let vipLabel: UILabel = {
        let label = UILabel()
        label.text = "VIP跳过该广告"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        return label
    }()

    // 关闭按钮（叉叉 icon）
    private let closeButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setTitle("✕", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        button.backgroundColor = .clear
        return button
    }()

    private let detailButton: UIView = {
        let container = UIView()

        // 设置蓝色背景 #0095FF
        container.backgroundColor = UIColor(red: 0x00/255.0, green: 0x95/255.0, blue: 0xFF/255.0, alpha: 1.0)

        // 设置圆角
        container.layer.cornerRadius = 20
        container.clipsToBounds = true

        // 創建 UIImageView 顯示圖標
        let iconImageView = UIImageView()
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        // 加載圖標
        if let iconImage = UIImage.dxPlayerImage(named: "ad_detail_icon") {
            DXPlayerLogger.debug("✅ [PrerollAdOverlay] 成功加載 ad_detail_icon，原始大小: \(iconImage.size)")
            iconImageView.image = iconImage
        } else {
            DXPlayerLogger.error("❌ [PrerollAdOverlay] 無法加載 ad_detail_icon 圖標！")
        }

        // 創建 UILabel 顯示文字
        let titleLabel = UILabel()
        titleLabel.text = "了解详情即可跳过广告"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 添加到容器
        container.addSubview(iconImageView)
        container.addSubview(titleLabel)

        // 設置約束
        NSLayoutConstraint.activate([
            // 圖標約束：左邊距 18pt，垂直居中，固定高度 16pt（與 14pt 字體視覺等高），保持 1:1 比例
            iconImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            iconImageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconImageView.heightAnchor.constraint(equalToConstant: 16), // 固定高度 16pt
            iconImageView.widthAnchor.constraint(equalTo: iconImageView.heightAnchor), // 保持 1:1 比例

            // 文字約束：距離圖標 8pt，垂直居中，右邊距 18pt
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18)
        ])

        return container
    }()

    // MARK: - 回调

    var onDetailClick: (() -> Void)?
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

        // 添加主容器
        addSubview(topRightContainer)
        addSubview(detailButton)

        // 將元素添加到右上角容器
        topRightContainer.addSubview(countdownButton)
        topRightContainer.addSubview(vipLabel)
        topRightContainer.addSubview(closeButton)

        // 设置约束
        topRightContainer.translatesAutoresizingMaskIntoConstraints = false
        countdownButton.translatesAutoresizingMaskIntoConstraints = false
        vipLabel.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        detailButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // 右上角容器
            topRightContainer.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            topRightContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -10),
            topRightContainer.heightAnchor.constraint(equalToConstant: 40),

            // 倒数按钮 - 容器左边（圓形 30×30）
            countdownButton.leadingAnchor.constraint(equalTo: topRightContainer.leadingAnchor, constant: 5),
            countdownButton.centerYAnchor.constraint(equalTo: topRightContainer.centerYAnchor),
            countdownButton.widthAnchor.constraint(equalToConstant: 30),
            countdownButton.heightAnchor.constraint(equalToConstant: 30),

            // VIP 文字 - 中间
            vipLabel.leadingAnchor.constraint(equalTo: countdownButton.trailingAnchor, constant: 8),
            vipLabel.centerYAnchor.constraint(equalTo: topRightContainer.centerYAnchor),
            vipLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),

            // 关闭按钮 - 容器右边
            closeButton.trailingAnchor.constraint(equalTo: topRightContainer.trailingAnchor, constant: -5),
            closeButton.centerYAnchor.constraint(equalTo: topRightContainer.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            // 了解详情按钮 - 在控制按鈕列上方
            detailButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            detailButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -36), // 在控制條上方
            detailButton.heightAnchor.constraint(equalToConstant: 40) // 容器固定高度
        ])

        // 设置 accessibility
        closeButton.accessibilityIdentifier = "prerollCloseButton"
        closeButton.accessibilityLabel = "关闭片头广告"
        detailButton.accessibilityIdentifier = "prerollDetailButton"
        detailButton.accessibilityLabel = "了解详情即可跳过广告"
        vipLabel.accessibilityIdentifier = "prerollVipLabel"
        countdownButton.accessibilityIdentifier = "prerollCountdown"

        // 添加按钮事件
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)

        // 点击"跳过广告"文字也能触发关闭
        vipLabel.isUserInteractionEnabled = true
        let skipTapGesture = UITapGestureRecognizer(target: self, action: #selector(skipLabelTapped))
        vipLabel.addGestureRecognizer(skipTapGesture)

        // 為詳情按鈕添加點擊手勢
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(detailButtonTapped))
        detailButton.addGestureRecognizer(tapGesture)
        detailButton.isUserInteractionEnabled = true
    }


    // MARK: - 跳过控制

    private var canSkip: Bool = true
    private var allowSkipTime: Int = 0
    private var totalDuration: Int = 15

    /// 已经过的秒数
    private var elapsedSeconds: Int {
        totalDuration - currentCountdown
    }

    /// 当前是否可以跳过
    private var canSkipNow: Bool {
        canSkip && elapsedSeconds >= allowSkipTime
    }

    private var currentCountdown: Int = 0

    // MARK: - 配置

    func configure(countdown: Int, isVIP: Bool, hasDetailButton: Bool, canSkip: Bool = true, allowSkipTime: Int = 0) {
        self.canSkip = canSkip
        self.allowSkipTime = allowSkipTime
        self.totalDuration = countdown
        self.currentCountdown = countdown

        updateCountdown(countdown)
        detailButton.isHidden = !hasDetailButton
        updateSkipUI()

        DXPlayerLogger.debug("🎨 [广告覆盖层] 配置片头广告 - 倒计时:\(countdown)秒, VIP:\(isVIP), 详情:\(hasDetailButton), canSkip:\(canSkip), allowSkipTime:\(allowSkipTime)")
    }

    func updateCountdown(_ seconds: Int) {
        currentCountdown = seconds
        countdownButton.setTitle("\(seconds)", for: .normal)
        updateSkipUI()
    }

    private func updateSkipUI() {
        if !canSkip {
            // 不允许跳过：隐藏所有跳过相关 UI
            topRightContainer.isHidden = true
            return
        }

        topRightContainer.isHidden = false

        if canSkipNow {
            vipLabel.text = "跳过广告"
            vipLabel.textColor = .white
            closeButton.isHidden = false
            closeButton.isEnabled = true
        } else {
            let remaining = allowSkipTime - elapsedSeconds
            vipLabel.text = "\(remaining)s 后可跳过"
            vipLabel.textColor = UIColor.white.withAlphaComponent(0.5)
            closeButton.isHidden = true
            closeButton.isEnabled = false
        }
    }

    // MARK: - 事件处理

    @objc private func closeButtonTapped() {
        DXPlayerLogger.debug("👆 [广告覆盖层] 关闭按钮点击")
        onClose?()
    }

    @objc private func skipLabelTapped() {
        guard canSkipNow else { return }
        DXPlayerLogger.debug("👆 [广告覆盖层] 跳过广告文字点击")
        onClose?()
    }

    @objc private func detailButtonTapped() {
        DXPlayerLogger.debug("👆 [广告覆盖层] 了解详情按钮点击")
        onDetailClick?()
    }
}
