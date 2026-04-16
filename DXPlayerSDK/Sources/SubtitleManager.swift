import Foundation
import FSPlayer

/// 字幕管理器
/// 负责字幕加载、样式配置、延迟调整等功能
public class SubtitleManager {

    // MARK: - 属性

    private weak var player: FSPlayer?
    private var currentSubtitleURL: URL?
    private var loadedSubtitles: [URL] = []

    // MARK: - 初始化

    public init(player: FSPlayer) {
        self.player = player
        loadSavedPreferences()
    }

    // MARK: - 字幕加载

    /// 加载字幕文件
    /// - Parameters:
    ///   - url: 字幕文件 URL（支持 file:// 和 http(s)://）
    ///   - autoActivate: 是否自动激活显示（默认 true）
    /// - Returns: 成功返回 true，失败返回 false
    public func loadSubtitle(url: URL, autoActivate: Bool = true) -> Bool {
        guard let player = player else {
            DXPlayerLogger.warning("⚠️ [字幕] 播放器未初始化")
            print("❌ [字幕] 播放器未初始化，无法加载字幕")
            return false
        }

        print("📝 [字幕] 开始加载字幕文件: \(url.path)")
        print("📝 [字幕] 文件是否存在: \(FileManager.default.fileExists(atPath: url.path))")
        print("📝 [字幕] 播放器状态 - isPlaying: \(player.isPlaying()), isPreparedToPlay: \(player.isPreparedToPlay)")

        let success: Bool
        if autoActivate {
            success = player.loadThenActiveSubtitle(url)
            print("📝 [字幕] loadThenActiveSubtitle 结果: \(success)")
            if success {
                currentSubtitleURL = url
                DXPlayerLogger.info("✅ [字幕] 加载并激活: \(url.lastPathComponent)")
            }
        } else {
            success = player.loadSubtitleOnly(url)
            print("📝 [字幕] loadSubtitleOnly 结果: \(success)")
            if success {
                DXPlayerLogger.info("✅ [字幕] 仅加载: \(url.lastPathComponent)")
            }
        }

        if success {
            loadedSubtitles.append(url)
            print("✅ [字幕] 字幕已添加到列表，当前字幕数量: \(loadedSubtitles.count)")
        } else {
            DXPlayerLogger.error("❌ [字幕] 加载失败: \(url.lastPathComponent)")
            print("❌ [字幕] 加载失败: \(url.lastPathComponent)")
        }

        return success
    }

    /// 批量加载字幕文件
    /// - Parameter urls: 字幕文件 URL 数组
    /// - Returns: 成功返回 true，失败返回 false
    public func loadSubtitles(urls: [URL]) -> Bool {
        guard let player = player else {
            DXPlayerLogger.warning("⚠️ [字幕] 播放器未初始化")
            return false
        }

        let success = player.loadSubtitlesOnly(urls)
        if success {
            loadedSubtitles.append(contentsOf: urls)
            DXPlayerLogger.info("✅ [字幕] 批量加载 \(urls.count) 个字幕")
        } else {
            DXPlayerLogger.error("❌ [字幕] 批量加载失败")
        }

        return success
    }

    /// 激活指定索引的字幕
    /// - Parameter index: 字幕索引（基于已加载的字幕列表）
    public func activateSubtitle(at index: Int) {
        guard index >= 0 && index < loadedSubtitles.count else {
            DXPlayerLogger.warning("⚠️ [字幕] 无效的索引: \(index)")
            return
        }

        let url = loadedSubtitles[index]
        _ = loadSubtitle(url: url, autoActivate: true)
    }

    /// 关闭字幕
    public func removeSubtitle() {
        guard let player = player else { return }

        player.closeCurrentStream(FS_VAL_TYPE__SUBTITLE)
        currentSubtitleURL = nil
        DXPlayerLogger.info("🚫 [字幕] 已关闭")
    }

    // MARK: - 字幕样式配置

