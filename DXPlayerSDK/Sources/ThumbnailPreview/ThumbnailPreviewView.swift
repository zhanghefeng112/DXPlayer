import UIKit

/// 缩略图预览悬浮窗口
/// 显示视频缩略图和时间标签
class ThumbnailPreviewView: UIView {

    // MARK: - UI Components

    /// 容器视图（包含阴影和圆角）
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.1, alpha: 0.95)
        view.layer.cornerRadius = 8
        view.layer.masksToBounds = false

        // 阴影
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 8
        view.layer.shadowOpacity = 0.3

        return view
    }()

    /// 缩略图视图
    private let thumbnailImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 6
        imageView.layer.masksToBounds = true
        imageView.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        return imageView
    }()

    /// 时间标签
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor(white: 0, alpha: 0.7)
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        return label
    }()

    /// 加载指示器（图片加载中显示）
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator: UIActivityIndicatorView
        if #available(iOS 13.0, *) {
            indicator = UIActivityIndicatorView(style: .medium)
        } else {
            indicator = UIActivityIndicatorView(style: .white)
        }
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Properties

    /// 预览窗口尺寸（16:9 比例）
    private let previewSize = CGSize(width: 160, height: 90)

    /// 内边距
    private let padding: CGFloat = 8

    /// 时间标签高度
    private let timeLabelHeight: CGFloat = 24

    /// 当前是否正在显示
    private(set) var isShowing = false

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        // 初始隐藏
        alpha = 0
        isHidden = true
        isShowing = false

        // 添加子视图
        addSubview(containerView)
        containerView.addSubview(thumbnailImageView)
        containerView.addSubview(timeLabel)
        containerView.addSubview(loadingIndicator)

        // 布局约束
        setupConstraints()
    }

    private func setupConstraints() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        let totalHeight = previewSize.height + timeLabelHeight + padding * 3

        NSLayoutConstraint.activate([
            // Container View
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.widthAnchor.constraint(equalToConstant: previewSize.width + padding * 2),
            containerView.heightAnchor.constraint(equalToConstant: totalHeight),

            // Thumbnail Image View
            thumbnailImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding),
            thumbnailImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding),
            thumbnailImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padding),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: previewSize.height),

            // Time Label
            timeLabel.topAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor, constant: padding),
            timeLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding),
            timeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -padding),
            timeLabel.heightAnchor.constraint(equalToConstant: timeLabelHeight),

            // Loading Indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: thumbnailImageView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: thumbnailImageView.centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        DXPlayerLogger.debug("🖼️ [预览窗口] layoutSubviews - frame: \(frame)")
        DXPlayerLogger.debug("🖼️ [预览窗口] layoutSubviews - containerView.frame: \(containerView.frame)")
    }

    // MARK: - Public Methods

    /// 设置缩略图和时间
    /// - Parameters:
    ///   - image: 缩略图（nil 表示加载中）
    ///   - time: 时间戳
    func setImage(_ image: UIImage?, time: TimeInterval) {
        // 禁用隐式动画，避免图片切换时闪烁
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if let image = image {
            // 有图片，停止加载指示器
            loadingIndicator.stopAnimating()
            thumbnailImageView.image = image
        } else {
            // 无图片，显示加载指示器
            thumbnailImageView.image = nil
            loadingIndicator.startAnimating()
        }

        CATransaction.commit()

        // 更新时间标签
        timeLabel.text = formatTime(time)
    }

    /// 只更新时间标签（不影响图片显示，避免闪烁）
    /// - Parameter time: 时间戳
    func updateTimeLabel(time: TimeInterval) {
        timeLabel.text = formatTime(time)
    }

    /// 显示预览窗口
    /// - Parameters:
    ///   - position: 在父视图中的 x 坐标
    ///   - aboveY: 预览窗口应该显示在此 Y 坐标之上（通常是进度条的顶部）
    ///   - parentView: 父视图
    ///   - animated: 是否动画显示
    func show(at position: CGFloat, aboveY: CGFloat, in parentView: UIView, animated: Bool = true) {
        DXPlayerLogger.debug("🖼️ [预览窗口] show() 被调用 - position: \(position), aboveY: \(aboveY), parentView: \(type(of: parentView))")
        DXPlayerLogger.debug("🖼️ [预览窗口] 当前状态 - isShowing: \(isShowing), isHidden: \(isHidden), alpha: \(alpha)")

        // 添加到父视图（如果还没有）
        if superview != parentView {
            DXPlayerLogger.debug("🖼️ [预览窗口] 添加到父视图: \(type(of: parentView))")
            parentView.addSubview(self)
        } else {
            DXPlayerLogger.debug("🖼️ [预览窗口] 已在父视图中")
        }

        // 更新位置
        updatePosition(position, aboveY: aboveY, in: parentView)
        DXPlayerLogger.debug("🖼️ [预览窗口] 位置更新完成 - frame: \(frame)")

        // 立即应用约束布局
        layoutIfNeeded()
        DXPlayerLogger.debug("🖼️ [预览窗口] 布局完成 - containerView.frame: \(containerView.frame)")

        // 如果之前没有显示，才需要淡入动画
        if !isShowing {
            isShowing = true
            isHidden = false

            // 动画显示
            if animated {
                UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut) {
                    self.alpha = 1.0
                }
            } else {
                alpha = 1.0
            }
        }

        DXPlayerLogger.debug("🖼️ [预览窗口] show() 完成")
    }

    /// 隐藏预览窗口
    /// - Parameter animated: 是否动画隐藏
    func hide(animated: Bool = true) {
        isShowing = false

        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
                self.alpha = 0
            }, completion: { _ in
                self.isHidden = true
                self.thumbnailImageView.image = nil
                self.loadingIndicator.stopAnimating()
            })
        } else {
            alpha = 0
            isHidden = true
            thumbnailImageView.image = nil
            loadingIndicator.stopAnimating()
        }
    }

    /// 更新位置（跟随手指移动）
    /// - Parameters:
    ///   - position: x 坐标
    ///   - aboveY: 预览窗口应该显示在此 Y 坐标之上
    ///   - parentView: 父视图
    func updatePosition(_ position: CGFloat, aboveY: CGFloat, in parentView: UIView) {
        // 使用预定义的尺寸，而不是 bounds（因为 Auto Layout 约束可能还未生效）
        let totalHeight = previewSize.height + timeLabelHeight + padding * 3
        let viewWidth = previewSize.width + padding * 2
        let viewHeight = totalHeight

        DXPlayerLogger.debug("🖼️ [预览窗口] updatePosition - 计算尺寸: width=\(viewWidth), height=\(viewHeight)")

        // 计算 x 坐标（居中对齐手指位置）
        var x = position - viewWidth / 2

        // 边界检测（避免超出屏幕）
        let margin: CGFloat = 8
        let minX = margin
        let maxX = parentView.bounds.width - viewWidth - margin

        x = max(minX, min(maxX, x))

        // y 坐标（在指定位置上方，预留 10pt 间距）
        let spacing: CGFloat = 10
        let y = aboveY - viewHeight - spacing

        DXPlayerLogger.debug("🖼️ [预览窗口] updatePosition - 最终位置: x=\(x), y=\(y), aboveY=\(aboveY)")

        // 更新 frame
        frame = CGRect(x: x, y: y, width: viewWidth, height: viewHeight)
    }

    // MARK: - Private Methods

    /// 格式化时间
    /// - Parameter time: 时间戳（秒）
    /// - Returns: 格式化的时间字符串（mm:ss 或 HH:mm:ss）
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
