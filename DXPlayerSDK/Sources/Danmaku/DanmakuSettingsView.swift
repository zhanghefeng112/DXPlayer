import UIKit

/// 彈幕設定視圖
/// 從右側滑入顯示，包含 4 個設定項目的滑桿
public class DanmakuSettingsView: UIView {

    // MARK: - 常量

    private let containerWidth: CGFloat = 280  // 改為右側滑入，使用寬度
    private var isAnimating: Bool = false

    // MARK: - UI 組件

    /// 背景遮罩
    private let dimView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.0)
        return view
    }()

    /// 容器視圖（右側滑入，毛玻璃效果）
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]  // 左側圓角
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
        label.text = "彈幕設定"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        return label
    }()

    /// 重置按鈕
    private let resetButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重置", for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        return button
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

    /// 滑桿滾動容器（橫屏時可滾動）
    private let slidersScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    /// 設定項目視圖
    private var opacitySlider: DanmakuSettingSliderView!
    private var linesSlider: DanmakuSettingSliderView!
    private var fontSizeSlider: DanmakuSettingSliderView!
    private var speedSlider: DanmakuSettingSliderView!
    private var sendModeRow: DanmakuSendModePickerView!
    private var colorPickerRow: DanmakuColorSwatchPickerView!

    // MARK: - 回調

    /// 設定變更回調
    public var onSettingsChanged: ((DanmakuSettings) -> Void)?

    // MARK: - 屬性

    /// 當前設定
    private var currentSettings: DanmakuSettings = .default

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

        // 添加標題、重置按鈕和關閉按鈕
        containerView.addSubview(titleLabel)
        containerView.addSubview(resetButton)
        containerView.addSubview(closeButton)

        // 按鈕事件
        resetButton.addTarget(self, action: #selector(resetButtonTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)

        // 創建設定項目
        setupSliders()

        // 添加滾動容器和設定項目
        containerView.addSubview(slidersScrollView)
        slidersScrollView.addSubview(opacitySlider)
        slidersScrollView.addSubview(linesSlider)
        slidersScrollView.addSubview(fontSizeSlider)
        slidersScrollView.addSubview(speedSlider)
        slidersScrollView.addSubview(sendModeRow)
        slidersScrollView.addSubview(colorPickerRow)
    }

    private func setupSliders() {
        opacitySlider = DanmakuSettingSliderView()
        opacitySlider.configure(
            title: "透明度",
            minValue: 0,
            maxValue: 100,
            currentValue: Float(currentSettings.opacity * 100),
            valueFormatter: { value in "\(Int(value))%" }
        )
        opacitySlider.onValueChanged = { [weak self] value in
            self?.currentSettings.opacity = CGFloat(value) / 100.0
            self?.notifySettingsChanged()
        }

        linesSlider = DanmakuSettingSliderView()
        linesSlider.configure(
            title: "顯示行數",
            minValue: 1,
            maxValue: 5,
            currentValue: Float(currentSettings.displayLines),
            valueFormatter: { value in "\(Int(value)) 行" }
        )
        linesSlider.onValueChanged = { [weak self] value in
            self?.currentSettings.displayLines = Int(value)
            self?.notifySettingsChanged()
        }

        fontSizeSlider = DanmakuSettingSliderView()
        fontSizeSlider.configure(
            title: "字體大小",
            minValue: 0,
            maxValue: 2,
            currentValue: Float(currentSettings.fontSize.rawValue),
            valueFormatter: { value in
                DanmakuFontSize(rawValue: Int(value))?.displayName ?? "標準"
            }
        )
        fontSizeSlider.onValueChanged = { [weak self] value in
            if let fontSize = DanmakuFontSize(rawValue: Int(value)) {
                self?.currentSettings.fontSize = fontSize
                self?.notifySettingsChanged()
            }
        }

        speedSlider = DanmakuSettingSliderView()
        speedSlider.configure(
            title: "速度",
            minValue: 0,
            maxValue: 2,
            currentValue: Float(currentSettings.speed.rawValue),
            valueFormatter: { value in
                DanmakuSpeed(rawValue: Int(value))?.displayName ?? "普通"
            }
        )
        speedSlider.onValueChanged = { [weak self] value in
            if let speed = DanmakuSpeed(rawValue: Int(value)) {
                self?.currentSettings.speed = speed
                self?.notifySettingsChanged()
            }
        }

        sendModeRow = DanmakuSendModePickerView()
        sendModeRow.setMode(currentSettings.sendMode)
        sendModeRow.onModeSelected = { [weak self] mode in
            self?.currentSettings.sendMode = mode
            self?.notifySettingsChanged()
        }

        colorPickerRow = DanmakuColorSwatchPickerView()
        colorPickerRow.setColor(currentSettings.sendColor)
        colorPickerRow.onColorSelected = { [weak self] color in
            self?.currentSettings.sendColor = color
            self?.notifySettingsChanged()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        // 動畫進行中不更新 frame
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
        titleLabel.frame = CGRect(x: 16, y: safeTop, width: 100, height: 24)

        // 重置按鈕（標題右側）
        resetButton.frame = CGRect(x: width - 100, y: safeTop, width: 50, height: 24)

        // 關閉按鈕
        closeButton.frame = CGRect(x: width - 46, y: safeTop - 3, width: 30, height: 30)

        // 滾動容器（標題下方到底部）
        let scrollTop = safeTop + 44
        let scrollHeight = height - scrollTop - max(safeAreaInsets.bottom, 10)
        slidersScrollView.frame = CGRect(x: 0, y: scrollTop, width: width, height: scrollHeight)

        // 滑桿佈局（在滾動容器內）
        let sliderX: CGFloat = 16
        let sliderWidth = width - 32
        let sliderHeight: CGFloat = 70
        var sliderY: CGFloat = 0

        opacitySlider.frame = CGRect(x: sliderX, y: sliderY, width: sliderWidth, height: sliderHeight)
        sliderY += sliderHeight + 8

        linesSlider.frame = CGRect(x: sliderX, y: sliderY, width: sliderWidth, height: sliderHeight)
        sliderY += sliderHeight + 8

        fontSizeSlider.frame = CGRect(x: sliderX, y: sliderY, width: sliderWidth, height: sliderHeight)
        sliderY += sliderHeight + 8

        speedSlider.frame = CGRect(x: sliderX, y: sliderY, width: sliderWidth, height: sliderHeight)
        sliderY += sliderHeight + 16

        sendModeRow.frame = CGRect(x: sliderX, y: sliderY, width: sliderWidth, height: 72)
        sliderY += 72 + 16

        colorPickerRow.frame = CGRect(x: sliderX, y: sliderY, width: sliderWidth, height: 72)
        sliderY += 72

        // 設置滾動內容大小
        slidersScrollView.contentSize = CGSize(width: sliderWidth, height: sliderY + 16)
    }

    // MARK: - 公共方法

    /// 載入設定
    public func loadSettings(_ settings: DanmakuSettings) {
        currentSettings = settings

        opacitySlider.setValue(Float(settings.opacity * 100))
        linesSlider.setValue(Float(settings.displayLines))
        fontSizeSlider.setValue(Float(settings.fontSize.rawValue))
        speedSlider.setValue(Float(settings.speed.rawValue))
        sendModeRow.setMode(settings.sendMode)
        colorPickerRow.setColor(settings.sendColor)
    }

    /// 顯示面板（從右側滑入）
    public func show(animated: Bool = true) {
        // 强制先完成布局
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

    /// 隱藏面板（向右側滑出）
    public func hide(animated: Bool = true) {
        if animated {
            isAnimating = true
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn, animations: {
                self.dimView.alpha = 0
                self.containerView.transform = CGAffineTransform(translationX: self.containerWidth, y: 0)
            }, completion: { _ in
                self.isAnimating = false
                self.removeFromSuperview()
            })
        } else {
            removeFromSuperview()
        }
    }

    // MARK: - 事件處理

    @objc private func closeButtonTapped() {
        hide(animated: true)
    }

    @objc private func dimViewTapped() {
        hide(animated: true)
    }

    @objc private func resetButtonTapped() {
        // 重置為默認設定（sendMode/sendColor 也一併重置）
        loadSettings(.default)
        notifySettingsChanged()
    }

    private func notifySettingsChanged() {
        onSettingsChanged?(currentSettings)
    }
}

