# DXPlayerSDK 新功能验证指南

## 功能概览

本项目新增了三个播放器功能模块：
1. **字幕管理** (SubtitleManager)
2. **播放速度控制** (PlaybackSpeedManager)
3. **画面比例调整** (AspectRatioManager)

---

## 验证步骤

### 方法一：使用 Xcode 运行 Demo 应用

#### 1. 打开项目
```bash
cd /Users/sean/Documents/proj_foya/DXPlayerSDKDemo
open DXPlayerSDKDemo.xcodeproj
```

#### 2. 运行 Demo 应用
- 在 Xcode 中选择 Scheme: **DXPlayerSDKDemoApp**
- 选择目标设备：iPhone 模拟器（推荐 iPhone 14 或以上）
- 点击 Run (⌘R) 或点击播放按钮

#### 3. 测试界面说明

Demo 应用启动后，会看到以下界面：

**视频播放区域**
- 顶部显示播放器（自动播放测试视频）

**功能测试按钮**（从下往上）：
1. 🔵 **启用代理播放** - 切换代理播放模式
2. 📊 **查看代理统计** - 显示代理服务器统计信息
3. 📝 **字幕测试** - 测试字幕功能
4. ⚡️ **播放速度** - 测试播放速度调整
5. 📐 **画面比例** - 测试画面比例设置

---

### 功能测试详细步骤

#### ✅ 字幕功能测试

**点击 "📝 字幕测试" 按钮**，会弹出菜单：

1. **加载测试字幕**
   - 选择后会自动创建并加载测试字幕
   - 播放视频时会看到字幕显示
   - 测试字幕内容：
     ```
     00:00-00:03: 这是第一条测试字幕
     00:03-00:06: DXPlayerSDK 字幕功能演示
     00:06-00:10: 支持 SRT、VTT、ASS 等格式
     ```

2. **应用大号白色样式**
   - 字幕会变为大号白色显示（1.5x 缩放）

3. **应用中号黄色样式**
   - 字幕会变为中号黄色显示（1.2x 缩放）

4. **字幕延迟 +0.5秒**
   - 字幕显示延迟 0.5 秒

5. **字幕提前 -0.5秒**
   - 字幕显示提前 0.5 秒

6. **移除字幕**
   - 关闭字幕显示

**验证点**：
- ✅ 字幕能正确加载和显示
- ✅ 字幕样式可以切换（大小、颜色）
- ✅ 字幕延迟可以调整
- ✅ 可以关闭字幕

---

#### ✅ 播放速度功能测试

**点击 "⚡️ 播放速度" 按钮**，会弹出菜单显示当前速度：

**速度选项**：
1. **0.5x 慢速** - 慢速播放
2. **0.75x 较慢** - 较慢播放
3. **1.0x 正常** ✓ - 正常速度（默认）
4. **1.25x 较快** - 较快播放
5. **1.5x 快速** - 快速播放
6. **2.0x 很快** - 很快播放
7. **切换到下一个速度** - 循环切换
8. **重置为正常速度** - 恢复 1.0x

**验证步骤**：
1. 选择 **2.0x 很快**
   - 观察视频播放速度明显加快
   - 音频也会相应加速
2. 选择 **0.5x 慢速**
   - 观察视频播放速度明显减慢
3. 点击 **切换到下一个速度**
   - 速度会循环切换到下一档
4. 重新打开菜单
   - 当前速度会显示 ✓ 标记

**验证点**：
- ✅ 播放速度可以实时调整
- ✅ 所有 6 档速度都能正常工作
- ✅ 速度设置会保存（重启应用后仍保持）
- ✅ 当前速度有 ✓ 标记指示

---

#### ✅ 画面比例功能测试

**点击 "📐 画面比例" 按钮**，会弹出菜单显示当前比例：

**比例选项**：
1. **适应屏幕** ✓ - 保持原始比例，可能有黑边（默认）
2. **填充屏幕** - 填满屏幕，可能裁剪
3. **拉伸填充** - 拉伸填满，不保持比例
4. **16:9** - 强制 16:9 比例
5. **4:3** - 强制 4:3 比例
6. **1:1** - 强制 1:1 方形比例
7. **切换到下一个比例** - 循环切换
8. **重置为适应屏幕** - 恢复默认

**验证步骤**：
1. 选择 **填充屏幕**
   - 观察视频填满播放器区域（可能裁剪边缘）
2. 选择 **拉伸填充**
   - 观察视频被拉伸填满（画面可能变形）
3. 选择 **16:9**
   - 观察视频以 16:9 比例显示
4. 选择 **4:3**
   - 观察视频以 4:3 比例显示（有黑边）
5. 点击 **切换到下一个比例**
   - 比例会循环切换

**验证点**：
- ✅ 画面比例可以实时调整
- ✅ 所有 6 种比例模式都能正常工作
- ✅ 比例设置会保存（重启应用后仍保持）
- ✅ 当前比例有 ✓ 标记指示
- ✅ 画面显示符合选择的比例模式

---

## 方法二：代码审查验证

### 1. 检查核心文件

