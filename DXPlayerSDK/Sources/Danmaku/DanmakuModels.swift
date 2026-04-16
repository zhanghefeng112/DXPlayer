import Foundation
import UIKit

// MARK: - DanmakuItem

/// 彈幕資料項目
public struct DanmakuItem {
    /// 彈幕唯一 ID
    public let id: String

    /// 彈幕文字內容
    public let text: String

    /// 發送者 ID（可選）
    public let userId: String?

    /// 發送者暱稱（可選）
    public let userName: String?

    /// 彈幕顏色（可選，預設白色）
    public let color: UIColor

    /// 字體大小（可選，使用全局設定）
    public let fontSize: CGFloat?

    /// 時間戳（僅時間軸模式使用）
    /// 表示該彈幕應該在影片的哪個時間點顯示（秒）
    public let timestamp: TimeInterval?

    /// 接收時間（即時模式使用）
    public let receivedAt: Date

    /// 是否為自己發送的彈幕
    public let isSelf: Bool

    /// 初始化
    public init(
        id: String = UUID().uuidString,
        text: String,
        userId: String? = nil,
        userName: String? = nil,
        color: UIColor = .white,
        fontSize: CGFloat? = nil,
        timestamp: TimeInterval? = nil,
        receivedAt: Date = Date(),
        isSelf: Bool = false
    ) {
        self.id = id
        self.text = text
        self.userId = userId
        self.userName = userName
        self.color = color
        self.fontSize = fontSize
        self.timestamp = timestamp
        self.receivedAt = receivedAt
        self.isSelf = isSelf
    }
}

// MARK: - DanmakuSettings

/// 彈幕設定
public struct DanmakuSettings {
    /// 透明度（0.0 - 1.0）
    public var opacity: CGFloat

    /// 顯示行數（1 - 5）
    public var displayLines: Int

    /// 字體大小
    public var fontSize: DanmakuFontSize

    /// 滾動速度
    public var speed: DanmakuSpeed

    /// 是否啟用彈幕
    public var isEnabled: Bool

    /// 預設值
    public static var `default`: DanmakuSettings {
        return DanmakuSettings(
            opacity: 1.0,
            displayLines: 3,
            fontSize: .standard,
            speed: .normal,
            isEnabled: true
        )
    }

    /// 初始化
    public init(
        opacity: CGFloat = 1.0,
        displayLines: Int = 3,
        fontSize: DanmakuFontSize = .standard,
        speed: DanmakuSpeed = .normal,
        isEnabled: Bool = true
    ) {
        self.opacity = max(0.0, min(1.0, opacity))
        self.displayLines = max(1, min(5, displayLines))
        self.fontSize = fontSize
        self.speed = speed
        self.isEnabled = isEnabled
    }
}

// MARK: - DanmakuFontSize

/// 字體大小
public enum DanmakuFontSize: Int, CaseIterable {
    case small = 0      // 12pt
    case standard = 1   // 16pt
    case large = 2      // 20pt

    public var points: CGFloat {
        switch self {
        case .small: return 12.0
        case .standard: return 16.0
        case .large: return 20.0
        }
    }

    public var displayName: String {
        switch self {
        case .small: return "小"
        case .standard: return "標準"
        case .large: return "大"
        }
    }
}

// MARK: - DanmakuSpeed

/// 滾動速度
public enum DanmakuSpeed: Int, CaseIterable {
    case slow = 0       // 15 秒/屏
    case normal = 1     // 10 秒/屏
    case fast = 2       // 6 秒/屏

    public var duration: TimeInterval {
        switch self {
        case .slow: return 15.0
        case .normal: return 10.0
        case .fast: return 6.0
        }
    }

    public var displayName: String {
        switch self {
        case .slow: return "慢"
        case .normal: return "普通"
        case .fast: return "快"
        }
    }
}

// MARK: - DanmakuSettings + Persistence

extension DanmakuSettings {
    /// 從 UserDefaults 載入設定
    public static func load() -> DanmakuSettings {
        let defaults = UserDefaults.standard
        return DanmakuSettings(
            opacity: CGFloat(defaults.float(forKey: "danmaku.opacity") == 0 ? 1.0 : defaults.float(forKey: "danmaku.opacity")),
            displayLines: defaults.integer(forKey: "danmaku.lines") == 0 ? 3 : defaults.integer(forKey: "danmaku.lines"),
            fontSize: DanmakuFontSize(rawValue: defaults.integer(forKey: "danmaku.fontSize")) ?? .standard,
            speed: DanmakuSpeed(rawValue: defaults.integer(forKey: "danmaku.speed")) ?? .normal,
            isEnabled: defaults.object(forKey: "danmaku.enabled") == nil ? true : defaults.bool(forKey: "danmaku.enabled")
        )
    }

    /// 儲存設定到 UserDefaults
    public func save() {
        let defaults = UserDefaults.standard
        defaults.set(Float(opacity), forKey: "danmaku.opacity")
        defaults.set(displayLines, forKey: "danmaku.lines")
        defaults.set(fontSize.rawValue, forKey: "danmaku.fontSize")
        defaults.set(speed.rawValue, forKey: "danmaku.speed")
        defaults.set(isEnabled, forKey: "danmaku.enabled")
    }
}

// MARK: - DanmakuTrack (內部使用)

/// 彈幕軌道
struct DanmakuTrack {
    /// 軌道編號（0 開始）
    let index: Int

    /// 當前軌道上的彈幕視圖
    var danmakuViews: [DanmakuLabel] = []

    /// 檢查是否可以放置新彈幕
    func canPlace(screenWidth: CGFloat, danmakuWidth: CGFloat) -> Bool {
        // 如果軌道為空，可以放置
        guard let lastView = danmakuViews.last else {
            return true
        }

        // 使用 presentation layer 獲取動畫中的實際位置
        let lastViewTrailingEdge = lastView.layer.presentation()?.frame.maxX ?? lastView.frame.maxX

        // 最小間距
        let requiredGap: CGFloat = 50

        // 最後一條彈幕的尾部已經離開畫面右側足夠距離
        return lastViewTrailingEdge < screenWidth - requiredGap
    }
}
