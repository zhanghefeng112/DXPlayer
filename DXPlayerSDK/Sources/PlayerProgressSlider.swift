import UIKit
import FSPlayer

/// 自定义视频进度条
/// 支持显示播放进度、缓冲进度、拖动控制
class PlayerProgressSlider: UIControl {

    // MARK: - 公共属性

    /// 当前播放进度（0.0 - 1.0）
    var progress: Float = 0.0 {
        didSet {
            // 如果正在拖动，忽略外部的进度更新
            // 避免拖动时被自動更新覆蓋
            guard !isDragging else { return }
            updateLayerFrames()
        }
    }

    /// 缓冲进度（0.0 - 1.0）
    var bufferProgress: Float = 0.0 {
        didSet {
            updateLayerFrames()
        }
    }

    /// 轨道颜色（設計稿：白色半透明）
    var trackTintColor: UIColor = UIColor.white.withAlphaComponent(0.3) {
        didSet {
            trackLayer.backgroundColor = trackTintColor.cgColor
        }
    }

    /// 播放进度颜色
    var progressTintColor: UIColor = .systemRed {
        didSet {
            progressLayer.backgroundColor = progressTintColor.cgColor
        }
    }

    /// 缓冲进度颜色
    var bufferTintColor: UIColor = UIColor.white.withAlphaComponent(0.3) {
        didSet {
            bufferLayer.backgroundColor = bufferTintColor.cgColor
        }
    }

    /// 滑块颜色
    var thumbTintColor: UIColor = .white {
        didSet {
            thumbView.backgroundColor = thumbTintColor
        }
    }

    /// 滑块大小
    var thumbSize: CGSize = CGSize(width: 16, height: 16) {
        didSet {
            updateLayerFrames()
        }
    }

    /// 轨道高度
    var trackHeight: CGFloat = 3.0 {
        didSet {
            setNeedsLayout()
        }
    }

    /// 视频总时长（秒），用于计算预览时间
    var duration: TimeInterval = 0

    /// 缩略图管理器（弱引用，由外部管理）
    weak var thumbnailManager: ThumbnailPreviewManager?

    // MARK: - 私有属性

    private let trackLayer = CALayer()
    private let bufferLayer = CALayer()
    private let progressLayer = CALayer()
    private let thumbView = UIView()

    // 缩略图预览视图
    private let thumbnailPreviewView = ThumbnailPreviewView()