// MARK: - DanmakuSettingSliderView

/// 設定項目滑桿視圖
class DanmakuSettingSliderView: UIView {

    // MARK: - UI 組件

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        return label
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor(white: 1, alpha: 0.7)
        label.font = UIFont.systemFont(ofSize: 14)
        label.textAlignment = .right
        return label
    }()

    private let slider: UISlider = {
        let slider = UISlider()
        slider.minimumTrackTintColor = UIColor.systemBlue
        slider.maximumTrackTintColor = UIColor(white: 1, alpha: 0.3)
        slider.thumbTintColor = .white
        return slider
    }()

    // MARK: - 屬性

    private var valueFormatter: ((Float) -> String)?
    var onValueChanged: ((Float) -> Void)?

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
        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(slider)

        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = bounds.width
        titleLabel.frame = CGRect(x: 0, y: 0, width: width * 0.6, height: 20)
        valueLabel.frame = CGRect(x: width * 0.6, y: 0, width: width * 0.4, height: 20)
        // 給滑桿足夠的空間，確保 thumb 不會被截斷
        slider.frame = CGRect(x: 0, y: 25, width: width, height: 35)
    }

    // 擴大 touch 響應區域
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expandedBounds = bounds.insetBy(dx: 0, dy: -10)
        return expandedBounds.contains(point)
    }

    // MARK: - 公共方法

    func configure(title: String, minValue: Float, maxValue: Float, currentValue: Float, valueFormatter: @escaping (Float) -> String) {
        titleLabel.text = title
        slider.minimumValue = minValue
        slider.maximumValue = maxValue
        slider.value = currentValue
        self.valueFormatter = valueFormatter
        valueLabel.text = valueFormatter(currentValue)
    }

    func setValue(_ value: Float) {
        slider.value = value
        valueLabel.text = valueFormatter?(value) ?? "\(value)"
    }

    // MARK: - 事件處理

    @objc private func sliderValueChanged() {
        // 對於離散值滑桿（如字體大小、速度），四捨五入到最近的整數
        let rawValue = slider.value
        let roundedValue = roundf(rawValue)

        // 更新顯示使用四捨五入後的值
        valueLabel.text = valueFormatter?(roundedValue) ?? "\(roundedValue)"
        onValueChanged?(roundedValue)
    }
}

