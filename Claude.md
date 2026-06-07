# Voice Input v3.3 — 项目文档

## 技术栈

- 纯 Swift，无 Xcode 项目文件，无 SwiftUI 视图生命周期
- SPM 目录结构（`Sources/VoiceInput/`），但**不用 swift build**，由 `build.sh` 调 swiftc 编译
- sherpa-onnx：动态库（dylib）+ bridging header 手动链接，没有 SPM 包
- macOS 原生 API：AppKit（NSStatusItem/NSPanel）、AVFoundation（录音）、CoreGraphics（模拟键盘）、Accessibility（CGEvent tap）
- 云端 ASR：阿里云 DashScope WebSocket 流式识别
- 本地 ASR：sherpa-onnx + SenseVoice Small 模型（~894MB），CoreML 加速

## 文件结构

```
/Users/paul/voice-input-v3/
├── Package.swift              # SPM 目录声明，不参与实际编译
├── build.sh                   # 编译 + 链接 + 签名 + 打包 DMG（唯一构建入口）
├── SherpaOnnx-Bridging-Header.h  # sherpa-onnx C API bridging header
├── SherpaOnnx.swift           # sherpa-onnx Swift wrapper（从 GitHub 下载）
├── logo.icns / menu-icon.png  # App 图标和菜单栏图标
├── Frameworks/
│   └── sherpa-onnx-dylib/     # sherpa-onnx 动态库（3 个 dylib）
│   └── sherpa-onnx-headers-v1.12.29/  # 头文件
├── Sources/VoiceInput/
│   ├── main.swift             # 入口：NSApplication + AppDelegate
│   ├── VoiceInputApp.swift    # AppDelegate：状态栏菜单、设置窗口、状态观察
│   ├── AppState.swift         # 核心状态机：权限检查、录音流程、双引擎调度
│   ├── Config.swift           # 配置管理、快捷键映射、数据目录
│   ├── HotkeyManager.swift    # 全局快捷键：CGEvent tap + 周期性权限检查
│   ├── AudioRecorder.swift    # 录音器：AVAudioEngine，16kHz 单声道输出
│   ├── Transcriber.swift      # 云端 ASR：DashScope WebSocket 流式识别
│   ├── LocalASRService.swift  # 本地 ASR：sherpa-onnx SenseVoice 推理 + 后处理
│   ├── ModelManager.swift     # 模型管理：下载/校验/删除/扫描本地模型（MD5 via ETag）
│   ├── TextInputService.swift # 剪贴板粘贴文本输入（保存/恢复剪贴板 + 模拟 Cmd+V）
│   ├── FloatingOverlay.swift  # 屏幕右上角药丸形浮动指示器（NSPanel）
│   ├── SettingsView.swift     # 设置界面 SwiftUI（NSPanel 容器，含快捷键录制器）
│   └── ClipboardHelper.swift  # 系统通知（AppleScript）
```

数据目录：`~/Library/Application Support/VoiceInput/`
- `config.json`：非敏感配置（API Key 不在此文件）
- `.env`：API Key（权限 0o600）
- `models/sensevoice-small/`：本地模型文件（默认）
- `models/<模型目录名>/`：其他本地模型（whisper-base、paraformer-zh 等）
- `recordings/`：保存的录音（WAV）

---

## 权限处理（重要，别搞砸）

这个 App 需要**两个**系统权限，缺任何一个都不会工作。之前的 bug 就是因为权限处理不当导致的。

### 1. 辅助功能权限（Accessibility）

**用途**：两个地方需要
- `HotkeyManager`：CGEvent tap 监听全局按键
- `TextInputService`：CGEvent 模拟 Cmd+V 粘贴文本

**处理逻辑**：

```
App 启动
  └─ AppState.setup()
       └─ checkAccessibilityPermission()
            ├─ AXIsProcessTrusted() == true → 正常
            └─ AXIsProcessTrusted() == false → 弹系统授权弹窗
                 （AXIsProcessTrustedWithOptions + kAXTrustedCheckOptionPrompt）
                 + 系统通知提醒用户去设置里开启

HotkeyManager.start()
  ├─ tryCreateTap() → 尝试创建 CGEvent tap
  │    ├─ 成功 → isTapActive = true，开始监听按键
  │    └─ 失败 → isTapActive = false，等待用户授权
  │
  └─ 启动 2 秒周期性检查（periodicCheck）
       ├─ AXIsProcessTrusted() == false → 如果 tap 还在，停掉它
       └─ AXIsProcessTrusted() == true → 检查 tap 是否有效
            ├─ 有效 → 正常
            └─ 无效 → 销毁旧 tap，重新创建
```

