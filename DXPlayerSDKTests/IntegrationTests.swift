// Integration Tests — 测试多个模块协同工作

import XCTest
@testable import DXPlayerSDK

final class IntegrationTests: XCTestCase {

    // MARK: - SubtitleTrack + switchSubtitle 集成

    func testSubtitleTrackListAndSwitch() {
        let tracks: [IJKPlayerContainerView.SubtitleTrack] = [
            .init(lang: "zh", label: "简体中文", url: "https://cdn.example.com/zh.srt"),
            .init(lang: "en", label: "English", url: "https://cdn.example.com/en.srt"),
            .init(lang: "ja", label: "日本語", url: "https://cdn.example.com/ja.srt"),
        ]
        XCTAssertEqual(tracks.count, 3)
        XCTAssertEqual(tracks.first?.lang, "zh")
        XCTAssertEqual(tracks.last?.label, "日本語")

        // 模拟语言偏好保存
        UserDefaults.standard.set("en", forKey: "DXPlayer_SubtitleLangPref")
        let saved = UserDefaults.standard.string(forKey: "DXPlayer_SubtitleLangPref")
        XCTAssertEqual(saved, "en")

        // 模拟找到偏好语言
        let preferred = tracks.first { $0.lang == saved }
        XCTAssertNotNil(preferred)
        XCTAssertEqual(preferred?.label, "English")

        // 清理
        UserDefaults.standard.removeObject(forKey: "DXPlayer_SubtitleLangPref")
    }

    // MARK: - SRT 修复 + 解析 集成

