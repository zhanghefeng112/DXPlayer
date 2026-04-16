import Foundation
import FSPlayer

/// 播放器控制逻辑 ViewModel
class PlayerControlViewModel {

    // MARK: - 状态属性

    /// 是否正在播放
    var isPlaying: Bool = false

    /// 当前播放时间（秒）
    var currentTime: TimeInterval = 0

    /// 视频总时长（秒）
    var duration: TimeInterval = 0

    /// 缓冲进度（0.0 - 1.0）
    var bufferProgress: Float = 0

    // MARK: - 回调

    /// 播放状态变化回调
    var onPlayStateChanged: ((Bool) -> Void)?

    /// 播放进度变化回调
    var onProgressChanged: ((TimeInterval, TimeInterval) -> Void)?

    /// 缓冲状态变化回调
    var onBufferingStateChanged: ((Bool) -> Void)?

    // MARK: - 初始化

    init() {}

    // MARK: - 公共方法

    /// 格式化时间为字符串
    /// - Parameter time: 时间（秒）
    /// - Returns: 格式化后的时间字符串，如 "02:05" 或 "01:01:05"
    func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && !time.isInfinite else {
            return "00:00"
        }

        let totalSeconds = Int(max(0, time))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// 计算当前播放进度百分比
    /// - Returns: 进度百分比（0.0 - 1.0）
    func progressPercentage() -> Float {
        guard duration > 0 else { return 0 }
        return Float(currentTime / duration)
    }

    /// 更新播放状态
    /// - Parameter state: IJKPlayer 播放状态
    func updatePlaybackState(_ state: FSPlayerPlaybackState) {
        let wasPlaying = isPlaying
        isPlaying = (state == .playing)

        if wasPlaying != isPlaying {
            onPlayStateChanged?(isPlaying)
        }
    }

    /// 更新播放进度
    /// - Parameters:
    ///   - current: 当前播放时间
    ///   - duration: 视频总时长
    func updateProgress(current: TimeInterval, duration: TimeInterval) {
        self.currentTime = current
        self.duration = duration
        onProgressChanged?(current, duration)
    }

    /// 更新缓冲进度
    /// - Parameter progress: 缓冲进度（0.0 - 1.0）
    func updateBufferProgress(_ progress: Float) {
        self.bufferProgress = progress
    }

    /// 触发缓冲状态变化
    /// - Parameter isBuffering: 是否正在缓冲
    func notifyBufferingStateChanged(_ isBuffering: Bool) {
        onBufferingStateChanged?(isBuffering)
    }

    /// 根据视频时长计算 Seek 偏移量对应的时间
    /// - Parameter offset: 偏移量（秒）
    /// - Returns: 目标时间，限制在 [0, duration] 范围内
    func calculateSeekTime(offset: TimeInterval) -> TimeInterval {
        let targetTime = currentTime + offset
        return max(0, min(targetTime, duration))
    }
}