    /// 配置字幕样式
    /// - Parameters:
    ///   - scale: 字体缩放（默认 1.0）
    ///   - bottomMargin: 距离底部距离 [0.0, 1.0]（默认 0.05）
    ///   - fontName: 字体名称（默认 "Arial"）
    ///   - textColor: 文字颜色 RGBA Hex（默认 0xFFFFFF00 白色）
    ///   - outlineWidth: 边框宽度（默认 2.0）
    ///   - outlineColor: 边框颜色 RGBA Hex（默认 0x00000000 黑色）
    public func configureStyle(
        scale: Float = 1.0,
        bottomMargin: Float = 0.05,
        fontName: String = "Arial",
        textColor: UInt32 = 0xFFFFFF00,
        outlineWidth: Float = 2.0,
        outlineColor: UInt32 = 0x00000000
    ) {
        guard let player = player else {
            DXPlayerLogger.warning("⚠️ [字幕] 播放器未初始化")
            return
        }

        var preference = fs_subtitle_default_preference()
        preference.Scale = scale
        preference.BottomMargin = bottomMargin
        preference.ForceOverride = 1

        // 设置字体名称
        withUnsafeMutableBytes(of: &preference.FontName) { ptr in
            let buffer = ptr.bindMemory(to: CChar.self)
            fontName.utf8CString.withUnsafeBufferPointer { source in
                let copyCount = min(source.count, 256)
                memcpy(buffer.baseAddress, source.baseAddress, copyCount)
            }
        }

        preference.PrimaryColour = textColor
        preference.Outline = outlineWidth
        preference.OutlineColour = outlineColor

        player.subtitlePreference = preference

        // 保存样式设置
        saveStylePreferences(preference)

        DXPlayerLogger.info("🎨 [字幕] 样式已更新 - 缩放:\(scale) 边框:\(outlineWidth)")
    }

    /// 使用预设样式
    public enum SubtitleStyle {
        case `default`      // 默认样式（白色文字 + 黑色边框）
        case largeWhite     // 大号白色（1.5x）
        case mediumYellow   // 中号黄色
        case smallCyan      // 小号青色
    }

    /// 应用预设样式
    /// - Parameter style: 预设样式枚举
    public func applyPresetStyle(_ style: SubtitleStyle) {
        switch style {
        case .default:
            configureStyle(
                scale: 1.0,
                bottomMargin: 0.05,
                textColor: 0xFFFFFF00,  // 白色
                outlineWidth: 2.0,
                outlineColor: 0x00000000 // 黑色边框
            )
        case .largeWhite:
            configureStyle(
                scale: 1.5,
                bottomMargin: 0.08,
                textColor: 0xFFFFFF00,  // 白色
                outlineWidth: 3.0,
                outlineColor: 0x00000000 // 黑色边框
            )
        case .mediumYellow:
            configureStyle(
                scale: 1.2,
                bottomMargin: 0.05,
                textColor: 0xFFFF0000,  // 黄色
                outlineWidth: 2.0,
                outlineColor: 0x00000080 // 黑色半透明边框
            )
        case .smallCyan:
            configureStyle(
                scale: 0.8,
                bottomMargin: 0.03,
                textColor: 0x00FFFF00,  // 青色
                outlineWidth: 1.5,
                outlineColor: 0x00000000 // 黑色边框
            )
        }
    }

    // MARK: - 字幕延迟调整

    /// 设置字幕延迟
    /// - Parameter delay: 延迟时间（秒），正值延迟显示，负值提前显示
    public func setSubtitleDelay(_ delay: Float) {
        guard let player = player else {
            DXPlayerLogger.warning("⚠️ [字幕] 播放器未初始化")
            return
        }

        player.currentSubtitleExtraDelay = delay
        saveSubtitleDelay(delay)

        let delayText = delay >= 0 ? "+\(delay)s" : "\(delay)s"
        DXPlayerLogger.info("⏱ [字幕] 延迟设置: \(delayText)")
    }

    /// 获取当前字幕延迟
    /// - Returns: 延迟时间（秒）
    public func getSubtitleDelay() -> Float {
        return player?.currentSubtitleExtraDelay ?? 0.0
    }

