# Voice Input v3 — 设计文档

## 背景

参考竞品 Typeoff，将 Voice Input v2 重构为 v3。核心改动：双引擎 ASR（云端 + 本地）、剪贴板粘贴替代 AX 文本写入、药丸形浮动指示器。去掉润色功能。保持原生 Swift + SPM 技术栈。

## 文件结构

```
/Users/paul/voice-input-v3/
├── Package.swift
├── build.sh                    # 编译 + 链接 sherpa-onnx + 打包
├── SherpaOnnx-Bridging-Header.h
├── SherpaOnnx.swift            # 从 sherpa-onnx 项目复制
├── logo.icns / menu-icon.png   # 从 v2 复制
├── Sources/VoiceInput/
│   ├── main.swift              # 保留不变
│   ├── VoiceInputApp.swift     # 微调：去掉润色相关状态
│   ├── AppState.swift          # 重构：双引擎 ASR + 剪贴板粘贴
│   ├── Config.swift            # 重构：去掉润色字段，加 asrMode/cjkSpacing
│   ├── HotkeyManager.swift     # 保留不变
│   ├── AudioRecorder.swift     # 修改：新增 getFloat32Samples() 方法
│   ├── Transcriber.swift       # 保留不变（云端 DashScope）
│   ├── LocalASRService.swift   # 新增：sherpa-onnx SenseVoice 本地识别
│   ├── ModelManager.swift      # 新增：模型下载/校验/管理
│   ├── TextInputService.swift  # 新增：剪贴板粘贴文本输入
│   ├── FloatingOverlay.swift   # 完全重写：底部居中药丸形指示器
│   ├── SettingsView.swift      # 重新设计：2 栏（基础 + 识别）
│   └── ClipboardHelper.swift   # 保留不变
```

删除的文件：TextPolisher.swift、TextStreamer.swift、CaretPosition.swift

---

## 实现阶段

### 阶段 1：基础搭建

创建项目目录，从 v2 复制可复用的文件，创建 Package.swift。

Package.swift：和 v2 基本相同（纯 SPM），sherpa-onnx 通过 build.sh 手动链接（它没有 SPM 包，提供的是 xcframework + C API + Swift wrapper 文件）。

Config.swift 重构：
- 删除字段：polishEnabled、polishType、polishApiUrl、polishApiKey、polishModel
- 新增字段：asrMode（"cloud" / "local"，默认 "cloud"）、cjkSpacing（Bool，默认 true）
- 保留字段：asrEngine、asrProvider、asrApiKey、hotkey、saveRecordings
- 旧配置中的 polish_* 字段读取时静默忽略
- ConfigManager 单例模式、config.json + .env 存储方式不变

### 阶段 2：文本输入服务

新建 TextInputService.swift，参考 Typeoff 的 TextInputSimulator.js：

流程：
1. 保存当前剪贴板内容
2. 写入目标文本到剪贴板
3. 等待 30ms，验证剪贴板内容是否匹配
4. CGEvent 模拟 Cmd+V
5. 等待 150ms
6. 恢复原剪贴板内容

辅助功能权限检查：AXIsProcessTrusted()

### 阶段 3：录音器修改

修改 AudioRecorder.swift：
- 新增 stopAndGetFloatSamples() -> [Float]? 方法，返回 16kHz 单声道 Float32 采样数据（供本地 ASR 使用）
- 转换逻辑复用 v2 的 AVAudioConverter 重采样，输出 Float32 数组而非 WAV 文件
- 保留现有 stop() -> URL?（WAV 输出，用于保存录音）
- 保留 onBuffer（云端流式）和 onVolume（波形动画）回调

### 阶段 4：模型管理

新建 ModelManager.swift，参考 Typeoff 的 LocalASRService.js 下载逻辑：

- 模型目录：~/Library/Application Support/VoiceInput/models/sensevoice-small/
- 模型文件：model.onnx（~894MB）+ tokens.txt
- 下载源：https://file.pgyer.com/models/sensevoice-small/
- 下载流程：
  a. 写入临时文件 model.onnx.tmp，成功后 rename
  b. 支持 HTTP 重定向（最多 5 次）
  c. 通过 ETag 响应头做 MD5 校验（阿里云 OSS 的 ETag = 文件 MD5 hex）
  d. model.onnx 必须 >= 100MB，否则视为损坏重新下载
  e. 已存在且完整的文件跳过下载
- 接口：isModelDownloaded()、downloadModel(onProgress:)、deleteModel()、redownloadModel()

### 阶段 5：本地 ASR 服务

新建 LocalASRService.swift，参考 Typeoff 的 LocalASRService.js 数据处理：

sherpa-onnx 集成方式：
- 从 sherpa-onnx GitHub release 下载 xcframework
- 通过 bridging header 引入 C API
- 使用 SherpaOnnx.swift wrapper 文件调用
- build.sh 负责下载 xcframework + 编译链接

模型加载配置（和 Typeoff 一模一样）：
```
SenseVoice:
  model: model.onnx 路径
  language: ""（自动检测）
  useInverseTextNormalization: true
  tokens: tokens.txt 路径
  numThreads: 2
  provider: "coreml"（macOS CoreML 加速）
```

数据处理流程（和 Typeoff 一模一样）：
1. 接收 Float32 采样数据（16kHz 单声道）
2. 超过 28 秒的音频按 28 秒分段（留 2 秒余量）
3. 每段独立推理：createStream() → acceptWaveform() → decode() → getResult()
4. 拼接所有段结果

