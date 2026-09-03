# Changelog

## 0.1.0 — 2026-09-02

First version. Private, pre-release.

- Capture with hard refusal rules: concealed and transient pasteboard types, secure input,
  excluded apps (pre-filled with password managers), size cap.
- SQLite + FTS5 history with 30 day / 2,000 item / 1 GB retention; pinned items exempt;
  real deletion; session-only mode.
- Non-activating floating panel: ⌥⌘V, live search, ↑↓, ↩ paste, ⌘↩ plain, ⌘C copy, ⌘1–9,
  ⌘P pin, ⌘⌫ delete, esc; preview pane that never renders HTML; context menu; drag out.
- Copy-only and auto-paste (Accessibility) with previous-clipboard restore.
- Pins with keywords, `clipmac snip`, Text Replacement export.
- Redactor: API keys, JWTs, private keys, Luhn-valid card numbers, credentials, long base64.
- Assist: on-device semantic search; Apple on-device model (macOS 26); bring-your-own-key
  with visible redacted payload, per-request confirmation, and a request log.
- `clipmac` CLI with `--json` everywhere; `clipmac://` URL scheme for Shortcuts and scripts.
- First-launch welcome, About, Check for Updates, Help menu, login item.
- English and Spanish. Universal binary, macOS 14+.
