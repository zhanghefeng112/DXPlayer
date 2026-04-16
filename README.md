# DXPlayerSDK (iOS 播放器 SDK)

原生 iOS 自研视频播放器 SDK，支持 m3u8 加密播放、广告系统、音视频分轨、多语言字幕、弹幕系统。

---

## 一、技术选型

| 项目 | 选型 | 原因 |
|------|------|------|
| 语言 | Swift 5.0 | 原生性能，Apple 生态 |
| 最低版本 | iOS 15.0 | 覆盖 95%+ 设备 |
| 播放器核心 | FSPlayer (IJKPlayer fork) | FFmpeg-based，支持 m3u8/HLS/AES、硬件解码、字幕渲染 |
| 项目管理 | XcodeGen (project.yml) | 避免 pbxproj 冲突，声明式配置 |
| 弹幕系统 | 自研 DanmakuManager | CADisplayLink 动画、轨道碰撞检测、View 复用池 |
| 字幕渲染 | 自渲染 UILabel overlay | FSPlayer 原生字幕对非标准 SRT 兼容差，改自渲染 |
| 缩略图 | ThumbnailPreviewManager | WebVTT + 雪碧图解析、懒加载 |
| 分轨音频 | AVPlayer 串流 | 不需下载完整文件即可播放，降低首帧延迟 |

---

## 二、版本信息

| 项目 | 值 |
|------|------|
| 仓库 | `git@foya:china/gb_ios.git` |
| 分支 | `master` |
| Bundle ID | `com.dxplayer.www` |
| SDK version | 0.0.1 |
| Swift 版本 | 5.0 |
| 最低部署版本 | iOS 15.0 |
| Team ID | BQ6A4VMVJF |

---

## 三、已完成功能

| 里程碑 | 功能 | 状态 |
|--------|------|:----:|
| M1 | m3u8 HLS 加密播放 | ✅ |
| M1 | 广告系统（片头/中插/暂停/浮层） | ✅ |
| M1 | 进度条缩略图预览（WebVTT + 雪碧图） | ✅ |
| M1 | 性能优化（降温、帧率控制、硬解） | ✅ |
| M2 | 音视频分轨同步播放 | ✅ |
| M4 | 多语言字幕切换（zh/zh-tc/en） | ✅ |
| M4 | 字幕样式调整（字号/颜色/背景/预设） | ✅ |
| M4 | SRT 非标准格式自动修复 | ✅ |
| M4 | 内嵌字幕（m3u8 SUBTITLES） | ✅ |
| M4 | 弹幕系统（显示/发送/设置/过滤） | ✅ |
| M4 | 弹幕 API 轮询预加载 | ✅ |
| M4 | 字幕语言偏好记忆 | ✅ |

---

## 四、公开 API（74 个方法）

### 播放控制

```swift
playerContainer.setVideoConfig(url: String, useProxy: Bool)
playerContainer.play()
playerContainer.pause()
playerContainer.stop()
playerContainer.togglePlay()
playerContainer.seekTo(_ ms: Int)
playerContainer.setSpeed(_ speed: Float)
playerContainer.setLooping(_ looping: Bool)
playerContainer.isPlaying() -> Bool
playerContainer.getPosition() -> TimeInterval
playerContainer.getDuration() -> TimeInterval
```

### 分轨音视频

```swift
playerContainer.setExternalAudio(url: String)
```

### 多语言字幕

```swift
playerContainer.setSubtitleTracks([
    .init(lang: "zh", label: "简体中文", url: "https://cdn/zh.srt"),
    .init(lang: "en", label: "English", url: "https://cdn/en.srt"),
])
playerContainer.switchSubtitle(to: "zh")      // 切换语言
playerContainer.switchSubtitle(to: nil)        // 关闭字幕
playerContainer.getCurrentSubtitleLang()       // 获取当前语言
playerContainer.getSubtitleTracks()            // 获取字幕列表
```

### 字幕样式

```swift
playerContainer.applySubtitleStylePreset(.largeWhite)   // 22pt 白字+黑底
playerContainer.applySubtitleStylePreset(.mediumYellow)  // 18pt 黄字
playerContainer.applySubtitleStylePreset(.smallCyan)     // 14pt 青字
playerContainer.applySubtitleStylePreset(.defaultStyle)  // 16pt 白字
playerContainer.setSubtitleFontSize(20)
playerContainer.setSubtitleTextColor(.yellow)
playerContainer.setSubtitleDelay(0.5)   // 延迟 +0.5 秒
```

### 弹幕系统