    // MARK: - 字幕信息

    /// 获取已加载的字幕列表
    /// - Returns: 字幕 URL 数组
    public func getLoadedSubtitles() -> [URL] {
        return loadedSubtitles
    }

    /// 获取当前激活的字幕 URL
    /// - Returns: 当前字幕 URL
    public func getCurrentSubtitleURL() -> URL? {
        return currentSubtitleURL
    }

    // MARK: - 持久化

    private func saveStylePreferences(_ preference: FSSubtitlePreference) {
        UserDefaults.standard.set(preference.Scale, forKey: "DXPlayer_Subtitle_Scale")
        UserDefaults.standard.set(preference.BottomMargin, forKey: "DXPlayer_Subtitle_BottomMargin")
        UserDefaults.standard.set(preference.PrimaryColour, forKey: "DXPlayer_Subtitle_TextColor")
        UserDefaults.standard.set(preference.Outline, forKey: "DXPlayer_Subtitle_OutlineWidth")
        UserDefaults.standard.set(preference.OutlineColour, forKey: "DXPlayer_Subtitle_OutlineColor")
    }

    private func saveSubtitleDelay(_ delay: Float) {
        UserDefaults.standard.set(delay, forKey: "DXPlayer_Subtitle_Delay")
    }

    private func loadSavedPreferences() {
        guard let player = player else { return }

        // 加载样式设置
        let scale = UserDefaults.standard.float(forKey: "DXPlayer_Subtitle_Scale")
        let bottomMargin = UserDefaults.standard.float(forKey: "DXPlayer_Subtitle_BottomMargin")
        let textColor = UInt32(UserDefaults.standard.integer(forKey: "DXPlayer_Subtitle_TextColor"))
        let outlineWidth = UserDefaults.standard.float(forKey: "DXPlayer_Subtitle_OutlineWidth")
        let outlineColor = UInt32(UserDefaults.standard.integer(forKey: "DXPlayer_Subtitle_OutlineColor"))

        if scale > 0 {
            var preference = fs_subtitle_default_preference()
            preference.Scale = scale
            preference.BottomMargin = bottomMargin
            preference.ForceOverride = 1
            preference.PrimaryColour = textColor
            preference.Outline = outlineWidth
            preference.OutlineColour = outlineColor
            player.subtitlePreference = preference
        }

        // 加载延迟设置
        let delay = UserDefaults.standard.float(forKey: "DXPlayer_Subtitle_Delay")
        if delay != 0 {
            player.currentSubtitleExtraDelay = delay
        }
    }
}

// MARK: - 字幕颜色工具扩展

extension SubtitleManager {

    /// 字幕颜色常量（RGBA Hex 格式）
    public struct SubtitleColor {
        public static let white: UInt32         = 0xFFFFFF00  // 白色
        public static let black: UInt32         = 0x00000000  // 黑色
        public static let red: UInt32           = 0xFF000000  // 红色
        public static let green: UInt32         = 0x00FF0000  // 绿色
        public static let blue: UInt32          = 0x0000FF00  // 蓝色
        public static let yellow: UInt32        = 0xFFFF0000  // 黄色
        public static let cyan: UInt32          = 0x00FFFF00  // 青色
        public static let magenta: UInt32       = 0xFF00FF00  // 品红
        public static let blackTransparent: UInt32 = 0x00000080  // 黑色半透明
    }

    /// 从 RGB 创建字幕颜色
    /// - Parameters:
    ///   - red: 红色 (0-255)
    ///   - green: 绿色 (0-255)
    ///   - blue: 蓝色 (0-255)
    ///   - alpha: 透明度 (0=不透明, 255=全透明)
    /// - Returns: RGBA Hex 颜色值
    public static func makeColor(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 0) -> UInt32 {
        return (UInt32(red) << 24) | (UInt32(green) << 16) | (UInt32(blue) << 8) | UInt32(alpha)
    }
}
