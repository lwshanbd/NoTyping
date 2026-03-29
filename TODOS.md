# TODOS

## V2 Future Features

### 本地 Whisper 离线模式
**What:** 集成 whisper.cpp 或 MLX Whisper，支持无网络下的本地语音转写。
**Why:** 零延迟（不需要网络往返）、零费用、无网络环境也能用。当前 V1 完全依赖网络。
**Pros:** 彻底消除网络依赖，转写延迟从 2-4 秒降到 <1 秒。
**Cons:** 需要集成 C/C++ 库或 MLX，模型文件较大（~75MB-1.5GB），首次下载体验需要设计。
**Context:** V1 设计审查中明确排除。TranscriptionProvider 协议已经设计好，实现一个 LocalWhisperProvider 即可插入。主要工作量在模型管理（下载、更新、多语言模型选择）。
**Depends on:** V1 Phase 1 完成（TranscriptionProvider 协议稳定）

### 上下文感知润色
**What:** 读取当前活跃 App 的信息，自动调整 LLM 润色风格。在 Xcode 里用代码友好格式，在邮件里用正式语气，在聊天里保持口语化。
**Why:** 这是 Typeless 有但更智能的版本。不同场景的文本风格差异很大，统一润色是一个妥协。
**Pros:** 用户不需要手动切换模式，体验更自然。
**Cons:** 需要维护 App 分类规则，system prompt 变得更复杂，可能增加注入风险。
**Context:** V1 设计审查中排除。V1 的 RewriteProvider 协议和 system prompt 需要扩展。可以参考 V1 的 AppContextClassifier 设计思路（按 Bundle ID 分类）。
**Depends on:** V1 Phase 2 完成（RewriteProvider + ValidationGate 稳定）

### 拆分 AppCoordinator
**What:** 将 AppCoordinator.swift（900+ 行）拆分为更小的协调器。
**Why:** 文件过大，职责过多（录音流程、文本插入、HUD 控制、设置管理、错误处理全在一个类里）。每次改动都要理解整个文件。
**Pros:** 更好的可维护性、更容易测试、减少合并冲突。
**Cons:** 需要设计好协调器之间的通信机制，可能引入中间层复杂度。
**Context:** Bug fix（文本插入 + HUD 行为修复）后，文件会更长。拆分方向：提取 `InsertionCoordinator`（AXUIElement 缓存、策略选择、失败回退）和 `DictationFlowController`（start/stop 流程、状态机驱动、HUD 控制）。现有的 `private func` 已经按职责分组，提取相对直接。Beck 原则："Make the change easy, then make the easy change."
**Depends on:** Bug fix（Step 1）完成后再做，不要混在一起

### 多窗口精确插入
**What:** 插入目标精确到窗口/tab 级别，而不仅仅是进程级别。
**Why:** 当前 `app.activate()` 只能激活进程，不能指定窗口。用户开了多个 Terminal 窗口时，文本可能插入到错误的窗口。
**Pros:** 消除多窗口场景下的目标歧义。
**Cons:** 需要在 dictation start 时捕获窗口级 AXUIElement 引用并管理其生命周期。
**Context:** Codex plan review 发现的架构限制。当前不变量是"插入目标 = dictation start 时的 app（进程级）"。要升级到窗口级，需要缓存 `AXUIElement` 的 window 引用（不只是 focused element），并在插入时用 `AXUIElementPerformAction(kAXRaiseAction)` 精确激活目标窗口。`FocusedElementContext` 需要扩展加入 pid 和 window identifier。
**Depends on:** Bug fix + AppCoordinator 拆分完成后

### 录音时音频反馈
**What:** 在 HUD 录音状态下显示音量指示器或简单波形动画，让用户知道麦克风正在捕捉声音。
**Why:** 当前唯一的录音反馈是静态文字"Listening..."。用户无法确认麦克风是否真的在工作，只能等到结果出来才知道。这在安静环境或麦克风出问题时尤其困惑。
**Pros:** 即时反馈增强信心，减少"我说了但它没听到"的焦虑。
**Cons:** 需要从 AudioCaptureManager 获取音量数据并传递到 HUD，增加 HUD 复杂度。
**Context:** 设计审查中发现的体验缺口。AudioCaptureManager 已经有 PCM 数据流，计算 RMS 音量很简单。HUD 可以用一个简单的音量条（3-5 个短横条）而不是完整波形。Typeless 有类似的视觉反馈。
**Depends on:** HUD 行为修复（Step 1）完成后
