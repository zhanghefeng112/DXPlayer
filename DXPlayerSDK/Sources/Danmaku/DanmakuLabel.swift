import UIKit

/// 彈幕視圖
class DanmakuLabel: UILabel {

    // MARK: - 屬性

    /// 彈幕資料
    var danmakuItem: DanmakuItem?

    /// 所屬軌道索引
    var trackIndex: Int = 0

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
        // 文字樣式
        textAlignment = .natural
        numberOfLines = 1
        lineBreakMode = .byClipping

        // 描邊效果（增強可讀性）
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 1, height: 1)
        layer.shadowRadius = 2
        layer.shadowOpacity = 0.8

        // 背景透明
        backgroundColor = .clear
    }

    // MARK: - 配置

    /// 配置彈幕視圖
    func configure(danmaku: DanmakuItem, fontSize: CGFloat, opacity: CGFloat) {
        self.danmakuItem = danmaku

        // 設定文字
        self.text = danmaku.text

        // 設定字體
        let finalFontSize = danmaku.fontSize ?? fontSize
        self.font = UIFont.systemFont(ofSize: finalFontSize, weight: .medium)

        // 設定顏色（不再在這裡設定透明度）
        self.textColor = danmaku.color

        // 設定整個視圖的透明度，這樣可以同時影響文字和表情符號
        self.alpha = opacity

        // 計算尺寸
        sizeToFit()

        // 添加內距
        let padding: CGFloat = 8
        self.frame.size.width += padding * 2
    }

    /// 重置視圖狀態（用於複用）
    func reset() {
        danmakuItem = nil
        trackIndex = 0
        text = nil
        alpha = 1.0  // 重置透明度
        textColor = .white  // 重置顏色
        layer.removeAllAnimations()
        removeFromSuperview()
    }
}
