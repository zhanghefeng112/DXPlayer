import Foundation
import FSPlayer

/// 画面比例管理器
/// 负责控制视频画面的显示比例和缩放模式
public class AspectRatioManager {

    // MARK: - 属性

    private weak var player: FSPlayer?
    private var currentAspectRatio: AspectRatioMode = .original

    // MARK: - 初始化

    public init(player: FSPlayer) {
        self.player = player
        loadSavedAspectRatio()
    }

    // MARK: - 画面比例模式

    /// 画面比例模式枚举
    public enum AspectRatioMode {
        case original       // 原始尺寸
        case ratio16_9      // 16:9 比例
        case ratio4_3       // 4:3 比例
        case fill           // 鋪滿全屏

        var description: String {
            switch self {
            case .original: return "原始尺寸"
            case .ratio16_9: return "16:9"
            case .ratio4_3: return "4:3"
            case .fill: return "鋪滿全屏"
            }
        }

        var scalingMode: FSScalingMode {
            switch self {
            case .fill:
                return .fill       // 鋪滿全屏：拉伸填滿
            default:
                return .aspectFit  // 其他模式：保持比例
            }
        }

        /// 獲取 DAR (Display Aspect Ratio) 比例值
        /// - 原始尺寸和鋪滿全屏返回 0（不強制比例）
        /// - 16:9 返回 1.777...
        /// - 4:3 返回 1.333...
        var darRatio: Float {
            switch self {
            case .original: return 0
            case .ratio16_9: return 16.0 / 9.0
            case .ratio4_3: return 4.0 / 3.0
            case .fill: return 0
            }
        }

        public var rawValue: Int {
            switch self {
            case .original: return 0
            case .ratio16_9: return 1
            case .ratio4_3: return 2
            case .fill: return 3
            }
        }

        public init?(rawValue: Int) {
            switch rawValue {
            case 0: self = .original
            case 1: self = .ratio16_9
            case 2: self = .ratio4_3
            case 3: self = .fill
            default: return nil
            }
        }
    }

    // MARK: - 画面比例控制

    /// 设置画面比例模式
    /// - Parameter mode: 画面比例模式
    public func setAspectRatio(_ mode: AspectRatioMode) {
        guard let player = player else {
            DXPlayerLogger.warning("⚠️ [画面比例] 播放器未初始化")
            return
        }

        // 设置 FSPlayer 的 scalingMode
        player.scalingMode = mode.scalingMode

        // 設置 DAR (Display Aspect Ratio)
        var darPreference = FSDARPreference()
        darPreference.ratio = mode.darRatio
        player.view.darPreference = darPreference

        // 如果播放器暫停中，刷新當前畫面
        if !player.isPlaying() {
            player.view.setNeedsRefreshCurrentPic()
        }

        currentAspectRatio = mode
        saveAspectRatio(mode)

        DXPlayerLogger.info("📐 [画面比例] 设置为: \(mode.description), darRatio: \(mode.darRatio)")
    }

    /// 获取当前画面比例模式
    /// - Returns: 当前画面比例模式
    public func getCurrentAspectRatio() -> AspectRatioMode {
        return currentAspectRatio
    }

    /// 切换到下一个画面比例模式
    /// 循环顺序：原始尺寸 → 16:9 → 4:3 → 鋪滿全屏 → 原始尺寸
    public func switchToNextAspectRatio() {
        let allModes: [AspectRatioMode] = [.original, .ratio16_9, .ratio4_3, .fill]

        if let currentIndex = allModes.firstIndex(where: { $0.rawValue == currentAspectRatio.rawValue }) {
            let nextIndex = (currentIndex + 1) % allModes.count
            setAspectRatio(allModes[nextIndex])
        } else {
            setAspectRatio(.original)
        }
    }

    /// 重置为原始尺寸模式
    public func resetToFitMode() {
        setAspectRatio(.original)
    }

    // MARK: - 画面比例信息

    /// 获取画面比例描述
    /// - Returns: 当前画面比例的描述文本
    public func getAspectRatioDescription() -> String {
        return currentAspectRatio.description
    }

    /// 获取所有支持的画面比例模式
    /// - Returns: 画面比例模式列表（包含描述）
    public static func getAllAspectRatios() -> [(mode: AspectRatioMode, description: String)] {
        return [
            (.original, "原始尺寸"),
            (.ratio16_9, "16:9"),
            (.ratio4_3, "4:3"),
            (.fill, "鋪滿全屏")
        ]
    }

    // MARK: - 持久化

    private func saveAspectRatio(_ mode: AspectRatioMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "DXPlayer_AspectRatio")
    }

    private func loadSavedAspectRatio() {
        let savedValue = UserDefaults.standard.integer(forKey: "DXPlayer_AspectRatio")

        if let mode = AspectRatioMode(rawValue: savedValue) {
            currentAspectRatio = mode
            // 注意：這裡不設置 darPreference，因為 player.view 可能還未準備好
            // 實際設置會在 setAspectRatio 被調用時進行
            DXPlayerLogger.debug("📖 [画面比例] 加载保存的比例: \(mode.description)")
        }
    }
}

// MARK: - 便捷扩展

extension AspectRatioManager {

    /// 是否为原始尺寸模式
    public var isOriginalMode: Bool {
        return currentAspectRatio.rawValue == AspectRatioMode.original.rawValue
    }

    /// 是否为 16:9 模式
    public var is16_9Mode: Bool {
        return currentAspectRatio.rawValue == AspectRatioMode.ratio16_9.rawValue
    }

    /// 是否为 4:3 模式
    public var is4_3Mode: Bool {
        return currentAspectRatio.rawValue == AspectRatioMode.ratio4_3.rawValue
    }

    /// 是否为鋪滿全屏模式
    public var isFillMode: Bool {
        return currentAspectRatio.rawValue == AspectRatioMode.fill.rawValue
    }
}
