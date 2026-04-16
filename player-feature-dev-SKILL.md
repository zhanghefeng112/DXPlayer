---
name: player-feature-dev
description: "播放器 SDK 串接指南。帮助开发者快速接入 Flutter SDK 和 iOS SDK 的播放器功能（加密播放、广告、分轨音视频、字幕、弹幕）。当用户要求接入播放器、查 API、写播放器代码时触发。"
---

# 播放器 SDK 串接指南

帮助开发者快速接入自研播放器 SDK 的各项功能。

## 项目信息

| 项目 | Flutter SDK | iOS SDK |
|------|------------|---------|
| 仓库 | `git@foya:china/gb_ios_android_web_flutter.git` | `git@foya:china/gb_ios.git` |
| 分支 | `jm-decryptor-plugin` | `master` |
| Bundle ID | `com.flutterplayer.www` | `com.dxplayer.www` |
| 包名 (Android) | `com.didi.hlw` | — |
| 播放器核心 | IJKPlayer (FFmpeg) | FSPlayer (IJKPlayer fork) |
| 字幕渲染 | 自渲染 overlay (Timer 匹配) | 自渲染 UILabel overlay |
| 弹幕 | PlayerBarrageWidget + DanmakuManager | DanmakuManager (CADisplayLink) |
| 分轨音频 iOS | AVPlayer 串流 | AVPlayer 串流 |
| 分轨音频 Android | MediaPlayer + 速率微调同步 | — |

## 已完成里程碑

| 阶段 | 内容 | 状态 |
|------|------|:----:|
| M1 | m3u8 加密播放 + 广告系统 + 缩略图预览 + 性能优化 | ✅ |
| M2 | 音视频分轨同步播放 | ✅ |
| M4 | 多语言字幕 + 字幕样式 + 弹幕系统 + 轮询 | ✅ |

## 测试覆盖

| 类型 | Flutter SDK | iOS SDK |
|------|:-----------:|:-------:|
| Unit Tests | 18 | 27 |
| Integration Tests | 14 | 9 |
| Maestro E2E | 8 yaml | 7 yaml |

---

## Flutter SDK 串接

### 基本用法

```dart
ShortMvPlayer(
  info: {
    "source_240": "https://cdn.example.com/video.mp4",  // 必填
    "title": "视频标题",
    "cover": "https://cdn.example.com/cover.jpg",
    "is_buy": true,
    "isSpeed": 1,
  },
  isNeedBack: true,
)
```

### info Map 完整参数

| Key | 类型 | 必填 | 说明 |
|-----|------|:----:|------|
| `source_240` | String | ✅ | 视频 URL |
| `preview_url` | String | | 预览视频 URL（未购买时） |
| `title` | String | | 视频标题 |
| `cover` | String | | 封面图 URL |
| `is_buy` | bool | | 是否已购买 |
| `isSpeed` | int | | 倍速开关（1=开启） |
| `vtt_url` | String | | 缩略图雪碧图 VTT URL |
| `subtitle_url` | String | | 单字幕 URL（旧格式） |
| `subtitles` | List | | 多语言字幕列表 |
| `realtime_subtitle_url` | String | | WebSocket 实时字幕 URL |
| `is_encryption` | int | | 是否加密（0/1） |
| `isEncrypt` | bool | | 是否加密（旧格式） |
| `extra` | Map | | 扩展配置 |

### 加密视频

```dart
ShortMvPlayer(info: {
  "source_240": "https://cdn/encrypted.m3u8",
  "is_encryption": 1,
})
```

### 分轨音视频

```dart
ShortMvPlayer(info: {
  "source_240": "https://cdn/video.mp4",
  "extra": {"audioUrl": "https://cdn/audio.mp3"},
})
```

### 多语言字幕

```dart
ShortMvPlayer(info: {
  "source_240": "https://cdn/video.mp4",
  "subtitles": [
    {"lang": "zh", "label": "简体中文", "url": "https://cdn/zh.srt"},
    {"lang": "zh-tc", "label": "繁體中文", "url": "https://cdn/zh-tc.srt"},
    {"lang": "en", "label": "English", "url": "https://cdn/en.srt"},
  ],
})
// CC 按钮自动出现，点击弹出语言选择器
// 长按 CC 按钮调整字幕样式（字号/颜色/背景）
// 语言偏好自动记忆到 SharedPreferences
// 非标准 SRT 自动修复（缺序号、不完整时间戳）
```

### 广告系统

```dart
ShortMvPlayer(
  info: {"source_240": "https://cdn/video.mp4"},
  adData: videoAdData,  // VideoAdData，从后端 API 获取
)
```

### 缩略图预览

```dart
ShortMvPlayer(info: {
  "source_240": "https://cdn/video.mp4",
  "vtt_url": "https://cdn/sprites.vtt",
})
```

---

## iOS SDK 串接

### 基本用法

```swift
let playerContainer = IJKPlayerContainerView()
view.addSubview(playerContainer)
playerContainer.setVideoConfig(url: "https://cdn/video.mp4", useProxy: false)

playerContainer.onPlayerReady = {
    print("播放器就绪")
}
```

### 播放控制

