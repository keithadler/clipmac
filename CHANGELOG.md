# Changelog

## 1.0.2 — 2026-09-03

"More from the Same Maker" in the Help menu and the menu bar, pointing at the family page. Help and README gained the same section.

## 1.0.1 — 2026-09-02

- Opens at login by default (registered once on first run) and checks for a new version once a day
  by default. Both are toggles in Settings › General; nothing is ever installed by itself.

## 1.0.0 — 2026-09-02

First release.

- Capture with hard refusal rules: concealed and transient pasteboard types, secure input,
  excluded apps (pre-filled with password managers), size cap.
- SQLite + FTS5 history with 30 day / 2,000 item / 1 GB retention; pinned items exempt;
  real deletion; session-only mode.
- Non-activating floating panel: ⌥⌘V, live search, ↑↓, ↩ paste, ⌘↩ plain, ⇧↩ queue, ⌘C copy,
  ⌘1–9, ⌘P pin, ⌘⌫ delete, esc; resizable; preview pane that never renders HTML; context
  menu; drag out.
- Global paste-as-plain-text (⌥⇧⌘V) and paste stack with paste-next (⌃⌥⌘V); all shortcuts
  configurable with conflict detection.
- Copy-only and auto-paste (Accessibility) with previous-clipboard restore.
- Pins with keywords, `clipmac snip`, Text Replacement export.
- Redactor: API keys, JWTs, private keys, Luhn-valid card numbers, credentials, long base64.
- Assist: on-device semantic search; Apple on-device model (macOS 26); bring-your-own-key
  with visible redacted payload, per-request confirmation, and a request log.
- `clipmac` CLI with `--json` everywhere; `clipmac://` URL scheme for Shortcuts and scripts.
- First-launch welcome, About, Help menu, login item. Updates: manual check, or an opt-in daily
  check that surfaces a newer release in the menu bar (nothing installs itself); `clipmac update`.
- Bundled help (English and Spanish) with a keyboard reference; `clipmac screenshots` renders every
  window with demo data in dark and light for the README.
- Search by meaning uses averaged word embeddings (measured far better than the sentence model on
  clipboard text); card-number detection is group-aware.
- Paste transforms (⌥↩ clean, Paste As menu), paste-all from the stack, duplicate-aware
  history with ×N counts, window titles when Accessibility allows, skip toast, Vision OCR
  for screenshots, pins export/import and folder sync, local-network sharing paired by code
  and end-to-end encrypted, Shortcuts actions (metadata via make-appintents.sh with Xcode).
- English and Spanish. Universal binary, macOS 14+.