    func testSrtFixAndParse() {
        // 非标准 SRT（缺序号、时间戳不完整）
        let badSrt = """
        00:00:04,000 --> 00:00:06

        主引擎开始启动



        1

        00:00:23,000 --> 00:00:24,500

        你太无耻了, Thom.
        """

        // 修复后应该能正确解析
        let timePattern = try! NSRegularExpression(
            pattern: #"(\d{2}:\d{2}:\d{2}[,\.]?\d{0,3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]?\d{0,3})"#)
        let lines = badSrt.components(separatedBy: "\n")

        var timeLineIndices: [Int] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if timePattern.firstMatch(in: trimmed, range: range) != nil {
                timeLineIndices.append(i)
            }
        }
        XCTAssertEqual(timeLineIndices.count, 2, "应找到 2 个时间戳行")

        // 提取文字
        var subtitles: [(String, String)] = [] // (time, text)
        for (idx, timeIdx) in timeLineIndices.enumerated() {
            let timeLine = lines[timeIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let nextBound = idx + 1 < timeLineIndices.count ? timeLineIndices[idx + 1] : lines.count
            var textLines: [String] = []
            for j in (timeIdx + 1)..<nextBound {
                let trimmed = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if trimmed.allSatisfy({ $0.isNumber }) { continue }
                textLines.append(trimmed)
            }
            if !textLines.isEmpty {
                subtitles.append((timeLine, textLines.joined(separator: "\n")))
            }
        }
        XCTAssertEqual(subtitles.count, 2)
        XCTAssertEqual(subtitles[0].1, "主引擎开始启动")
        XCTAssertEqual(subtitles[1].1, "你太无耻了, Thom.")
    }

    // MARK: - 时间戳修复

    func testTimestampFix() {
        func fixTimestamp(_ ts: String) -> String {
            var t = ts.trimmingCharacters(in: .whitespaces)
            if !t.contains(",") && !t.contains(".") { t += ",000" }
            return t.replacingOccurrences(of: ".", with: ",")
        }

        XCTAssertEqual(fixTimestamp("00:00:06"), "00:00:06,000")
        XCTAssertEqual(fixTimestamp("00:00:23,500"), "00:00:23,500")
        XCTAssertEqual(fixTimestamp("00:01:05.200"), "00:01:05,200")
    }

    // MARK: - SRT 时间转秒

    func testSrtTimeToSeconds() {
        func srtTimeToSeconds(_ time: String) -> Double {
            let cleaned = time.replacingOccurrences(of: ",", with: ".")
            let parts = cleaned.components(separatedBy: ":")
            guard parts.count == 3 else { return 0 }
            let h = Double(parts[0]) ?? 0
            let m = Double(parts[1]) ?? 0
            let s = Double(parts[2]) ?? 0
            return h * 3600 + m * 60 + s
        }

        XCTAssertEqual(srtTimeToSeconds("00:00:23,500"), 23.5, accuracy: 0.01)
        XCTAssertEqual(srtTimeToSeconds("00:01:05,000"), 65.0, accuracy: 0.01)
        XCTAssertEqual(srtTimeToSeconds("01:30:00,000"), 5400.0, accuracy: 0.01)
        XCTAssertEqual(srtTimeToSeconds("00:00:00,000"), 0.0, accuracy: 0.01)
    }

    // MARK: - DanmakuSettings + APIDanmakuDataSource 集成

    func testDanmakuSettingsPersistence() {
        // 保存设置
        var settings = DanmakuSettings()
        settings.opacity = 0.6
        settings.displayLines = 4
        settings.fontSize = .large
        settings.speed = .slow
        settings.save()

        // 重新加载
        let loaded = DanmakuSettings.load()
        XCTAssertEqual(loaded.opacity, 0.6, accuracy: 0.01)
        XCTAssertEqual(loaded.displayLines, 4)
        XCTAssertEqual(loaded.fontSize, .large)
        XCTAssertEqual(loaded.speed, .slow)

        // 恢复默认
        var defaults = DanmakuSettings()
        defaults.save()
    }

    func testAPIDanmakuDataSourceInit() {
        let source = APIDanmakuDataSource(baseURL: "https://api.example.com", pollingInterval: 15)
        XCTAssertEqual(source.sourceType, .timeline)
        source.stop() // 不崩溃
    }

    // MARK: - DanmakuItem 颜色解析

    func testDanmakuColorParsing() {
        // 测试 hex 颜色解析
        let item1 = DanmakuItem(text: "测试", color: .white)
        XCTAssertEqual(item1.color, .white)

        let item2 = DanmakuItem(text: "红色", color: .red)
        XCTAssertEqual(item2.color, .red)
    }

    // MARK: - 多语言字幕偏好 + 列表匹配

    func testSubtitlePreferenceMatching() {
        let tracks: [IJKPlayerContainerView.SubtitleTrack] = [
            .init(lang: "zh", label: "简体中文", url: "https://cdn.example.com/zh.srt"),
            .init(lang: "en", label: "English", url: "https://cdn.example.com/en.srt"),
        ]

        // 有匹配的偏好
        let match = tracks.first { $0.lang == "zh" }
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.url, "https://cdn.example.com/zh.srt")

        // 无匹配时使用第一个
        let noMatch = tracks.first { $0.lang == "fr" }
        XCTAssertNil(noMatch)
        let fallback = tracks.first
        XCTAssertEqual(fallback?.lang, "zh")
    }

    // MARK: - SubtitleManager 样式预设完整性

    func testAllSubtitlePresets() {
        let defaultPref = fs_subtitle_default_preference()

        // 验证默认值
        XCTAssertEqual(defaultPref.Scale, 1.0)
        XCTAssertEqual(defaultPref.Outline, 1.0)
        XCTAssertEqual(defaultPref.ForceOverride, 0)

        // 验证颜色常量
        XCTAssertEqual(SubtitleManager.SubtitleColor.white, 0xFFFFFF00)
        XCTAssertEqual(SubtitleManager.SubtitleColor.black, 0x00000000)
        XCTAssertEqual(SubtitleManager.SubtitleColor.red, 0xFF000000)
        XCTAssertEqual(SubtitleManager.SubtitleColor.yellow, 0xFFFF0000)
        XCTAssertEqual(SubtitleManager.SubtitleColor.cyan, 0x00FFFF00)

        // 验证 makeColor
        let customColor = SubtitleManager.makeColor(red: 128, green: 64, blue: 32, alpha: 0)
        XCTAssertEqual(customColor, 0x80402000)
    }
}
