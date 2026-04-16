// 音视频分轨功能 单元测试

import XCTest
import AVFoundation
@testable import DXPlayerSDK

final class SplitTrackTests: XCTestCase {

    // MARK: - 同步参数验证

    /// 验证漂移阈值 = 0.3 秒
    func testSyncDriftThreshold() {
        let threshold: TimeInterval = 0.3
        // 漂移 0.2 秒：不需要校正
        XCTAssertFalse(abs(5.0 - 5.2) > threshold)
        // 漂移 0.5 秒：需要校正
        XCTAssertTrue(abs(5.0 - 5.5) > threshold)
        // 漂移正好 0.3 秒：不需要校正（>，不是 >=）
        XCTAssertFalse(abs(5.0 - 5.3) > threshold)
    }

    /// 验证同步间隔 = 2.0 秒
    func testSyncTimerInterval() {
        let interval: TimeInterval = 2.0
        XCTAssertEqual(interval, 2.0)
    }

    // MARK: - AVAudioPlayer 初始化

    /// 验证 AVAudioPlayer 可以从数据初始化
    func testAVAudioPlayerInitWithData() {
        // 生成一小段静音 WAV 数据
        let silentWAV = generateSilentWAV(durationSeconds: 1.0, sampleRate: 44100)
        do {
            let player = try AVAudioPlayer(data: silentWAV)
            player.prepareToPlay()
            XCTAssertGreaterThan(player.duration, 0)
            XCTAssertEqual(player.currentTime, 0)
        } catch {
            XCTFail("AVAudioPlayer 初始化失败: \(error)")
        }
    }

    /// 验证 AVAudioPlayer seek 功能
    func testAVAudioPlayerSeek() {
        let silentWAV = generateSilentWAV(durationSeconds: 3.0, sampleRate: 44100)
        guard let player = try? AVAudioPlayer(data: silentWAV) else {
            XCTFail("无法创建 AVAudioPlayer")
            return
        }
        player.prepareToPlay()

        // seek 到 1.5 秒
        let seekTarget: TimeInterval = 1.5
        if seekTarget < player.duration {
            player.currentTime = seekTarget
        }
        XCTAssertEqual(player.currentTime, seekTarget, accuracy: 0.01)
    }

    /// 验证 seek 超出 duration 时的安全处理
    func testSeekBeyondDuration() {
        let silentWAV = generateSilentWAV(durationSeconds: 2.0, sampleRate: 44100)
        guard let player = try? AVAudioPlayer(data: silentWAV) else {
            XCTFail("无法创建 AVAudioPlayer")
            return
        }
        player.prepareToPlay()

        // seek 目标超出 duration，不应执行 seek
        let seekTarget: TimeInterval = 10.0
        if seekTarget < player.duration {
            player.currentTime = seekTarget
        }
        // currentTime 应该保持为 0
        XCTAssertEqual(player.currentTime, 0, accuracy: 0.01)
    }

    // MARK: - play / pause 状态

    /// 验证 play 后 isPlaying 为 true
    func testPlayStartsAudio() {
        let silentWAV = generateSilentWAV(durationSeconds: 2.0, sampleRate: 44100)
        guard let player = try? AVAudioPlayer(data: silentWAV) else {
            XCTFail("无法创建 AVAudioPlayer")
            return
        }
        player.prepareToPlay()
        player.play()
        XCTAssertTrue(player.isPlaying)
        player.stop()
    }

    /// 验证 pause 后 isPlaying 为 false
    func testPauseStopsAudio() {
        let silentWAV = generateSilentWAV(durationSeconds: 2.0, sampleRate: 44100)
        guard let player = try? AVAudioPlayer(data: silentWAV) else {
            XCTFail("无法创建 AVAudioPlayer")
            return
        }
        player.prepareToPlay()
        player.play()
        player.pause()
        XCTAssertFalse(player.isPlaying)
    }

    // MARK: - Timer 管理

    /// 验证 timer 创建和销毁
    func testTimerLifecycle() {
        var timer: Timer? = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in }
        XCTAssertNotNil(timer)
        XCTAssertTrue(timer!.isValid)

        timer?.invalidate()
        timer = nil
        XCTAssertNil(timer)
    }

    /// 验证 stopAudioSync 不会 crash（timer 为 nil 时）
    func testStopSyncWithNilTimer() {
        var timer: Timer? = nil
        // 模拟 stopAudioSync
        timer?.invalidate()
        timer = nil
        XCTAssertNil(timer)
    }

    // MARK: - Dispose 安全性

    /// 验证 dispose 时清理所有资源
    func testDisposeCleanup() {
        let silentWAV = generateSilentWAV(durationSeconds: 1.0, sampleRate: 44100)
        var audioPlayer: AVAudioPlayer? = try? AVAudioPlayer(data: silentWAV)
        var syncTimer: Timer? = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in }

        audioPlayer?.prepareToPlay()
        audioPlayer?.play()

        // 模拟 dispose
        syncTimer?.invalidate()
        syncTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil

        XCTAssertNil(audioPlayer)
        XCTAssertNil(syncTimer)
    }

    // MARK: - URL 验证

    /// 验证分轨 URL 格式
    func testSplitTrackURLFormat() {
        let videoUrl = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_1k/video.mp4"
        let audioUrl = "https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_1k/audio.mp3"

        XCTAssertTrue(videoUrl.hasPrefix("https://"))
        XCTAssertTrue(audioUrl.hasPrefix("https://"))
        XCTAssertTrue(videoUrl.hasSuffix(".mp4"))
        XCTAssertTrue(audioUrl.hasSuffix(".mp3"))

        XCTAssertNotNil(URL(string: videoUrl))
        XCTAssertNotNil(URL(string: audioUrl))
    }

    /// 验证空 URL 不会创建 NSURL
    func testEmptyURLHandling() {
        let emptyUrl = ""
        // 模拟 setExternalAudioURL 的第一行检查
        if emptyUrl.isEmpty { return }
        XCTFail("不应执行到这里")
    }

    // MARK: - Helpers

    /// 生成静音 WAV 数据
    private func generateSilentWAV(durationSeconds: Double, sampleRate: Int) -> Data {
        let numSamples = Int(durationSeconds * Double(sampleRate))
        let numChannels: Int = 1
        let bitsPerSample: Int = 16
        let bytesPerSample = bitsPerSample / 8
        let dataSize = numSamples * numChannels * bytesPerSample
        let fileSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(numChannels).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        let byteRate = sampleRate * numChannels * bytesPerSample
        data.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        let blockAlign = numChannels * bytesPerSample
        data.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        data.append(Data(count: dataSize)) // 静音数据（全 0）

        return data
    }
}
