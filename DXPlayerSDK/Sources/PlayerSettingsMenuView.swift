import UIKit

/// 設定菜單項目
public struct SettingsMenuItem {
    let icon: String  // SF Symbol 名稱
    let title: String
    let action: (() -> Void)?

    public init(icon: String, title: String, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.action = action
    }
}

/// 播放器設定菜單視圖
/// 從右側滑入顯示，包含網格佈局的設定項目
public class PlayerSettingsMenuView: UIView {

    // MARK: - 常量

    private let containerWidth: CGFloat = 280
    private var isAnimating: Bool = false

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
        label.text = "設定"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        return label
    }()

    /// 關閉按鈕
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        let image = UIImage(systemName: "xmark", withConfiguration: config)
        button.setImage(image, for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        button.layer.cornerRadius = 15
        return button
    }()

    /// 菜單項目網格
    private let gridStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.distribution = .fillEqually
        return stack
    }()

    // MARK: - 屬性

    /// 菜單項目
    private var menuItems: [SettingsMenuItem] = []

    // MARK: - 回調

    /// 關閉回調
    public var onClose: (() -> Void)?

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupDefaultMenuItems()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupDefaultMenuItems()
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

        // 添加標題和關閉按鈕
        containerView.addSubview(titleLabel)
        containerView.addSubview(closeButton)
        containerView.addSubview(gridStackView)

        // 關閉按鈕事件
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
    }

    private func setupDefaultMenuItems() {
        // 設計稿菜單項目
        menuItems = [
            SettingsMenuItem(icon: "arrow.down.circle", title: "下載"),
            SettingsMenuItem(icon: "tv", title: "投屏"),
            SettingsMenuItem(icon: "pip.enter", title: "畫中畫"),
            SettingsMenuItem(icon: "speaker.wave.2", title: "只聽音頻"),
            SettingsMenuItem(icon: "repeat", title: "循環播放"),
            SettingsMenuItem(icon: "text.bubble", title: "彈幕設置"),
            SettingsMenuItem(icon: "play.rectangle.on.rectangle", title: "自動連播"),
            SettingsMenuItem(icon: "speedometer", title: "倍速"),
            SettingsMenuItem(icon: "square.and.arrow.up", title: "分享"),
            SettingsMenuItem(icon: "timer", title: "定時關閉"),
            SettingsMenuItem(icon: "captions.bubble", title: "字幕"),
            SettingsMenuItem(icon: "exclamationmark.bubble", title: "播放反饋"),
            SettingsMenuItem(icon: "aspectratio", title: "畫面比例"),
            SettingsMenuItem(icon: "ellipsis.circle", title: "更多設置")
        ]
        buildMenuGrid()
    }

    private func buildMenuGrid() {
        // 清空現有視圖
        gridStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 每行 4 個項目
        let itemsPerRow = 4
        var currentRow: UIStackView?

        for (index, item) in menuItems.enumerated() {
            if index % itemsPerRow == 0 {
                currentRow = UIStackView()
                currentRow?.axis = .horizontal
                currentRow?.spacing = 8
                currentRow?.alignment = .fill
                currentRow?.distribution = .fillEqually
                gridStackView.addArrangedSubview(currentRow!)
            }

            let itemView = createMenuItemView(item: item, index: index)
            currentRow?.addArrangedSubview(itemView)
        }

        // 補齊最後一行
        if let lastRow = gridStackView.arrangedSubviews.last as? UIStackView {
            let remaining = itemsPerRow - lastRow.arrangedSubviews.count
            for _ in 0..<remaining {
                let spacer = UIView()
                spacer.backgroundColor = .clear
                lastRow.addArrangedSubview(spacer)
            }
        }
    }

    private func createMenuItemView(item: SettingsMenuItem, index: Int) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        container.layer.cornerRadius = 8
        container.tag = index

        let iconImageView = UIImageView()
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            iconImageView.image = UIImage(systemName: item.icon, withConfiguration: config)
        }
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconImageView)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -6)
        ])

        // 添加點擊手勢
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(menuItemTapped(_:)))
        container.addGestureRecognizer(tapGesture)
        container.isUserInteractionEnabled = true

        return container
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
        let safeTop: CGFloat = 50  // 為 safe area 留出空間

        // 標題
        titleLabel.frame = CGRect(x: 16, y: safeTop, width: 100, height: 24)

        // 關閉按鈕
        closeButton.frame = CGRect(x: width - 46, y: safeTop - 3, width: 30, height: 30)

        // 網格佈局
        let gridTop = safeTop + 40
        let gridPadding: CGFloat = 12
        gridStackView.frame = CGRect(
            x: gridPadding,
            y: gridTop,
            width: width - gridPadding * 2,
            height: containerView.bounds.height - gridTop - 40
        )
    }

    // MARK: - 公共方法

    /// 設置菜單項目
    public func setMenuItems(_ items: [SettingsMenuItem]) {
        menuItems = items
        buildMenuGrid()
    }

    /// 設置項目點擊回調
    public func setItemAction(at index: Int, action: @escaping () -> Void) {
        guard index < menuItems.count else { return }
        var item = menuItems[index]
        menuItems[index] = SettingsMenuItem(icon: item.icon, title: item.title, action: action)
    }

    /// 顯示面板
    public func show(animated: Bool = true) {
        setNeedsLayout()
        layoutIfNeeded()

        // 初始狀態（從右側外）
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

    @objc private func closeButtonTapped() {
        hide(animated: true)
    }

    @objc private func dimViewTapped() {
        hide(animated: true)
    }

    @objc private func menuItemTapped(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        let index = view.tag

        // 點擊動畫
        UIView.animate(withDuration: 0.1, animations: {
            view.alpha = 0.6
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                view.alpha = 1.0
            }
        }

        // 執行回調
        if index < menuItems.count {
            let item = menuItems[index]
            item.action?()
        }
    }
}
