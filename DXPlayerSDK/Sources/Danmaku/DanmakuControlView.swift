import UIKit

/// 弹幕控制视图
/// 整合于影片控制列中，提供弹幕开关、设定按钮、输入框
public class DanmakuControlView: UIView {

    // MARK: - UI 组件

    /// 按钮容器（包含开关和设定按钮）
    private let buttonContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.3, alpha: 0.8)
        view.layer.cornerRadius = 16
        view.clipsToBounds = true
        return view
    }()

    /// 弹幕开关按钮
    private let toggleButton: UIButton = {
        let button = UIButton(type: .custom)
        let image = UIImage.dxPlayerImage(named: "danmaku_on")?.withRenderingMode(.alwaysTemplate)
        button.setImage(image, for: .normal)
        button.tintColor = .white
        button.backgroundColor = .clear
        return button
    }()

    /// 分隔线
    private let separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        return view
    }()

    /// 弹幕设定按钮
    private let settingsButton: UIButton = {
        let button = UIButton(type: .custom)
        let image = UIImage.dxPlayerImage(named: "danmaku_settings")?.withRenderingMode(.alwaysTemplate)
        button.setImage(image, for: .normal)
        button.tintColor = .white
        button.backgroundColor = .clear
        return button
    }()

    /// 输入框
    private let inputTextField: UITextField = {
        let textField = UITextField()
        textField.textColor = .white
        textField.font = UIFont.systemFont(ofSize: 14)
        textField.backgroundColor = UIColor(white: 0, alpha: 0.6)
        textField.layer.cornerRadius = 16
        textField.returnKeyType = .send
        textField.enablesReturnKeyAutomatically = true
        textField.isHidden = true  // 默认隐藏

        // 设置 placeholder 样式
        let placeholderText = "發個彈幕吧..."
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholderText,
            attributes: [
                .foregroundColor: UIColor.white.withAlphaComponent(0.6),
                .font: UIFont.systemFont(ofSize: 14)
            ]
        )

        // 左右内距
        let leftPaddingView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 32))
        textField.leftView = leftPaddingView
        textField.leftViewMode = .always

        let rightPaddingView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 32))
        textField.rightView = rightPaddingView
        textField.rightViewMode = .always

        return textField
    }()

    /// 发送按钮
    private let sendButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setTitle("發送", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = UIColor(red: 0x00 / 255.0, green: 0x95 / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
        button.layer.cornerRadius = 18
        button.isHidden = true  // 默认隐藏
        return button
    }()

    /// 弹幕关闭状态的斜线
    private let disabledSlashLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.red.cgColor
        layer.lineWidth = 2.0
        layer.isHidden = true
        return layer
    }()

    // MARK: - 回调

    /// 弹幕开关回调
    public var onToggleEnabled: ((Bool) -> Void)?

    /// 发送弹幕回调
    public var onSendDanmaku: ((String) -> Void)?

    /// 显示设定回调
    public var onShowSettings: (() -> Void)?

    // MARK: - 属性

    /// 是否启用弹幕
    private var isEnabled: Bool = true

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

        // 添加组件
        addSubview(buttonContainer)
        buttonContainer.addSubview(toggleButton)
        buttonContainer.addSubview(separatorView)
        buttonContainer.addSubview(settingsButton)
        addSubview(inputTextField)
        addSubview(sendButton)

        // 设定约束
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        inputTextField.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // 按钮容器 - 左侧
            buttonContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            buttonContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonContainer.heightAnchor.constraint(equalToConstant: 32),

            // 弹幕开关按钮
            toggleButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            toggleButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            toggleButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
            toggleButton.widthAnchor.constraint(equalToConstant: 36),

            // 分隔线
            separatorView.leadingAnchor.constraint(equalTo: toggleButton.trailingAnchor),
            separatorView.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            separatorView.widthAnchor.constraint(equalToConstant: 1),
            separatorView.heightAnchor.constraint(equalToConstant: 16),

            // 设定按钮
            settingsButton.leadingAnchor.constraint(equalTo: separatorView.trailingAnchor),
            settingsButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            settingsButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 36),

            // 发送按钮 - 右侧固定
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 60),
            sendButton.heightAnchor.constraint(equalToConstant: 36),

            // 输入框 - 中间，buttonContainer 右侧到 sendButton 左侧
            inputTextField.leadingAnchor.constraint(equalTo: buttonContainer.trailingAnchor, constant: 8),
            inputTextField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
            inputTextField.heightAnchor.constraint(equalToConstant: 32)
        ])

        // 添加按钮事件
        toggleButton.addTarget(self, action: #selector(toggleButtonTapped), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)

        // 输入框代理
        inputTextField.delegate = self

        // 添加斜线 layer 到按钮
        toggleButton.layer.addSublayer(disabledSlashLayer)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateSlashLayerPath()
    }

    /// 更新斜线路径
    private func updateSlashLayerPath() {
        let buttonSize = toggleButton.bounds.size
        guard buttonSize.width > 0, buttonSize.height > 0 else { return }

        let padding: CGFloat = 6
        let path = UIBezierPath()
        path.move(to: CGPoint(x: padding, y: buttonSize.height - padding))
        path.addLine(to: CGPoint(x: buttonSize.width - padding, y: padding))
        disabledSlashLayer.path = path.cgPath
    }

    /// 更新斜线显示状态
    private func updateSlashVisibility() {
        disabledSlashLayer.isHidden = isEnabled
        toggleButton.tintColor = isEnabled ? .white : UIColor.white.withAlphaComponent(0.4)
    }

    // MARK: - 公共方法

    /// 设定弹幕开关状态
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        updateSlashVisibility()
    }

    /// 显示输入框（弹出键盘）
    public func showInputField() {
        inputTextField.isHidden = false
        sendButton.isHidden = false
        inputTextField.becomeFirstResponder()
    }

    /// 隐藏输入框（收起键盘）
    public func hideInputField() {
        inputTextField.resignFirstResponder()
        inputTextField.isHidden = true
        sendButton.isHidden = true
    }

    // MARK: - 事件处理

    @objc private func toggleButtonTapped() {
        isEnabled.toggle()
        updateSlashVisibility()
        onToggleEnabled?(isEnabled)

        if isEnabled {
            // 启用弹幕时显示输入框
            showInputField()
        } else {
            // 禁用弹幕时收起输入框
            hideInputField()
        }

        DXPlayerLogger.debug("👆 [弹幕控制] 弹幕开关: \(isEnabled ? "开启" : "关闭")")
    }

    @objc private func settingsButtonTapped() {
        DXPlayerLogger.debug("👆 [弹幕控制] 设定按钮点击")
        onShowSettings?()
    }

    @objc private func sendButtonTapped() {
        sendDanmaku()
    }

    private func sendDanmaku() {
        guard let text = inputTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        DXPlayerLogger.debug("👆 [弹幕控制] 发送弹幕: \(text)")

        onSendDanmaku?(text)

        // 清空输入框并收起
        inputTextField.text = nil
        hideInputField()
    }
}

// MARK: - UITextFieldDelegate

extension DanmakuControlView: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendDanmaku()
        return true
    }

    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // 限制最大长度为 100 字
        let currentText = textField.text ?? ""
        guard let stringRange = Range(range, in: currentText) else { return false }
        let updatedText = currentText.replacingCharacters(in: stringRange, with: string)
        return updatedText.count <= 100
    }
}