// MARK: - DanmakuSendModePickerView

/// 發送模式選擇器（4 個按鈕橫排）
class DanmakuSendModePickerView: UIView {

    // MARK: - 數據

    private let modes: [(DanmakuMode, String)] = [
        (.scroll,  "滾動"),
        (.top,     "頂部"),
        (.bottom,  "底部"),
        (.reverse, "反向")
    ]

    private var selectedMode: DanmakuMode = .scroll
    var onModeSelected: ((DanmakuMode) -> Void)?

    // MARK: - UI

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "發送模式"
        l.textColor = .white
        l.font = .systemFont(ofSize: 16, weight: .medium)
        return l
    }()

    private let buttonStack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 6
        s.alignment = .fill
        s.distribution = .fillEqually
        return s
    }()

    private var modeButtons: [UIButton] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(titleLabel)
        addSubview(buttonStack)

        for (index, (_, label)) in modes.enumerated() {
            let btn = UIButton(type: .custom)
            btn.setTitle(label, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            btn.layer.cornerRadius = 6
            btn.tag = index
            btn.addTarget(self, action: #selector(modeTapped(_:)), for: .touchUpInside)
            buttonStack.addArrangedSubview(btn)
            modeButtons.append(btn)
        }
        updateButtonStyles()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        titleLabel.frame = CGRect(x: 0, y: 0, width: w, height: 20)
        buttonStack.frame = CGRect(x: 0, y: 28, width: w, height: 36)
    }

    // MARK: - 公共方法

    func setMode(_ mode: DanmakuMode) {
        selectedMode = mode
        updateButtonStyles()
    }

    // MARK: - 私有

    private func updateButtonStyles() {
        for (index, (mode, _)) in modes.enumerated() {
            let btn = modeButtons[index]
            let isSelected = mode == selectedMode
            btn.backgroundColor = isSelected
                ? UIColor.systemBlue
                : UIColor.white.withAlphaComponent(0.15)
            btn.setTitleColor(isSelected ? .white : UIColor.white.withAlphaComponent(0.8), for: .normal)
            btn.layer.borderWidth = isSelected ? 0 : 0.5
            btn.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        }
    }

    @objc private func modeTapped(_ sender: UIButton) {
        let (mode, _) = modes[sender.tag]
        selectedMode = mode
        updateButtonStyles()
        onModeSelected?(mode)
    }
}

// MARK: - DanmakuColorSwatchPickerView

/// 發送顏色色塊選擇器（橫排色塊）
class DanmakuColorSwatchPickerView: UIView {