后处理（和 Typeoff 一模一样）：
1. 清理 SenseVoice 标签：正则 `<\|[^|]*\|>` 替换为空
2. 单行文本：去掉末尾句号（`.`, `。` 等）
3. CJK 空格：中日韩字符与英文/数字之间加空格

内存管理：
- 云端模式下空闲 5 分钟自动卸载模型
- 本地模式下模型常驻内存

### 阶段 6：浮动指示器重写

完全重写 FloatingOverlay.swift，参考 Typeoff 的 IndicatorApp.jsx：

窗口属性（NSPanel）：
- 无边框、不抢焦点、可穿透鼠标事件
- .floating 层级，所有 Space 和全屏可见
- 透明背景
- 水平居中，屏幕底部

药丸设计：
- 黑色圆角矩形，36px 高，border-radius 18px
- 白色 30% 透明度边框
- 阴影

三种状态：
1. **录音中**：麦克风图标 + 波形动画（16 根柱子，非对称升降 4.5:1）+ 计时器
   - 云端模式有 partial 文本且 >6 字符时：波形替换为水平滚动文本
2. **思考中**：旋转圆圈 + "思考中..." 文字 + 假进度条（渐近曲线 `1 - 1/(1 + t*2.5)`，上限 95%）
3. **空闲**：隐藏

过渡动画：显示/隐藏 300ms 渐变 + 位移 + 缩放

### 阶段 7：AppState 重构

AppState.swift 重构：

删除：
- 所有润色相关属性和逻辑
- textStreamer 实例

新增：
- asrMode 属性
- localASR = LocalASRService 单例
- modelManager = ModelManager 单例

录音流程（双引擎）：

**云端模式：**
1. 按下快捷键 → 立即开始录音（不等连接）
2. 同时建立 DashScope WebSocket 连接
3. 音频实时通过 WebSocket 发送
4. partial 结果显示在指示器
5. 松开 → 发送 finish-task → 等待最终结果
6. 结果通过 TextInputService 剪贴板粘贴
7. 云端失败 → 如果本地模型可用，用本地 fallback

**本地模式：**
1. 按下快捷键 → 开始录音（不建 WebSocket）
2. 只显示波形 + 计时器（无 partial 文本）
3. 松开 → 指示器切到 thinking 状态
4. 录音停止 → 取 Float32 数据 → LocalASRService 推理
5. 后处理（清理标签、CJK 空格等）
6. 结果通过 TextInputService 剪贴板粘贴
7. 本地失败 → 如果 API Key 已配置，用云端 fallback

ESC 取消：录音中和 thinking 阶段均可取消

### 阶段 8：设置界面重设计

SettingsView.swift：从 3 栏改为 2 栏

- **Tab 1 基础**：快捷键、开机自启、保存录音、版本信息
- **Tab 2 识别**：
  - ASR 模式选择：云端 / 本地
  - 云端时：显示 API Key 输入框
  - 本地时：显示模型状态（未下载/已下载 894MB/下载中 45%）、下载/删除/重新下载按钮、进度条

### 阶段 9：构建脚本

build.sh：
1. 检查 sherpa-onnx 动态库（dylib）
2. 下载 SherpaOnnx.swift wrapper 和 bridging header（如果不存在）
3. 用 swiftc 编译（指定 bridging header、头文件路径、链接动态库）
4. 打包 .app（复制 dylib 到 Frameworks、logo、创建 Info.plist）
5. 打包 .dmg

---

## 关键技术决策

1. **sherpa-onnx 集成**：无 SPM 包，通过动态库（dylib）+ bridging header + build.sh 手动链接
2. **云端流式 vs 本地批量**：云端边录边发有实时预览，本地录完后整段推理无预览
3. **剪贴板粘贴 vs AX 写值**：参考 Typeoff 用剪贴板粘贴，更简单可靠，短暂占用剪贴板（180ms 内恢复）
4. **指示器定位**：屏幕底部居中（非光标附近），多显示器时跟随鼠标所在屏幕
5. **配置兼容**：读取 v2 旧配置时静默忽略 polish_* 字段

## 参考文件

| 用途 | 文件路径 |
|------|----------|
| 云端 ASR 参考 | /Users/paul/voice-input-v2/Sources/VoiceInput/Transcriber.swift |
| 本地 ASR 参考 | /tmp/typeoff-src/src/services/LocalASRService.js |
| 文本输入参考 | /tmp/typeoff-src/src/services/TextInputSimulator.js |
| 指示器 UI 参考 | /tmp/typeoff-src/src/renderer/components/IndicatorApp.jsx |
| 录音流程参考 | /tmp/typeoff-src/src/services/RecordingService.js |
| v2 可复用代码 | /Users/paul/voice-input-v2/Sources/VoiceInput/ |

## 验证方式

1. 剪贴板粘贴：在 TextEdit、VS Code、浏览器、终端中测试文本输入
2. 本地 ASR：录制中文短语验证识别正确性；录制 >28s 音频验证分段
3. 模型下载：全新环境下载、MD5 校验、中断恢复
4. 指示器：波形动画、partial 文本滚动、thinking 进度条、多显示器
5. 降级：云端失败 → 本地 fallback；本地失败 → 云端 fallback
6. 完整构建：bash build.sh → VoiceInput.app → DMG 安装
