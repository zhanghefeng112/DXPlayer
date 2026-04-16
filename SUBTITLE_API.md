# 字幕 API 集成指南

## 概述

DXPlayerSDK 字幕系统支持两种模式：
1. **Mock 模式**（当前）：使用硬编码的字幕数据
2. **API 模式**（未来）：从远程服务器下载字幕

## 当前实现（Mock 模式）

### 代码位置
`DemoApp/ViewController.swift` - `playVideo()` 方法

```swift
// 目前使用 mock 字幕
self?.loadSintelSubtitleMock()
```

### Mock 字幕数据
- 位置：`loadSintelSubtitleMock()` 方法
- 格式：SRT (硬编码在代码中)
- 用途：离线测试，无需网络请求

---

## 迁移到 API 模式

### 步骤 1：准备 API 端点

确保你的字幕 API 返回以下格式之一：
- **SRT** (推荐)
- **VTT** (WebVTT)
- **ASS/SSA** (高级字幕)

API 示例：
```
GET https://api.example.com/subtitles/{video_id}.srt
Response: SRT 格式的纯文本字幕内容
```

### 步骤 2：修改代码

在 `ViewController.swift` 的 `playVideo()` 方法中：

```swift
// 延迟加载测试字幕（确保播放器已完全初始化并开始播放）
DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
    print("⏰ 开始加载字幕...")

    // 🔥 取消注释下面两行，启用 API 下载
    let subtitleURL = "https://api.example.com/subtitles/sintel_zh.srt"
    self?.loadSubtitleFromURL(subtitleURL)

    // 🔥 注释掉 Mock 模式
    // self?.loadSintelSubtitleMock()
}
```

### 步骤 3：动态字幕 URL

如果字幕 URL 根据视频动态变化：

```swift
private func playVideo(useProxy: Bool, videoId: String? = nil) {
    let testVideoURL = "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4"

    playerContainer.setTitle(useProxy ? "🟢 代理播放模式" : "⚪️ 直接播放模式")
    playerContainer.setVideoConfig(url: testVideoURL, useProxy: useProxy)
    playerContainer.play()

    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
        // 根据 videoId 构建字幕 URL
        let videoId = videoId ?? "sintel"
        let subtitleURL = "https://api.example.com/subtitles/\(videoId)_zh.srt"
        self?.loadSubtitleFromURL(subtitleURL)
    }
}
```

---

## API 字幕下载方法详解

### 方法签名
```swift
private func loadSubtitleFromURL(_ urlString: String)
```

### 功能特性
- ✅ 异步下载（不阻塞主线程）
- ✅ 自动识别文件扩展名（.srt, .vtt, .ass）
- ✅ 错误处理和日志输出
- ✅ 自动保存到临时目录
- ✅ 下载完成后弹出提示

### 日志输出
```
📝 [字幕] 开始从 URL 下载字幕: https://api.example.com/subtitles/sintel_zh.srt
✅ [字幕] 下载成功，大小: 1234 字节
📝 [字幕] 保存到临时文件: /tmp/downloaded_subtitle_1234567890.srt
✅ [字幕] 字幕加载成功
```

### 错误处理
- URL 格式错误
- 网络请求失败
- 数据解析失败（非 UTF-8 编码）
- 文件保存失败

---

## API 响应格式要求

### SRT 格式示例
```srt
1
00:01:47,250 --> 00:01:50,500
这把刀有一段黑暗的历史

2
00:01:51,800 --> 00:01:55,800
它沾满了太多无辜者的鲜血
```

### VTT 格式示例
```vtt
WEBVTT

1
00:01:47.250 --> 00:01:50.500
这把刀有一段黑暗的历史

2
00:01:51.800 --> 00:01:55.800
它沾满了太多无辜者的鲜血
```

### 重要提示
- ✅ 必须是纯文本格式（不能是 JSON 包装）
- ✅ 必须使用 UTF-8 编码
- ✅ Content-Type 建议设置为 `text/plain` 或 `text/vtt`
- ⚠️ 时间戳格式必须正确（SRT 用逗号，VTT 用点号）

---

## 测试 API 集成

### 方法 1：使用公共字幕 URL
```swift
// GitHub raw 文件
let subtitleURL = "https://raw.githubusercontent.com/username/repo/master/subtitles/sintel_zh.srt"
self?.loadSubtitleFromURL(subtitleURL)
```

### 方法 2：使用本地服务器
```bash
# 启动简单 HTTP 服务器
cd /path/to/subtitles
python3 -m http.server 8000

# 访问
# http://localhost:8000/sintel_zh.srt
```

```swift
let subtitleURL = "http://localhost:8000/sintel_zh.srt"
self?.loadSubtitleFromURL(subtitleURL)
```

---

## 进阶：添加认证和请求头

如果 API 需要认证，修改 `loadSubtitleFromURL()` 方法：

```swift
private func loadSubtitleFromURL(_ urlString: String, authToken: String? = nil) {
    guard let url = URL(string: urlString) else {
        print("❌ [字幕] URL 格式错误")
        return
    }

    var request = URLRequest(url: url)

    // 添加认证头
    if let token = authToken {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // 添加其他请求头
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
        // ... 其余代码保持不变
    }

    task.resume()
}
```

---

## 性能优化建议

### 1. 字幕缓存
```swift
// 缓存已下载的字幕
private var subtitleCache: [String: URL] = [:]

private func loadSubtitleFromURL(_ urlString: String) {
    // 检查缓存
    if let cachedURL = subtitleCache[urlString] {
        print("📦 [字幕] 使用缓存字幕")
        let success = playerContainer.loadSubtitle(url: cachedURL, autoActivate: true)
        return
    }

    // 下载并缓存
    // ...
}
```

### 2. 超时控制
```swift
var request = URLRequest(url: url)
request.timeoutInterval = 10.0  // 10秒超时
```

### 3. 后台下载（大文件）
```swift
let config = URLSessionConfiguration.background(withIdentifier: "com.app.subtitle.download")
let session = URLSession(configuration: config)
```

---

## 总结

### 当前状态
✅ Mock 模式运行正常
✅ API 下载功能已实现
⏳ 等待切换到 API 模式

### 切换步骤
1. 准备字幕 API 端点
2. 取消注释 `loadSubtitleFromURL()` 调用
3. 注释掉 `loadSintelSubtitleMock()` 调用
4. 测试并验证

### 支持
- 支持多种字幕格式（SRT, VTT, ASS）
- 自动文件类型识别
- 完整的错误处理
- 用户友好的提示信息
