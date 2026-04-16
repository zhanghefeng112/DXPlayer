// M4 字幕/弹幕系统 单元测试

import XCTest
@testable import DXPlayerSDK

final class M4SubtitleDanmakuTests: XCTestCase {

    // MARK: - SubtitleTrack

    func testSubtitleTrackInit() {
        let track = IJKPlayerContainerView.SubtitleTrack(lang: "en", label: "English", url: "https://cdn/en.vtt")
        XCTAssertEqual(track.lang, "en")
        XCTAssertEqual(track.label, "English")
        XCTAssertEqual(track.url, "https://cdn/en.vtt")
    }

    func testMultipleSubtitleTracks() {
        let tracks = [
            IJKPlayerContainerView.SubtitleTrack(lang: "en", label: "English", url: "https://cdn/en.vtt"),
            IJKPlayerContainerView.SubtitleTrack(lang: "zh", label: "中文", url: "https://cdn/zh.vtt"),
            IJKPlayerContainerView.SubtitleTrack(lang: "ja", label: "日本語", url: "https://cdn/ja.vtt"),
        ]
        XCTAssertEqual(tracks.count, 3)
        XCTAssertEqual(tracks[1].label, "中文")
    }

    // MARK: - SubtitleManager 样式

    func testSubtitleDefaultPreference() {
        let pref = fs_subtitle_default_preference()
        XCTAssertEqual(pref.Scale, 1.0)
        XCTAssertEqual(pref.BottomMargin, 0.025, accuracy: 0.001)
        XCTAssertEqual(pref.ForceOverride, 0)
        XCTAssertEqual(pref.Outline, 1.0)
    }

    func testSubtitlePreferenceEquality() {
        var p1 = fs_subtitle_default_preference()
        var p2 = fs_subtitle_default_preference()
        XCTAssertEqual(FSSubtitlePreferenceIsEqual(&p1, &p2), 1)

        p2.Scale = 2.0
        XCTAssertEqual(FSSubtitlePreferenceIsEqual(&p1, &p2), 0)
    }

    func testSubtitlePreferenceScaleChange() {
        var pref = fs_subtitle_default_preference()
        pref.Scale = 1.5
        XCTAssertEqual(pref.Scale, 1.5)
    }

    // MARK: - DanmakuSettings 持久化

    func testDanmakuSettingsSaveAndLoad() {
        var settings = DanmakuSettings()
        settings.opacity = 0.5
        settings.displayLines = 2
        settings.fontSize = .large
        settings.speed = .slow
        settings.save()

        let loaded = DanmakuSettings.load()
        XCTAssertEqual(loaded.opacity, 0.5, accuracy: 0.01)
        XCTAssertEqual(loaded.displayLines, 2)
        XCTAssertEqual(loaded.fontSize, .large)
        XCTAssertEqual(loaded.speed, .slow)

        // 恢复默认
        var defaults = DanmakuSettings()
        defaults.save()
    }

    func testDanmakuSettingsDefaultValues() {
        let settings = DanmakuSettings()
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.opacity, 1.0, accuracy: 0.01)
        XCTAssertEqual(settings.displayLines, 3)
        XCTAssertEqual(settings.fontSize, .standard)
        XCTAssertEqual(settings.speed, .normal)
    }

    // MARK: - DanmakuItem

    func testDanmakuItemInit() {
        let item = DanmakuItem(text: "测试弹幕")
        XCTAssertEqual(item.text, "测试弹幕")
        XCTAssertFalse(item.isSelf)
    }

    func testDanmakuItemWithColor() {
        let item = DanmakuItem(text: "红色弹幕", color: .red)
        XCTAssertEqual(item.color, .red)
    }

    // MARK: - 字幕语言偏好

    func testSubtitleLangPreference() {
        // 保存
        UserDefaults.standard.set("zh", forKey: "DXPlayer_SubtitleLangPref")
        // 读取
        let lang = UserDefaults.standard.string(forKey: "DXPlayer_SubtitleLangPref")
        XCTAssertEqual(lang, "zh")

        // 清除
        UserDefaults.standard.removeObject(forKey: "DXPlayer_SubtitleLangPref")
        let cleared = UserDefaults.standard.string(forKey: "DXPlayer_SubtitleLangPref")
        XCTAssertNil(cleared)
    }

    func testSubtitleLangPreferenceNil() {
        UserDefaults.standard.removeObject(forKey: "DXPlayer_SubtitleLangPref")
        let lang = UserDefaults.standard.string(forKey: "DXPlayer_SubtitleLangPref")
        XCTAssertNil(lang)
    }

    // MARK: - SubtitleManager 颜色工具

    func testSubtitleColorMake() {
        let color = SubtitleManager.makeColor(red: 255, green: 0, blue: 0, alpha: 0)
        XCTAssertEqual(color, 0xFF000000)
    }

    func testSubtitleColorPresets() {
        XCTAssertEqual(SubtitleManager.SubtitleColor.white, 0xFFFFFF00)
        XCTAssertEqual(SubtitleManager.SubtitleColor.yellow, 0xFFFF0000)
    }

    // MARK: - URL 验证

    func testSubtitleURLValid() {
        let url = URL(string: "https://cdn.example.com/subtitle_en.vtt")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.hasSuffix(".vtt"))
    }

    func testSubtitleURLEmpty() {
        let url = URL(string: "")
        XCTAssertNil(url)
    }
}