```swift
playerContainer.play()
playerContainer.pause()
playerContainer.stop()
playerContainer.togglePlay()
playerContainer.seekTo(30000)        // 毫秒
playerContainer.setSpeed(1.5)
playerContainer.setLooping(true)

let isPlaying = playerContainer.isPlaying()
let position = playerContainer.getPosition()
let duration = playerContainer.getDuration()
```

### 分轨音视频

```swift
playerContainer.onPlayerReady = { [weak self] in
    self?.playerContainer.setExternalAudio(url: "https://cdn/audio.mp3")
}
playerContainer.setVideoConfig(url: "https://cdn/video.mp4", useProxy: false)
```

### 多语言字幕

```swift
playerContainer.setSubtitleTracks([
    .init(lang: "zh", label: "简体中文", url: "https://cdn/zh.srt"),
    .init(lang: "zh-tc", label: "繁體中文", url: "https://cdn/zh-tc.srt"),
    .init(lang: "en", label: "English", url: "https://cdn/en.srt"),
])
playerContainer.switchSubtitle(to: "zh")     // 切换
playerContainer.switchSubtitle(to: nil)      // 关闭
// 非标准 SRT 自动修复（两遍扫描法）
// 语言偏好自动记忆到 UserDefaults
```

### 字幕样式

```swift
playerContainer.applySubtitleStylePreset(.largeWhite)   // 22pt 白字+黑底
playerContainer.applySubtitleStylePreset(.mediumYellow)  // 18pt 黄字
playerContainer.applySubtitleStylePreset(.smallCyan)     // 14pt 青字
playerContainer.applySubtitleStylePreset(.defaultStyle)  // 16pt 白字

playerContainer.setSubtitleFontSize(20)
playerContainer.setSubtitleTextColor(.yellow)
playerContainer.setSubtitleBackgroundColor(.black.withAlphaComponent(0.5))
playerContainer.setSubtitleDelay(0.5)
```

### 弹幕系统

```swift
// 本地测试
let localSource = LocalDanmakuDataSource()
playerContainer.setDanmakuDataSource(localSource)

// 后端 API（轮询模式，每 30 秒预载）
let apiSource = APIDanmakuDataSource(baseURL: "https://api.example.com", pollingInterval: 30)
playerContainer.setDanmakuDataSource(apiSource)

playerContainer.startDanmakuSystem()
playerContainer.sendDanmaku(text: "太精彩了！") { result in ... }
playerContainer.setDanmakuEnabled(true/false)
playerContainer.clearDanmaku()

var settings = DanmakuSettings()
settings.opacity = 0.8
settings.displayLines = 3
playerContainer.updateDanmakuSettings(settings)
```

### 广告系统

```swift
playerContainer.showPrerollAd(config: prerollConfig)
playerContainer.skipPrerollAd()
playerContainer.showPauseAd(config: pauseConfig)
playerContainer.addMidrollAd(config: midrollConfig)
playerContainer.addOverlayAd(config: overlayConfig)
```

### 缩略图预览

```swift
if let vttURL = URL(string: "https://cdn/sprites.vtt") {
    playerContainer.setThumbnailMetadata(url: vttURL)
}
```

---

## 弹幕 API 接口

```
GET /danmu/list?video_id=123&from=0&to=60
→ [{"id":1, "time":5, "text":"哈哈", "color":"#fff"}]

POST /danmu/send
{"video_id":123, "time":15.2, "text":"太精彩了！", "color":"#ff0"}
```

获取策略：轮询模式，每 30 秒预载下一段（可配置），不使用 WebSocket。

---

## 测试用素材 URL

| 类型 | URL |
|------|-----|
| 1K 视频 | `https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_1k/TearsOfSteel_5min_1k.mp4` |
| 2K 视频 | `https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_2k/TearsOfSteel_5min_2k.mp4` |
| 分轨视频 | `https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_1k/video.mp4` |
| 分轨音频 | `https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_1k/audio.mp3` |
| 雪碧图 VTT | `https://dx-001-office.nhtekmaf.cc/video_thumbnail_package_1k/output_sprite.vtt` |
| 简体中文字幕 | `https://dx-001-office.nhtekmaf.cc/subtitle/tos.zh.srt` |
| 繁体中文字幕 | `https://dx-001-office.nhtekmaf.cc/subtitle/tos.zh-tc.srt` |
| 英文字幕 | `https://dx-001-office.nhtekmaf.cc/subtitle/tos.en.srt` |

---

## 开发周期

| 时间 | 事项 |
|------|------|
| 3/10 ~ 3/24 | M1: 加密播放 + 广告 + 缩略图 + 性能优化 |
| 3/25 ~ 4/03 | M2: 音视频分轨同步 |
| 4/07 ~ 4/14 | M4: 字幕/翻译/弹幕系统 |
| 4/18 ~ 4/20 | 弹幕联调（等后端交付） |
| 4/22 | 提测 |

## 注意事项

- Flutter 命令必须用 `fvm flutter` 前缀
- iOS SDK 需要 FSPlayer.xcframework（已内嵌）
- 字幕支持 SRT 和 WebVTT，非标准 SRT 自动修复
- 分轨音频 iOS 端用 AVPlayer 串流，Android 端用 MediaPlayer
- 弹幕采用轮询模式（每 30 秒预载），用户自己发的弹幕本地立即显示
- iOS SDK 用 XcodeGen 管理，`xcodegen generate` 后需手动注入 test target 到 scheme