```swift
// 本地测试
let localSource = LocalDanmakuDataSource()
playerContainer.setDanmakuDataSource(localSource)

// 后端 API（轮询）
let apiSource = APIDanmakuDataSource(baseURL: "https://api.example.com", pollingInterval: 30)
playerContainer.setDanmakuDataSource(apiSource)

playerContainer.startDanmakuSystem()
playerContainer.sendDanmaku(text: "太精彩了！") { result in ... }
playerContainer.setDanmakuEnabled(true/false)
playerContainer.clearDanmaku()
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
playerContainer.setThumbnailMetadata(url: vttURL)
```

---

## 五、跨端 API 接口规范

### 弹幕 API

```
GET /danmu/list?video_id=123&from=0&to=60
→ [{"id":1, "time":5, "text":"哈哈", "color":"#fff"}]

POST /danmu/send
{"video_id":123, "time":15.2, "text":"太精彩了！", "color":"#ff0"}
```

弹幕获取策略：轮询模式，每 30 秒预载下一段。

---

## 六、目前遇到的问题

| # | 问题 | 状态 |
|---|------|------|
| 1 | 弹幕后端 API 未交付 | ⏳ 预计 4/18 |
| 2 | 实时字幕（直播）需求待确认 | ⏳ 等待 |

---

## 七、开发周期

| 时间 | 事项 |
|------|------|
| 3/10 ~ 3/24 | M1: 加密播放 + 广告 + 缩略图 + 性能优化 |
| 3/25 ~ 4/03 | M2: 音视频分轨同步 |
| 4/07 ~ 4/14 | M4: 字幕/翻译/弹幕系统 |
| 4/18 ~ 4/20 | 弹幕联调 |
| 4/22 | 提测 |

---

## 八、测试覆盖

| 类型 | 数量 |
|------|------|
| XCTest Unit Tests | 27 |
| XCTest Integration Tests | 9 |
| Maestro E2E | 7 个 yaml |

---

## 九、源码结构

```
DXPlayerSDK/Sources/
├── IJKPlayerContainerView.swift       # 主播放器容器 (74 个 public API)
├── PlayerControlView.swift            # 控件层 UI
├── PlayerControlViewModel.swift       # 控件 ViewModel
├── PlayerSettingsMenuView.swift       # 设置菜单
├── SubtitleManager.swift              # 字幕管理（加载/样式/延迟）
├── AdManager.swift                    # 广告管理（片头/中插/暂停/浮层）
├── Decryptor.swift                    # m3u8 加密解密
├── ProxyServer.swift                  # 本地代理服务器
├── PlaybackSpeedManager.swift         # 倍速管理
├── AspectRatioManager.swift           # 画面比例
├── Danmaku/                           # 弹幕系统
│   ├── DanmakuManager.swift           # 弹幕管理器
│   ├── DanmakuOverlay.swift           # 弹幕渲染层
│   ├── DanmakuModels.swift            # 数据模型 + 设置
│   ├── DanmakuDataSource.swift        # 数据源协议
│   ├── APIDanmakuDataSource.swift     # 后端 API 轮询数据源
│   ├── LocalDanmakuDataSource.swift   # 本地测试数据源
│   ├── DanmakuControlView.swift       # 弹幕控件（开关/输入/发送）
│   ├── DanmakuSettingsView.swift      # 弹幕设置面板
│   └── DanmakuLabel.swift             # 弹幕文字渲染
└── ThumbnailPreview/                  # 缩略图预览
    ├── ThumbnailPreviewManager.swift
    ├── ThumbnailSpriteParser.swift
    ├── ThumbnailPreviewView.swift
    └── ThumbnailCache.swift

DemoApp/
└── ViewController.swift               # Demo 应用

DXPlayerSDKTests/
├── SplitTrackTests.swift              # 分轨测试
├── M4SubtitleDanmakuTests.swift       # M4 字幕/弹幕测试
└── IntegrationTests.swift             # 集成测试

.maestro/                              # E2E 测试脚本
```

---

## 十、开发命令

```bash
# 生成 Xcode 项目
xcodegen generate

# 构建
xcodebuild build -scheme DXPlayerSDKDemoApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# 测试
xcodebuild test -scheme DXPlayerSDKDemoApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:DXPlayerSDKTests

# Archive（Release）
xcodebuild -project DXPlayerSDKDemo.xcodeproj -scheme DXPlayerSDKDemoApp -sdk iphoneos -configuration Release -archivePath /tmp/DXPlayerSDKDemo.xcarchive archive
```