**关键点**：
- **不能只在启动时检查一次**。用户可能在 App 启动后才去设置里开权限，所以 HotkeyManager 必须周期性轮询（每 2 秒）
- CGEvent tap 可能被系统禁用（`tapDisabledByTimeout` / `tapDisabledByUserInput`），回调里要重新 enable
- 之前没做周期性检查，用户授权后必须重启 App 才生效，这就是"有时候退出软件再打开有用"的原因

### 2. 麦克风权限（Microphone）

**用途**：AVAudioEngine 录音

**处理逻辑**：

```
App 启动
  └─ AppState.setup()
       └─ requestMicrophonePermission()
            ├─ .authorized → 正常
            ├─ .notDetermined → 弹系统授权弹窗
            └─ .denied → 系统通知提醒用户去设置里开

每次按下快捷键录音
  └─ startRecording()
       └─ ensureMicrophonePermission()  ← 二次检查
            ├─ .authorized → 继续
            ├─ .notDetermined → 弹窗 + 返回 false（等用户点完再按）
            └─ .denied → 通知 + 返回 false
```

**关键点**：
- 启动时弹一次权限弹窗，但录音前还要再检查一次（因为用户可能事后撤销了权限）
- `ensureMicrophonePermission()` 返回 Bool，作为录音的前置条件

### 3. 代码签名（这是之前权限不稳定的核心原因）

**问题**：swiftc 编译出的二进制只有 linker-level 签名，不包含 bundle identifier 绑定。macOS 的 TCC（隐私权限系统）依赖应用签名来识别 App 身份。签名不对会导致：
- 重装后权限丢失（系统认为是"新"App）
- 权限状态不稳定（有时候能用有时候不能用）

**修复**：`build.sh` 第 165-167 行

```bash
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
```

- `--deep`：递归签名 Frameworks 里的 dylib
- `--sign -`：本机临时签名（ad-hoc），不依赖开发者证书
- 签名必须在复制完所有资源（dylib、图标、Info.plist）之后做
- **每次 build 都必须签名**，不能跳过

### 4. Info.plist 权限声明

三个 Usage Description 必须有，否则系统不会弹权限弹窗：

```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>语音输入需要语音识别权限来转写您的语音</string>
<key>NSMicrophoneUsageDescription</key>
<string>语音输入需要麦克风权限来录制您的语音</string>
<key>NSAccessibilityUsageDescription</key>
<string>语音输入需要辅助功能权限来模拟键盘输入</string>
```

### 权限故障排查清单

如果用户反馈"按了没反应"：
1. 检查 App 是否被 codesign 签过（`codesign -dvvv VoiceInput.app`）
2. 检查辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能
3. 检查麦克风权限：系统设置 → 隐私与安全性 → 麦克风
4. 看 NSLog：`log stream --predicate 'process == "VoiceInput"' --level debug`
5. 重点关注 `[VI] CGEvent tap 创建失败` 和 `[VI] 麦克风权限: 未授权`

---

## 核心流程

### 录音流程（双引擎）

```
用户按下快捷键（HotkeyManager 监听 CGEvent）
  │
  ├─ ensureMicrophonePermission() 检查麦克风权限
  │
  ├─ isRecording=true, show .recording overlay
  │
  ├─ 云端模式：
  │    ├─ transcriber.startLiveRecognition() 建立 WebSocket
  │    ├─ audioRecorder.onBuffer → transcriber.appendBuffer() 实时发送
  │    └─ FloatingOverlay 显示 partial 文本
  │
  └─ 本地模式：
       └─ 只录音，不建 WebSocket，不显示 partial 文本

用户松开快捷键
  │
  ├─ stopAndGetResults() 停止录音，取出 Float32 音频数据
  ├─ show .thinking overlay
  │
  ├─ 云端：processCloud() → stopLiveRecognition() 拿最终结果
  │    └─ 失败 + 本地模型可用 → processLocal() fallback
  │
  ├─ 本地：processLocal() → loadModel() + transcribe()
  │    └─ 失败 + 有 API Key → processCloud() fallback
  │
  ├─ hide overlay → 等 50ms（让焦点回到目标应用）
  └─ TextInputService.pasteText() 剪贴板粘贴

ESC 取消：录音中或 thinking 阶段均可取消
```

### 剪贴板粘贴流程

```
TextInputService.pasteText(text)
  1. 检查 AXIsProcessTrusted()（无权限直接 throw）
  2. 保存剪贴板所有类型的数据（不只是 string，还有图片/文件/富文本）
  3. 清空剪贴板 → 写入识别文本
  4. 等 30ms → 验证剪贴板内容是否匹配
  5. CGEvent 模拟 Cmd+V
  6. 等 150ms
  7. 恢复原剪贴板内容（所有类型）
```