    // MARK: - 數據

    /// nil = 服務端默認（顯示為白色+虛線邊框）
    private let presets: [(String?, UIColor)] = [
        (nil,        UIColor(white: 1, alpha: 0.9)),  // 默認
        ("#4FC3F7",  UIColor(red: 0.31, green: 0.76, blue: 0.97, alpha: 1)),  // 藍
        ("#66BB6A",  UIColor(red: 0.40, green: 0.73, blue: 0.41, alpha: 1)),  // 綠
        ("#AB47BC",  UIColor(red: 0.67, green: 0.28, blue: 0.74, alpha: 1)),  // 紫
        ("#EC407A",  UIColor(red: 0.93, green: 0.25, blue: 0.48, alpha: 1)),  // 粉
        ("#F9C74F",  UIColor(red: 0.98, green: 0.78, blue: 0.31, alpha: 1)),  // 黃
    ]

    private var selectedHex: String? = nil
    var onColorSelected: ((String?) -> Void)?

    // MARK: - UI

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "发送弹幕颜色"
        l.textColor = .white
        l.font = .systemFont(ofSize: 16, weight: .medium)
        return l
    }()

    private let defaultLabel: UILabel = {
        let l = UILabel()
        l.text = "默認"
        l.textColor = UIColor.white.withAlphaComponent(0.5)
        l.font = .systemFont(ofSize: 10)
        l.textAlignment = .center
        return l
    }()

    private var swatchViews: [UIView] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        addSubview(titleLabel)

        for (index, (hex, color)) in presets.enumerated() {
            let container = UIView()
            container.tag = index

            let swatch = UIView()
            swatch.backgroundColor = color
            swatch.layer.cornerRadius = 14
            swatch.layer.masksToBounds = false
            swatch.tag = 100

            container.addSubview(swatch)

            // 第一個（默認）加「默」標籤
            if hex == nil {
                let lbl = UILabel()
                lbl.text = "白"
                lbl.textColor = UIColor(white: 0.3, alpha: 1)
                lbl.font = .systemFont(ofSize: 11, weight: .bold)
                lbl.textAlignment = .center
                lbl.tag = 200
                swatch.addSubview(lbl)
            }

            let tap = UITapGestureRecognizer(target: self, action: #selector(swatchTapped(_:)))
            container.addGestureRecognizer(tap)
            container.isUserInteractionEnabled = true
            addSubview(container)
            swatchViews.append(container)
        }
        updateSwatchStyles()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        titleLabel.frame = CGRect(x: 0, y: 0, width: w, height: 20)

        let swatchSize: CGFloat = 28
        let totalSwatches = presets.count
        let spacing = (w - CGFloat(totalSwatches) * swatchSize) / CGFloat(totalSwatches - 1)
        let swatchY: CGFloat = 28 + (36 - swatchSize) / 2

        for (i, container) in swatchViews.enumerated() {
            let x = CGFloat(i) * (swatchSize + spacing)
            container.frame = CGRect(x: x, y: swatchY, width: swatchSize, height: swatchSize)
            if let swatch = container.viewWithTag(100) {
                swatch.frame = container.bounds
                swatch.layer.cornerRadius = swatchSize / 2
                if let lbl = swatch.viewWithTag(200) {
                    lbl.frame = swatch.bounds
                }
            }
        }
    }

    // MARK: - 公共方法

    func setColor(_ hex: String?) {
        selectedHex = hex
        updateSwatchStyles()
    }

    // MARK: - 私有

    private func updateSwatchStyles() {
        for (index, (hex, _)) in presets.enumerated() {
            guard let container = swatchViews[safe: index],
                  let swatch = container.viewWithTag(100) else { continue }
            let isSelected = hex == selectedHex
            swatch.layer.borderWidth = isSelected ? 3 : 1
            swatch.layer.borderColor = isSelected
                ? UIColor.systemBlue.cgColor
                : UIColor.white.withAlphaComponent(0.3).cgColor
            // 選中時縮小一點，未選中正常大小
            swatch.transform = isSelected
                ? CGAffineTransform(scaleX: 1.15, y: 1.15)
                : .identity
        }
    }

    @objc private func swatchTapped(_ gesture: UITapGestureRecognizer) {
        guard let container = gesture.view else { return }
        let index = container.tag
        let (hex, _) = presets[index]
        selectedHex = hex
        updateSwatchStyles()
        onColorSelected?(hex)
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
