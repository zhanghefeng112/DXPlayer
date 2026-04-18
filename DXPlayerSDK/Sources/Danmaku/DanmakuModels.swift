import Foundation
import UIKit

// MARK: - DanmakuMode

/// 彈幕顯示模式（對應 API mode 欄位）
public enum DanmakuMode: String {
    /// 從右往左滾動（預設）
    case scroll = "scroll"
    /// 固定在頂部
    case top = "top"
    /// 固定在底部
    case bottom = "bottom"
    /// 從左往右滾動（反向）
    case reverse = "reverse"
}

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

    /// 彈幕顯示模式（對應 API mode 欄位，預設 scroll）
    public let mode: DanmakuMode

    /// 發送者頭銜（GM / UP主 / VIP1-10 / 空字串）
    public let title: String?

    /// 時間戳（僅時間軸模式使用）
    /// 表示該彈幕應該在影片的哪個時間點顯示（秒）
    public let timestamp: TimeInterval?

    /// 服務端發送時間（毫秒 Unix 時間戳，對應 API send_time 欄位）
    public let sendTime: Int64?

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
        mode: DanmakuMode = .scroll,
        title: String? = nil,
        timestamp: TimeInterval? = nil,
        sendTime: Int64? = nil,
        receivedAt: Date = Date(),
        isSelf: Bool = false
    ) {
        self.id = id
        self.text = text
        self.userId = userId
        self.userName = userName
        self.color = color
        self.fontSize = fontSize
        self.mode = mode
        self.title = title
        self.timestamp = timestamp
        self.sendTime = sendTime
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

    /// 發送模式（默認滾動）
    public var sendMode: DanmakuMode

    /// 發送顏色 HEX 字符串（nil = 服務端使用用戶默認設置）
    public var sendColor: String?

    /// 預設值
    public static var `default`: DanmakuSettings {
        return DanmakuSettings(
            opacity: 1.0,
            displayLines: 3,
            fontSize: .standard,
            speed: .normal,
            isEnabled: true,
            sendMode: .scroll,
            sendColor: nil
        )
    }

    /// 初始化
    public init(
        opacity: CGFloat = 1.0,
        displayLines: Int = 3,
        fontSize: DanmakuFontSize = .standard,
        speed: DanmakuSpeed = .normal,
        isEnabled: Bool = true,
        sendMode: DanmakuMode = .scroll,
        sendColor: String? = nil
    ) {
        self.opacity = max(0.0, min(1.0, opacity))
        self.displayLines = max(1, min(5, displayLines))
        self.fontSize = fontSize
        self.speed = speed
        self.isEnabled = isEnabled
        self.sendMode = sendMode
        self.sendColor = sendColor
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
            isEnabled: defaults.object(forKey: "danmaku.enabled") == nil ? true : defaults.bool(forKey: "danmaku.enabled"),
            sendMode: DanmakuMode(rawValue: defaults.string(forKey: "danmaku.sendMode") ?? "") ?? .scroll,
            sendColor: defaults.string(forKey: "danmaku.sendColor")
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
        defaults.set(sendMode.rawValue, forKey: "danmaku.sendMode")
        if let color = sendColor {
            defaults.set(color, forKey: "danmaku.sendColor")
        } else {
            defaults.removeObject(forKey: "danmaku.sendColor")
        }
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

// MARK: - UIColor HEX 解析（弹幕内部工具）

extension UIColor {
    /// 從 HEX 字符串解析顏色，支持 `#RRGGBB` 和 `#RRGGBBAA` 格式
    /// - Returns: 解析失敗返回 nil
    static func danmaku_fromHex(_ hex: String) -> UIColor? {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        guard str.count == 6 || str.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: str).scanHexInt64(&value) else { return nil }
        let r, g, b, a: CGFloat
        if str.count == 6 {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >>  8) & 0xFF) / 255
            b = CGFloat( value        & 0xFF) / 255
            a = 1.0
        } else {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >>  8) & 0xFF) / 255
            a = CGFloat( value        & 0xFF) / 255
        }
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - DanmakuUserSetting

/// 服务端返回的用户弹幕设置（GET /api/danmu/setting）
public struct DanmakuUserSetting {
    /// 用户自定义弹幕颜色 HEX，nil 表示未设置（使用服务端默认）
    public let color: String?
    /// VIP 等级（0=非VIP，1-10=VIP等级）
    public let vipLevel: Int
    /// 是否为UP主（由三方系统同步）
    public let isUper: Bool
    /// 屏蔽关键字列表
    public let disturbKeywords: [String]
    /// 接收等级过滤（0=接收全部，1-10=仅接收该等级及以上用户的弹幕）
    public let receiveLevel: Int
}

/// 用于更新弹幕设置的请求体（POST /api/danmu/setting）
/// 所有字段均为可选，nil 表示不修改该字段
public struct DanmakuUserSettingUpdate {
    /// 弹幕颜色 HEX：nil=不修改，""=清除（恢复服务端默认），"#RRGGBB"=设置新颜色
    public var color: String?
    /// 屏蔽关键字：nil=不修改，[]=清除所有关键字
    public var disturbKeywords: [String]?
    /// 接收等级：nil=不修改，0=全部，1-10=最低VIP等级
    public var receiveLevel: Int?

    public init(
        color: String? = nil,
        disturbKeywords: [String]? = nil,
        receiveLevel: Int? = nil
    ) {
        self.color = color
        self.disturbKeywords = disturbKeywords
        self.receiveLevel = receiveLevel
    }
}
