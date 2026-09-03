# Contributing to Clip for Mac

Thanks for looking. Clip for Mac is small on purpose: one Swift package, no dependencies, no Xcode
project. Anything that keeps it that way is welcome.

## Ground rules that keep it trustworthy

These are not style preferences; they are the reason people can put a clipboard manager on a
machine that also runs a password manager. A pull request that bends one needs a very good argument.

1. **The refusal rules are not settings.** Concealed and transient pasteboard types, secure input,
   excluded apps and the size cap live in `Monitor.refusal` and have no off switch. Add rules
   there; never add a preference that weakens one.
2. **Nothing leaves the Mac by itself.** The only network calls are the manual update check and
   the bring-your-own-key assist, which sends only what the user has seen masked and confirmed.
   No telemetry, no crash reporting, no background fetches. Every cloud request is logged.
3. **The redactor runs before anything is sent.** New secret shapes go in `Redactor.swift` with a
   regression case; a false positive costs a `[REDACTED]` in a summary, a false negative costs a
   leaked key, so lean towards flagging.
4. **Forgetting is the feature.** Deletion is real deletion; retention is enforced; there is no
   soft-delete and no hidden copy. Session-only mode must keep nothing on disk.
5. **Say what you don't do.** The app does not encrypt its own database (FTS5 cannot index
   ciphertext); it says so in Settings, `clipmac status`, PRIVACY.md and the README, and warns
   when FileVault is off. If a feature has a limit, the UI states it in one plain sentence.
6. **No keystroke interception.** Snippet expansion is by pin, `clipmac snip`, or a macOS Text
   Replacement export. The app never registers an input monitor.
7. **Plain language.** Everything a user reads is written for someone who has never heard of a
   pasteboard type. Jargon in comments is fine.

## Building and testing

```bash
./build-app.sh --install --run     # universal build, wraps, installs, symlinks clipmac
clipmac selftest                   # 11 suites, no Xcode needed
swift test                         # the same suites under XCTest (needs Xcode)
./tests/integration.sh             # drives a second app instance end to end
clipmac screenshots docs/screenshots   # README images and promo cards from demo data
```

Run `./make-local-identity.sh` once so the Accessibility permission survives rebuilds.

## Adding a capture rule

1. Add a case to `Monitor.Refusal` and the check to `Monitor.refusal(...)`.
2. Add a case to `CaptureSuite` ("refusal rules") and, if the rule needs a real pasteboard, to
   `MonitorSuite`.
3. Mention it in the README's "What it will never capture" list, PRIVACY.md and both help pages.

## Adding a CLI command

1. Add the case to `CLI.run`, the usage text, `docs/clipmac.1` and both help pages.
2. Give it `--json` output through `Dump`.
3. Add an exit-code case to `CLISuite` and, if it changes the store, a store-effect case.

## Translations

Strings live in `Localization/<lang>.lproj/Localizable.strings`, keyed by the English text; the
long-form help is `docs/Help.<lang>.html`. Copy the Spanish files to start a new language. The
build script copies every `.lproj` and help page into the app.
