# Privacy

Clip for Mac is a clipboard history. By definition it stores things you copy. This page says
exactly what, where, and what ever leaves your Mac.

## What is stored

Every clipboard change that passes the capture rules: the text, the rich text or HTML source,
the image bytes, or the file paths; the name and bundle id of the app that was frontmost; when
Accessibility is granted and the option is on, the title of its front window; the time; how
often you pasted it back. Text recognised in images (on-device, Vision) is stored as the item's
searchable text. Nothing else. No keystrokes, no screenshots of your screen.

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

## Sharing between your own Macs

Off by default. When on, the other Mac is found with Bonjour on the local network, a six-digit
code derived from a Curve25519 key exchange is shown on both screens, and only after you press
Pair on both does anything travel. Payloads are sealed with ChaChaPoly using a key that never
leaves the two Macs' Keychains. Only pins and the last N text-like items travel; items that look
like secrets, images, files, and anything from an excluded app are never sent. Pins can also
travel as a checksummed JSON file through any folder you already sync; history never does.

## What leaves the Mac

Nothing, by default. There is no account, no telemetry, no crash reporting, and no analytics.
Once a day the app asks GitHub's releases API whether a newer version exists: one request, no
identifiers, and nothing is ever downloaded or installed by itself. Settings › General turns the
daily check off; "Check for Updates…" always works by hand. The app also registers itself to open
at login the first time it runs, since a clipboard history only helps while it is running; that is
a toggle too.

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