    // 浮動时间提示标籤
    private let timeTooltipLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.isHidden = true
        label.alpha = 0
        return label
    }()

    private var isDragging = false

    // 请求节流：记录上次请求时间和时间戳
    private var lastThumbnailRequestTime: TimeInterval = 0
    private var lastRequestedTimestamp: TimeInterval = -1
    private let thumbnailRequestThrottle: TimeInterval = 0.1  // 最小请求间隔（秒）

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    // MARK: - 设置

    private func setupLayers() {
        // 背景轨道
        trackLayer.backgroundColor = trackTintColor.cgColor
        trackLayer.cornerRadius = trackHeight / 2
        layer.addSublayer(trackLayer)

        // 缓冲进度
        bufferLayer.backgroundColor = bufferTintColor.cgColor
        bufferLayer.cornerRadius = trackHeight / 2
        layer.addSublayer(bufferLayer)

        // 播放进度
        progressLayer.backgroundColor = progressTintColor.cgColor
        progressLayer.cornerRadius = trackHeight / 2
        layer.addSublayer(progressLayer)

        // 滑块
        thumbView.backgroundColor = thumbTintColor
        thumbView.layer.cornerRadius = thumbSize.width / 2
        thumbView.layer.shadowColor = UIColor.black.cgColor
        thumbView.layer.shadowOffset = CGSize(width: 0, height: 2)
        thumbView.layer.shadowRadius = 3
        thumbView.layer.shadowOpacity = 0.3
        thumbView.clipsToBounds = false  // 允许阴影显示
        thumbView.isUserInteractionEnabled = false  // 禁用交互，讓触摸穿透到父控件
        addSubview(thumbView)

        // 时间提示标籤
        timeTooltipLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeTooltipLabel)
    }

    // MARK: - 布局

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayerFrames()
    }

    private func updateLayerFrames() {
        // 禁用隐式動画，确保拖动时即时更新
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let trackY = (bounds.height - trackHeight) / 2
        let trackWidth = bounds.width

        // 轨道层
        trackLayer.frame = CGRect(
            x: 0,
            y: trackY,
            width: trackWidth,
            height: trackHeight
        )

        // 缓冲层
        let bufferWidth = trackWidth * CGFloat(bufferProgress)
        bufferLayer.frame = CGRect(
            x: 0,
            y: trackY,
            width: bufferWidth,
            height: trackHeight
        )

        // 进度层
        let progressWidth = trackWidth * CGFloat(progress)
        progressLayer.frame = CGRect(
            x: 0,
            y: trackY,
            width: progressWidth,
            height: trackHeight
        )

        // 滑块（clamp 避免超出两端）
        let thumbX = min(max(progressWidth - thumbSize.width / 2, 0), bounds.width - thumbSize.width)
        let thumbY = (bounds.height - thumbSize.height) / 2
        thumbView.frame = CGRect(
            x: thumbX,
            y: thumbY,
            width: thumbSize.width,
            height: thumbSize.height
        )
        thumbView.layer.cornerRadius = thumbSize.width / 2

        CATransaction.commit()
    }

    // MARK: - 公共方法

    /// 更新进度
    /// - Parameters:
    ///   - progress: 播放进度（0.0 - 1.0）
    ///   - buffer: 缓冲进度（0.0 - 1.0）
    func updateProgress(_ progress: Float, buffer: Float) {
        self.progress = max(0, min(progress, 1.0))
        self.bufferProgress = max(0, min(buffer, 1.0))
    }

    /// 更新时间提示标籤的文字
    /// - Parameter text: 要显示的时间文字（例如："01:23"）
    func updateTooltipText(_ text: String) {
        timeTooltipLabel.text = text
        // 根据文字內容调整标籤寬度
        timeTooltipLabel.sizeToFit()
        // 增加左右內邊距
        let padding: CGFloat = 8
        timeTooltipLabel.frame.size.width += padding * 2
        timeTooltipLabel.frame.size.height = 24
    }

    // MARK: - 私有方法（工具提示）

    /// 显示时间提示标籤
    /// - Parameter xPosition: 提示标籤的 x 軸位置
    private func showTooltip(at xPosition: CGFloat) {
        // 设置位置（在进度条上方）
        let tooltipY = (bounds.height - trackHeight) / 2 - timeTooltipLabel.frame.height - 8
        var tooltipX = xPosition - timeTooltipLabel.frame.width / 2

        // 确保提示标籤不超出邊界
        let minX: CGFloat = 0
        let maxX = bounds.width - timeTooltipLabel.frame.width
        tooltipX = max(minX, min(tooltipX, maxX))

        timeTooltipLabel.frame.origin = CGPoint(x: tooltipX, y: tooltipY)

        // 显示動画
        if timeTooltipLabel.isHidden {
            timeTooltipLabel.isHidden = false
            UIView.animate(withDuration: 0.15) {
                self.timeTooltipLabel.alpha = 1.0
            }
        }
    }

    /// 隐藏时间提示标籤
    private func hideTooltip() {
        UIView.animate(withDuration: 0.15, animations: {
            self.timeTooltipLabel.alpha = 0.0
        }) { _ in
            self.timeTooltipLabel.isHidden = true
        }
    }

    // MARK: - 触摸处理

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isDragging = true

        // 重置请求节流状态，确保第一次请求立即执行
        lastThumbnailRequestTime = 0
        lastRequestedTimestamp = -1

        // 發送 touchDown 事件
        sendActions(for: .touchDown)

        // 放大滑块（视觉反馈）
        UIView.animate(withDuration: 0.15) {
            self.thumbView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }

        // 更新进度
        updateProgressForTouch(touch)

        // 显示缩略图预览
        showThumbnailPreview(for: touch)

        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateProgressForTouch(touch)

        // 更新缩略图预览
        showThumbnailPreview(for: touch)

        // 在拖动过程中也發送 valueChanged 事件，讓时间标籤即时更新
        sendActions(for: .valueChanged)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        isDragging = false

        // 恢复滑块大小
        UIView.animate(withDuration: 0.15) {
            self.thumbView.transform = .identity
        }

        // 隐藏缩略图预览
        hideThumbnailPreview()

        // 检查触摸点是否在控件范围內
        if let touch = touch {
            let location = touch.location(in: self)
            if bounds.contains(location) {
                sendActions(for: .touchUpInside)
            } else {
                sendActions(for: .touchUpOutside)
            }
        } else {
            sendActions(for: .touchUpInside)
        }

        // 发送值变化事件
        sendActions(for: .valueChanged)
    }

    override func cancelTracking(with event: UIEvent?) {
        isDragging = false

        // 恢复滑块大小
        UIView.animate(withDuration: 0.15) {
            self.thumbView.transform = .identity
        }

        // 隐藏缩略图预览
        hideThumbnailPreview()
    }

    private func updateProgressForTouch(_ touch: UITouch) {
        let location = touch.location(in: self)
        let newProgress = Float(location.x / bounds.width)
        progress = max(0, min(newProgress, 1.0))

        // 由于拖动时 progress 的 didSet 会被忽略，需要手動更新UI
        updateLayerFrames()

        // 发送触摸拖动事件
        sendActions(for: .touchDragInside)
    }

    // MARK: - 触摸区域扩展

    /// 扩展触摸区域，让进度条更容易点击
    /// 只向下扩展，向上不扩展（上方是控制列，避免冲突）
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expandedBounds = CGRect(
            x: bounds.origin.x - 10,
            y: bounds.origin.y - 5,     // 向上只扩展 5pt
            width: bounds.width + 20,
            height: bounds.height + 25   // 向下扩展 20pt
        )
        return expandedBounds.contains(point)
    }

    // MARK: - 缩略图预览

    /// 显示缩略图预览
    /// - Parameter touch: 触摸点
    private func showThumbnailPreview(for touch: UITouch) {
        // 只有当片源支持微缩图且已加载时才显示预览
        guard let manager = thumbnailManager, manager.isAvailable, duration > 0 else {
            return
        }

        let location = touch.location(in: self)
        let currentProgress = location.x / bounds.width
        let time = TimeInterval(currentProgress) * duration

        // 获取合适的父视图（向上查找不会裁剪子视图的容器）
        // 优先使用 IJKPlayerContainerView 或 PlayerControlView，避免被 progressRowView 裁剪
        guard let parentView = findSuitableParentView() else {
            return
        }

        // 计算预览窗口在父视图中的位置
        let locationInParent = convert(location, to: parentView)
        let xInParent = locationInParent.x

        // 计算进度条在父视图中的 y 坐标
        let sliderTopInParent = convert(bounds.origin, to: parentView).y

        // 关键优化：请求节流
        // 检查是否需要发起新的缩略图请求
        let now = Date().timeIntervalSince1970
        let shouldRequestNewThumbnail = (now - lastThumbnailRequestTime) >= thumbnailRequestThrottle &&
                                       abs(time - lastRequestedTimestamp) >= 0.5

        if shouldRequestNewThumbnail {
            // 更新请求时间戳
            lastThumbnailRequestTime = now
            lastRequestedTimestamp = time

            // 如果窗口还没显示，先显示窗口（首次显示需要处理 nil 状态）
            if !thumbnailPreviewView.isShowing {
                self.thumbnailPreviewView.setImage(nil, time: time)
                self.thumbnailPreviewView.show(at: xInParent, aboveY: sliderTopInParent, in: parentView, animated: false)
            } else {
                // 窗口已显示，只更新时间标签，保持当前图片（避免闪烁）
                self.thumbnailPreviewView.updateTimeLabel(time: time)
            }

            // 获取缩略图
            manager.getThumbnail(at: time) { [weak self] image in
                guard let self = self else { return }

                // 更新图片（保持窗口显示）
                DispatchQueue.main.async {
                    if let image = image {
                        // 只有成功获取图片时才更新，避免闪烁
                        self.thumbnailPreviewView.setImage(image, time: time)
                    }
                }
            }
        } else {
            // 不发起新请求，只更新预览窗口位置
            // 如果窗口正在显示，更新其位置
            if thumbnailPreviewView.isShowing {
                thumbnailPreviewView.updatePosition(xInParent, aboveY: sliderTopInParent, in: parentView)
            }
        }
    }

    /// 隐藏缩略图预览
    private func hideThumbnailPreview() {
        thumbnailPreviewView.hide(animated: true)
    }

    /// 查找合适的父视图（向上查找不会裁剪子视图的容器）
    /// 视图层级：progressSlider -> progressRowView -> bottomContainerView -> PlayerControlView -> IJKPlayerContainerView
    /// progressRowView 高度只有 30pt，预览窗口会被裁剪，所以需要找更上层的视图
    private func findSuitableParentView() -> UIView? {
        var view: UIView? = superview

        // 向上查找，找到 PlayerControlView 或 IJKPlayerContainerView
        // 这两个视图都足够大，不会裁剪预览窗口
        while let currentView = view {
            let typeName = String(describing: type(of: currentView))
            if typeName == "PlayerControlView" || typeName.contains("IJKPlayerContainerView") {
                return currentView
            }
            view = currentView.superview
        }

        // 如果找不到，退回到 window
        return window
    }
}
