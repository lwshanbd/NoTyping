# Permissions Troubleshooting

## Microphone

NoTyping needs microphone access to capture dictation audio. If dictation never starts or the HUD immediately shows an error:

1. Open NoTyping Settings.
2. Go to the `Permissions` tab.
3. Use `Request Access` or `Open System Settings`.
4. In System Settings, enable NoTyping under `Privacy & Security > Microphone`.
5. Return to the app and try again.

## Accessibility

NoTyping needs Accessibility access to inspect the focused text field and insert text into other apps.

If the app can transcribe but cannot insert text:

1. Open NoTyping Settings.
2. Go to the `Permissions` tab.
3. Use `Prompt Again` or `Open System Settings`.
4. In System Settings, enable NoTyping under `Privacy & Security > Accessibility`.
5. Relaunch the app if macOS does not refresh the permission immediately.

## Common Failure Modes

- If a target app uses a custom text engine, NoTyping may fall back to Unicode typing or pasteboard insertion.
- Password fields and other secure text fields are intentionally ignored.
- If a permission toggle appears enabled but behavior does not change, quit and relaunch NoTyping after toggling it.
