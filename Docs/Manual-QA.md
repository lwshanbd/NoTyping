# Manual QA Checklist

## Target Apps

- Notes
- Mail
- TextEdit
- Safari or Chrome textarea
- VS Code or Xcode
- Slack or Messages

## Core Flows

- Launch app and confirm the menu bar item appears.
- Open Settings and verify the tabs render correctly.
- Change the hotkey and confirm the new hotkey works.
- Toggle launch at login and confirm the app reports the new state.
- Verify permission prompts and the troubleshooting buttons.
- Confirm the HUD shows idle, listening, partial transcript, reconnecting, inserted, and error states.

## Language Coverage

- Dictate English in Smart Dictation mode.
- Dictate Simplified Chinese in Smart Dictation mode.
- Dictate mixed Chinese and English technical text.
- Force English and confirm the backend receives the `en` hint.
- Force Simplified Chinese and confirm the backend receives the `zh` hint.

## Vocabulary Coverage

- Add `NCCL`, `CUDA`, `PyTorch`, and `LLaMA` entries.
- Verify spoken aliases normalize correctly in preview.
- Import entries from JSON.
- Import entries from CSV.
- Export entries to both JSON and CSV.
- Disable an entry and confirm it stops affecting normalization.

## Error And Fallback Handling

- Run with the `Mock` provider and verify end-to-end insertion.
- Configure an invalid API key and confirm the error surfaces cleanly.
- Disconnect the network and confirm realtime or rewrite failures do not crash the app.
- While the network is interrupted mid-session, confirm the Debug panel shows reconnect status and the menu bar status reflects reconnecting progress.
- Test an app that does not expose standard accessibility text APIs and confirm fallback insertion still works or surfaces a clear error.
- Turn history on, dictate a phrase, and verify it is saved locally.
- Turn history off, dictate again, and verify no new history entry is persisted.