### 浮动指示器

- NSPanel，无边框，不抢焦点，鼠标事件穿透
- `.floating` 层级，所有 Space 和全屏可见
- 屏幕右上角（跟随鼠标所在屏幕）
- 三种状态：recording（波形/文本）、thinking（药丸形进度填充）、idle（隐藏）
- thinking 进度：整个药丸形状作为进度条，白色半透明从左往右填充（被圆角裁剪），渐近曲线 `1 - 1/(1 + t*2.5)` 上限 95%
- CVDisplayLink 驱动波形和进度条动画

### 模型管理

- 模型根目录：`~/Library/Application Support/VoiceInput/models/`
- 支持 6 种模型（`ModelManager.supportedModels`）：Whisper Base/Small/Medium/Large-v3、Paraformer-zh、SenseVoice Small
- 每个模型一个子目录，内含各自的 onnx 文件 + tokens.txt
- 设置界面下拉框显示本地已有模型，下方列出全部 6 种模型及大小供用户手动下载
- 下载（SenseVoice Small）：`URLSession.bytes` 逐块读取，写 `.tmp` 文件，完成后 rename
- 校验：MD5 via CommonCrypto，比对阿里云 OSS 返回的 ETag
- 最小文件检查：model.onnx 必须 >= 100MB，否则视为损坏
- 支持 HTTP 重定向（最多 5 次）
- `scanLocalModels()` 扫描所有 supportedModels 的文件完整性

### 本地 ASR 后处理

1. 清理 SenseVoice 标签：正则 `<\|[^|]*\|>` → 空
2. 单行文本：去掉末尾句号
3. CJK 空格：中日韩字符与英文/数字之间加空格（可配置）

---

## 构建和打包

**唯一构建入口**：`bash build.sh`

```
1. 检查 sherpa-onnx dylib 是否存在
2. 下载 SherpaOnnx.swift wrapper（如不存在）
3. 下载 bridging header（如不存在）
4. swiftc 编译（-O, -DSHERPA_ONNX, 指定 SDK, bridging header, 链接 dylib）
5. 打包 .app（二进制 + Frameworks + 图标 + Info.plist）
6. codesign --force --deep --sign -（关键！见权限部分）
7. hdiutil 打包 DMG
```

**编译标志**：
- `-DSHERPA_ONNX`：启用 LocalASRService 中的 sherpa-onnx 代码（SPM 编译时不定义，方法返回空）
- `-import-objc-header SherpaOnnx-Bridging-Header.h`：引入 C API
- `-Xlinker -rpath -Xlinker @executable_path/../Frameworks`：运行时找 dylib
- `-Xlinker -undefined -Xlinker dynamic_lookup`：允许 sherpa-onnx 符号运行时解析

**链接的框架**：CoreML, AVFoundation, AppKit, CoreAudio, CoreMedia, AudioToolbox, Carbon, Security

---

## 技术细节备忘

### CGEvent tap（HotkeyManager）

- 使用 `.cgSessionEventTap` + `.listenOnly`（只监听，不拦截）
- `self` 通过 `Unmanaged.passRetained` 传给 C 回调，在 `invalidateTap()` 时 release
- `flagsChanged` 事件处理修饰键（Command/Option/Control/Shift），区分左右键
- 键码 54 = 右 Command（默认快捷键）

### 状态栏菜单

- `NSApp.setActivationPolicy(.accessory)`：不显示 Dock 图标（LSUIElement=true）
- 菜单项：状态文字、当前模式、设置、退出
- 设置窗口是独立的 NSPanel（不是 NSWindow），不显示在 Dock 里

### 配置兼容

- v2 → v3：`polish_*` 字段读取时静默忽略
- API Key 存 `.env`（权限 0o600），不进 config.json
- 首次运行自动从 `~/voice-input-v2/` 迁移旧数据（一次性，标记文件 `.migrated`）
- `localModel` 字段：本地模型目录名，默认 `sensevoice-small`

### 快捷键录制器（RecorderView）

- NSViewRepresentable 嵌入 SwiftUI Form
- 点击进入录音状态，再次点击取消
- `flagsChanged` 追踪修饰键，`keyDown` 追踪普通键
- 所有修饰键松开时 finalize（不依赖普通键 keyUp，防 macOS 吞事件）
- ESC 取消录音

### 通知

- 使用 `osascript -e 'display notification ...'` 发系统通知
- 不用 UserNotifications 框架（避免额外的权限弹窗）

---

## 参考文件

| 用途 | 文件路径 |
|------|----------|
| v2 可复用代码 | /Users/paul/voice-input-v2/Sources/VoiceInput/ |