```bash
# 进入项目目录
cd /Users/sean/Documents/proj_foya/DXPlayerSDKDemo

# 查看三个管理器文件
ls -lh DXPlayerSDK/Sources/*Manager.swift

# 应该看到：
# SubtitleManager.swift      (10K)
# PlaybackSpeedManager.swift (5.5K)
# AspectRatioManager.swift   (5.5K)
```

### 2. 验证集成到播放器容器

```bash
# 检查 IJKPlayerContainerView 是否集成了三个管理器
grep -n "Manager?" DXPlayerSDK/Sources/IJKPlayerContainerView.swift
```

应该看到三个管理器属性定义：
- Line 26: `private var subtitleManager: SubtitleManager?`
- Line 27: `private var playbackSpeedManager: PlaybackSpeedManager?`
- Line 28: `private var aspectRatioManager: AspectRatioManager?`

### 3. 验证 Demo UI 集成

```bash
# 检查 ViewController 是否添加了测试按钮
grep -n "Button!" DemoApp/ViewController.swift
```

应该看到：
- `private var subtitleButton: UIButton!`
- `private var speedButton: UIButton!`
- `private var aspectRatioButton: UIButton!`

### 4. 验证编译通过

```bash
# 编译项目
xcodebuild -project DXPlayerSDKDemo.xcodeproj \
  -scheme DXPlayerSDK \
  -sdk iphonesimulator \
  -configuration Debug \
  build
```

应该看到：`** BUILD SUCCEEDED **`

---

## 方法三：查看 Git 提交历史

```bash
cd /Users/sean/Documents/proj_foya/DXPlayerSDKDemo

# 查看提交历史
git log --oneline

# 应该看到 4 个提交：
# 3674372 添加画面比例功能（AspectRatioManager）
# e3f880f 添加倍数播放功能（PlaybackSpeedManager）
# 2cd0c55 添加字幕功能（SubtitleManager）
# e0c8762 初始提交：DXPlayerSDK 代理播放功能

# 查看每个功能的详细改动
git show 2cd0c55  # 字幕功能
git show e3f880f  # 播放速度
git show 3674372  # 画面比例
```

---

## 常见问题

### Q1: 模拟器无法运行怎么办？
**A**: 确保已安装 Xcode 和 iOS 模拟器，选择 iPhone 14 或更新的模拟器。

### Q2: 字幕没有显示？
**A**: 
1. 确保已点击"加载测试字幕"
2. 视频播放到对应时间才会显示字幕（0-10秒）
3. 检查字幕样式是否被设置为透明

### Q3: 速度调整没有效果？
**A**: 
1. 确保视频正在播放
2. FSPlayer 支持 0.5x - 2.0x 速度范围
3. 检查控制台日志确认速度已设置

### Q4: 画面比例没有变化？
**A**:
1. 不同比例在不同视频源上效果可能不明显
2. 尝试"填充屏幕"和"拉伸填充"，效果最明显
3. 建议使用非 16:9 的视频测试 4:3 和 1:1 比例

### Q5: 如何查看日志？
**A**: 
在 Xcode 中运行时，打开 Console（⌘⇧Y），可以看到详细的功能日志：
- `⚡️ [播放速度] 设置为: xxx`
- `📐 [画面比例] 设置为: xxx`
- `✅ [字幕] 加载并激活: xxx`

---

## 功能 API 文档

### SubtitleManager API
```swift
// 加载字幕
playerContainer.loadSubtitle(url: URL, autoActivate: true)

// 配置字幕样式
playerContainer.configureSubtitleStyle(
    scale: 1.0,              // 缩放
    bottomMargin: 0.05,      // 底部边距
    fontName: "Arial",       // 字体
    textColor: 0xFFFFFF00,   // 文字颜色
    outlineWidth: 2.0,       // 边框宽度
    outlineColor: 0x00000000 // 边框颜色
)

// 设置字幕延迟
playerContainer.setSubtitleDelay(0.5) // +0.5秒
```

### PlaybackSpeedManager API
```swift
// 设置播放速度
playerContainer.setSpeed(1.5) // 1.5x

// 获取当前速度
let speed = playerContainer.getSpeed()

// 切换到下一个速度
playerContainer.switchToNextPlaybackSpeed()

// 重置为正常速度
playerContainer.resetPlaybackSpeed()
```

### AspectRatioManager API
```swift
// 设置画面比例
playerContainer.setAspectRatio(.fill)

// 获取当前比例
let mode = playerContainer.getCurrentAspectRatio()

// 切换到下一个比例
playerContainer.switchToNextAspectRatio()

// 重置为适应屏幕
playerContainer.resetAspectRatio()
```

---

## 总结

完成以上任一验证方法，即可确认三个功能已完整实作：

✅ **字幕功能** - 支持多格式字幕、样式配置、延迟调整  
✅ **播放速度** - 支持 0.5x-2.0x 六档速度、循环切换  
✅ **画面比例** - 支持 6 种比例模式、实时调整  

所有功能均：
- 完整集成到 IJKPlayerContainerView
- 提供公共 API 调用
- 包含 Demo 测试界面
- 支持设置持久化
- 编译通过无错误
