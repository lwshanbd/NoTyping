# Architecture

## Core Pipeline

`AppCoordinator` owns the user-visible state and orchestrates the dictation pipeline:

1. `HotkeyManager` captures a global press-and-hold or toggle hotkey.
2. `AudioCaptureManager` starts `AVAudioEngine`, converts input to 24 kHz mono PCM16, and feeds a local `VoiceActivityDetector`.
3. `RealtimeTranscriptionServiceProtocol` streams audio to the backend, emits connection-status events, and replays the current uncommitted buffer across bounded reconnect attempts.
4. `TranscriptAssembler` merges incremental deltas into stable partial text and finalized segments.
5. `TranscriptNormalizer` applies deterministic vocabulary normalization and protected-term extraction.
6. `RewriteServiceProtocol` lightly polishes finalized segments according to app context and dictation profile.
7. `FocusedElementInspector` reads the focused accessibility element and field context.
8. `TextInsertionServiceProtocol` inserts the final text into the target app with a fixed fallback chain.

## State Machine

The dictation lifecycle runs through these explicit states:

- `idle`
- `requestingPermissions`
- `ready`
- `recording`
- `receivingPartialTranscript`
- `segmentFinalizing`
- `normalizingVocabulary`
- `rewriting`
- `inserting`
- `error`

`DictationStateMachine` is actor-backed and rejects invalid stage transitions.

## Data Storage

- `SettingsStore` persists non-secret settings in Application Support.
- `KeychainStore` holds provider API keys.
- `VocabularyService` persists user vocabulary as JSON and supports CSV/JSON round-tripping.
- `HistoryStore` persists dictated text only when the user explicitly enables history.
- `DiagnosticStore` keeps an in-memory timeline and can persist a log file when debug logging is enabled.
- `AppCoordinator` also exposes live realtime connection status so the HUD, menu bar, and Debug panel can show reconnect progress.

## Provider Extensibility

Two protocols are the main swap points:

- `RealtimeTranscriptionServiceProtocol`
- `RewriteServiceProtocol`

Built-in adapters include OpenAI-compatible live implementations and mock implementations for offline testing.

## Insertion Strategy

The insertion stack is intentionally conservative:

1. Accessibility selected-text replacement
2. Accessibility value replacement
3. Unicode typing fallback
4. Pasteboard plus paste fallback

Secure fields are intentionally rejected.
