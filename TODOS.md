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
