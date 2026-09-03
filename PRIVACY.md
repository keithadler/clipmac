# Privacy

Clip for Mac is a clipboard history. By definition it stores things you copy. This page says
exactly what, where, and what ever leaves your Mac.

## What is stored

Every clipboard change that passes the capture rules: the text, the rich text or HTML source,
the image bytes, or the file paths; the name and bundle id of the app that was frontmost; the
time; how often you pasted it back. Nothing else. No keystrokes, no window titles, no screenshots.

## What is never stored

- Anything a password manager marks as concealed or transient (`org.nspasteboard.ConcealedType`
  and friends). 1Password, Bitwarden, Keychain Access, Strongbox, KeePassXC and others set this.
- Anything copied while a password field has focus (macOS "secure input").
- Anything copied from an app on the exclusion list (Settings › Capture). It ships pre-filled
  with the common password managers; you can add any app.
- Anything larger than the size cap.

These are not settings. There is no switch that turns them off.

## Where

`~/Library/Application Support/Clip for Mac/history.db` (SQLite, WAL mode) and `blobs/` next to it
for images and rich text. Default retention is 30 days, 2,000 items, 1 GB; pinned items are
exempt. Deleting is real deletion. "Session only" keeps everything in memory instead.

## Encryption

Clip for Mac does **not** encrypt the database itself. Full-text search cannot index ciphertext,
and half-encryption would imply more than it delivers. The history is protected by FileVault
like the rest of your home folder. The app warns in Settings › History and in `clipmac status`
when FileVault is off. If you share a Mac account with someone, they can read your history.

## What leaves the Mac

Nothing, by default. There is no account, no telemetry, no crash reporting, no analytics, and no
update check unless you click "Check for Updates…" (one request to GitHub with no identifiers).

The optional "ask your clipboard" feature has three levels:

1. Search by meaning uses Apple's on-device word embeddings. No network.
2. Apple's on-device model (macOS 26 with Apple Intelligence). No network.
3. Bring your own key (Anthropic or OpenAI). Off by default. You choose the items, the app runs
   the redactor over them (API keys, JWTs, private keys, card numbers, credentials, long base64
   are masked), shows you the exact payload, and sends it only when you confirm. The key is
   stored in your login Keychain. Every request is logged with the time, provider, model, item
   count, character count and token counts: `clipmac assist log`. The provider's own privacy
   terms apply to what you send.

## Permissions

- **Accessibility** is optional and only used to press ⌘V for you after you choose an item.
  Without it the app copies and you paste.
- No other permission is requested. The app does not ask for Full Disk Access, Screen Recording,
  Input Monitoring, Automation, or your contacts, calendar, or location.

## Removing everything

`clipmac wipe --yes`, or Settings › History › Forget everything, then delete
`~/Library/Application Support/Clip for Mac/`. Remove the API key from Keychain Access if you
added one (Settings › Assist › Remove does this too).
