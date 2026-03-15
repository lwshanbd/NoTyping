# NoTyping

NoTyping is a native macOS menu bar dictation app for system-wide AI voice typing. Hold a global hotkey, speak naturally, and the app captures microphone audio, streams it to a realtime transcription backend, normalizes custom vocabulary, lightly polishes the text, and inserts it into the currently focused field in another macOS app.

## What It Does

- Provides a menu bar app with a global hotkey, optional toggle mode, floating HUD, settings, and permission troubleshooting.
- Streams microphone audio incrementally to an OpenAI-compatible realtime transcription backend instead of uploading one long recording.
- Applies deterministic vocabulary normalization before rewrite so terms like `NCCL`, `CUDA`, `PyTorch`, and `LLaMA` are preserved consistently.
- Supports app-specific rules that can override category, dictation profile, rewrite aggressiveness, or disable rewrite entirely for specific bundle identifiers.
- Inserts the final text into the focused app using accessibility selected-text replacement first when possible, then full AX value replacement, then Unicode typing, then pasteboard fallback.
- Supports Auto, English, and Simplified Chinese language modes and preserves the original language in the rewrite layer.
- Ships with a `Mock` provider so the full UI and insertion flow can be exercised without live API credentials.

## Architecture Overview

The app is split into clear layers:

- `AppCoordinator` owns the dictation lifecycle and UI-facing state.
- `DictationStateMachine` enforces explicit states instead of scattered booleans.
- `HotkeyManager`, `AudioCaptureManager`, `VoiceActivityDetector`, `RealtimeTranscriptionService`, `TranscriptAssembler`, `TranscriptNormalizer`, `RewriteService`, `FocusedElementInspector`, and `TextInsertionService` form the core pipeline.
- `VocabularyService`, `SettingsStore`, `HistoryStore`, `DiagnosticStore`, and `KeychainStore` persist local data.
- `MenuBarController`, `HUDOverlayController`, and SwiftUI settings panes provide the app shell.

More detail lives in [Docs/Architecture.md](/Users/baodi/Documents/GitHub.nosync/NoTyping/Docs/Architecture.md).

## Dictation Flow

1. The user presses the configured global hotkey.
2. The app verifies Microphone and Accessibility permissions.
3. `AVAudioEngine` starts immediately and emits 24 kHz mono PCM16 chunks.
4. The realtime service streams chunks over WebSocket and receives partial and finalized transcript events.
5. `TranscriptAssembler` stabilizes partials and emits finalized segments in order.
6. `TranscriptNormalizer` applies vocabulary-aware normalization and protects configured terms.
7. `RewriteService` lightly polishes text for the detected app context unless the active profile bypasses rewrite.
8. `TextInsertionService` inserts the result into the focused macOS app.

## Permissions

- Microphone is required to capture dictation audio.
- Accessibility is required to inspect the focused element and insert text across apps.

Troubleshooting guidance lives in [Docs/Permissions.md](/Users/baodi/Documents/GitHub.nosync/NoTyping/Docs/Permissions.md).

## Vocabulary Mapping

Vocabulary entries are stored locally in Application Support as JSON and can be imported or exported as JSON or CSV. Each entry supports:

- written form
- one or more spoken forms
- language scope
- enabled flag
- case sensitivity
- priority
- notes

The normalization pass uses entries both to generate transcription hints and to deterministically replace known spoken aliases before the rewrite call.

## Language Support

- `Auto-detect` sends no fixed transcription language hint.
- `English` sends `en`.
- `Simplified Chinese` sends `zh` and keeps punctuation and output in Simplified Chinese.

Mixed-language dictation is handled conservatively, and configured technical terms are protected from rewrite drift.

## Provider Configuration

The app supports three provider profiles:

- `OpenAI`
- `Custom Compatible`
- `Mock`

For live providers, configure:

- base URL
- transcription model alias
- rewrite model alias
- API key
- optional realtime session token endpoint
- capability flags

`OpenAI` defaults to `https://api.openai.com`, `gpt-4o-transcribe`, and `gpt-5-mini`.

## Privacy

- Settings, vocabulary, and optional history are stored locally.
- API keys are stored in the macOS Keychain only.
- Transcript history is off by default.
- When history is off, dictated text is not persisted locally.
- Audio and rewrite prompts are sent only to the configured API provider during active dictation sessions.

## Mock Mode

Select the `Mock` provider profile to test the full dictation and insertion flow without network access or API credentials. The mock transcription service returns sample phrase-final output, and the mock rewrite service performs lightweight local cleanup.

## Build And Run

1. Generate the Xcode project:

   ```bash
   xcodegen generate
   ```

2. Open `NoTyping.xcodeproj` in Xcode.
3. Build and run the `NoTyping` scheme on macOS 14 or later.
4. Grant Microphone and Accessibility permissions when prompted.
5. Configure the provider in Settings if you want live transcription and rewrite.

You can also build from the command line:

```bash
xcodegen generate
xcodebuild -project NoTyping.xcodeproj -scheme NoTyping -destination 'platform=macOS' build
```

## Known Limitations

- Some apps expose incomplete accessibility text APIs, so the app may fall back to Unicode typing or pasteboard insertion.
- App-specific rules match by bundle identifier substring, which is practical and user-editable but less strict than exact signed-app identity matching.
- Realtime provider compatibility varies. `Custom Compatible` is intended for providers that mirror the required WebSocket and Responses API behavior.
- The session-token flow is adapter-based and may need a provider-specific backend contract in production.
- The rewrite layer intentionally falls back to normalized raw text when protected terms would otherwise be altered.

## Main Tradeoffs

- The app prefers reliability over aggressive rewriting. Protected-term validation and raw fallback are intentionally conservative.
- Accessibility insertion is the first-class path, but the fallback chain accepts that some apps require typing or pasteboard simulation.
- The realtime adapter is built around OpenAI-compatible event names and payloads, with capability flags and a mock profile to keep the app usable while provider details vary.
- Launch-at-login uses the main-app registration path for a lightweight setup. A production release may still want additional packaging and signing validation.

## Remaining TODOs

- Add production-grade reconnect backoff and websocket session resumption.
- Expand app-specific rule editing beyond the current practical list view.
- Add richer token protection for code snippets, shell commands, and URLs during rewrite validation.
- Add signed distribution, notarization, and release packaging automation.
- Add deeper manual QA across more third-party editors and browser-based rich-text fields.

## Extension Points

- Alternate transcription providers plug in through `RealtimeTranscriptionServiceProtocol` and `RealtimeTranscriptionServiceFactory` in [RealtimeTranscriptionService.swift](/Users/baodi/Documents/GitHub.nosync/NoTyping/NoTyping/Services/RealtimeTranscriptionService.swift).
- Alternate rewrite providers plug in through `RewriteServiceProtocol` and `RewriteServiceFactory` in [RewriteService.swift](/Users/baodi/Documents/GitHub.nosync/NoTyping/NoTyping/Services/RewriteService.swift).
- Vocabulary persistence and normalization extend through [VocabularyService.swift](/Users/baodi/Documents/GitHub.nosync/NoTyping/NoTyping/Services/VocabularyService.swift) and [TranscriptNormalizer.swift](/Users/baodi/Documents/GitHub.nosync/NoTyping/NoTyping/Services/TranscriptNormalizer.swift).

## Future Improvements

- Alternate provider plug-ins for speech recognition and rewrite.
- Richer field heuristics for code editors and terminals.
- Streaming phrase-by-phrase insertion undo support.
- More granular mixed-language normalization.
- Signed distribution, notarization, and automated release packaging.
