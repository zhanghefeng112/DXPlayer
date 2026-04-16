import Foundation
import FSPlayer

/// 播放速度管理器
/// 负责控制视频播放速度（倍速播放）
public class PlaybackSpeedManager {

    // MARK: - 属性

    private weak var player: FSPlayer?
    private var currentSpeed: Float = 1.0

    /// 支持的播放速度列表
    public static let supportedSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    // MARK: - 初始化

    public init(player: FSPlayer) {
        self.player = player
        loadSavedSpeed()
    }

    // MARK: - 播放速度控制

    /// 设置播放速度
    /// - Parameter speed: 播放速度倍率（0.5 ~ 2.0）
    public func setPlaybackSpeed(_ speed: Float) {
        guard speed >= 0.5 && speed <= 2.0 else {
            DXPlayerLogger.warning("⚠️ [播放速度] 无效的速度值: \(speed)，范围应为 0.5 ~ 2.0")
            return
        }

        guard let player = player else {
            DXPlayerLogger.warning("⚠️ [播放速度] 播放器未初始化")
            return
        }

        player.playbackRate = speed
        currentSpeed = speed
        savePlaybackSpeed(speed)

        let speedText = formatSpeedText(speed)
        DXPlayerLogger.info("⚡️ [播放速度] 设置为: \(speedText)")
    }

    /// 获取当前播放速度
    /// - Returns: 当前速度倍率
    public func getCurrentSpeed() -> Float {
        return currentSpeed
    }

    /// 切换到下一个速度
    /// 按照支持的速度列表循环切换：0.5x → 0.75x → 1.0x → 1.25x → 1.5x → 2.0x → 0.5x ...
    public func switchToNextSpeed() {
        let speeds = PlaybackSpeedManager.supportedSpeeds

        // 查找当前速度在列表中的索引
        if let currentIndex = speeds.firstIndex(where: { abs($0 - currentSpeed) < 0.01 }) {
            // 切换到下一个速度
            let nextIndex = (currentIndex + 1) % speeds.count
            setPlaybackSpeed(speeds[nextIndex])
        } else {
            // 如果当前速度不在列表中，重置为 1.0x
            setPlaybackSpeed(1.0)
        }
    }

    /// 重置为正常速度（1.0x）
    public func resetToNormalSpeed() {
        setPlaybackSpeed(1.0)
    }

    // MARK: - 速度预设

    /// 播放速度预设枚举
    public enum SpeedPreset {
        case slow       // 0.5x 慢速
        case slower     // 0.75x 较慢
        case normal     // 1.0x 正常
        case faster     // 1.25x 较快
        case fast       // 1.5x 快速
        case veryFast   // 2.0x 很快

        var value: Float {
            switch self {
            case .slow: return 0.5
            case .slower: return 0.75
            case .normal: return 1.0
            case .faster: return 1.25
            case .fast: return 1.5
            case .veryFast: return 2.0
            }
        }

        var description: String {
            switch self {
            case .slow: return "0.5x 慢速"
            case .slower: return "0.75x 较慢"
            case .normal: return "1.0x 正常"
            case .faster: return "1.25x 较快"
            case .fast: return "1.5x 快速"
            case .veryFast: return "2.0x 很快"
            }
        }
    }

    /// 应用速度预设
    /// - Parameter preset: 速度预设枚举
    public func applySpeedPreset(_ preset: SpeedPreset) {
        setPlaybackSpeed(preset.value)
    }

    // MARK: - 格式化

    /// 格式化速度文本
    /// - Parameter speed: 速度值
    /// - Returns: 格式化的文本（如 "1.0x"、"1.5x"）
    public func formatSpeedText(_ speed: Float) -> String {
        if speed == 1.0 {
            return "正常"
        } else if speed.truncatingRemainder(dividingBy: 1.0) == 0 {
            return "\(Int(speed)).0x"
        } else {
            return String(format: "%.2fx", speed)
        }
    }

    /// 获取速度描述文本
    /// - Parameter speed: 速度值
    /// - Returns: 描述文本（如 "正常"、"1.5x 快速"）
    public func getSpeedDescription(_ speed: Float) -> String {
        let presets: [SpeedPreset] = [.slow, .slower, .normal, .faster, .fast, .veryFast]

        for preset in presets {
            if abs(preset.value - speed) < 0.01 {
                return preset.description
            }
        }

        return formatSpeedText(speed)
    }

    // MARK: - 持久化

    private func savePlaybackSpeed(_ speed: Float) {
        UserDefaults.standard.set(speed, forKey: "DXPlayer_PlaybackSpeed")
    }

    private func loadSavedSpeed() {
        let savedSpeed = UserDefaults.standard.float(forKey: "DXPlayer_PlaybackSpeed")

        if savedSpeed > 0 {
            currentSpeed = savedSpeed
            player?.playbackRate = savedSpeed
            DXPlayerLogger.debug("📖 [播放速度] 加载保存的速度: \(formatSpeedText(savedSpeed))")
        }
    }
}

// MARK: - 便捷扩展

extension PlaybackSpeedManager {

    /// 是否为正常速度
    public var isNormalSpeed: Bool {
        return abs(currentSpeed - 1.0) < 0.01
    }

    /// 是否为慢速播放
    public var isSlowMotion: Bool {
        return currentSpeed < 1.0
    }

    /// 是否为快速播放
    public var isFastForward: Bool {
        return currentSpeed > 1.0
    }

    /// 支持的速度选项列表（包含描述）
    public static var speedOptions: [(value: Float, description: String)] {
        return [
            (0.5, "0.5x 慢速"),
            (0.75, "0.75x 较慢"),
            (1.0, "1.0x 正常"),
            (1.25, "1.25x 较快"),
            (1.5, "1.5x 快速"),
            (2.0, "2.0x 很快")
        ]
    }
}
