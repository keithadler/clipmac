# Clip for Mac: sell it, advertise it, or neither?

Written 2026-09-02, at version 1.0.0, before any public release. Revisit when the facts change.

## The short answer

- **License:** MIT, all of it, no paid tier. Decided.
- **Sell it:** not now. Take money only through a tip jar (GitHub Sponsors) and, later, a
  pay-what-you-want notarized DMG. Revisit selling if the usage triggers below are hit.
- **Advertise it:** yes, but not 0.1. Use it daily for two weeks, ship 0.2 notarized, then launch
  on the security angle. Details below.

## Why not sell

1. **The market is priced by free software.** Maccy is free, open source and good. Raycast ships a
   clipboard manager inside a free launcher. Alfred and Paste own the paid end with years of
   polish. A new entrant charging money competes with "free and already installed".
2. **The product's identity is trust, and trust doesn't gate well.** The three things that aren't
   commoditized are the capture-refusal rules, on-device semantic search, and redaction before
   anything is sent. Every one of them is a reason to *believe* the app, and the way people
   believe a clipboard app is by reading its source. Putting any of it behind a license check
   weakens the pitch more than the license fee is worth.
3. **The spec forbids the machinery.** No license server, no account, no relay. A paid unlock needs
   at least a key check; the cheapest honest version (Gumroad key, offline validation) is still
   support tickets, refunds and a second build to test.
4. **The arithmetic is small.** A niche utility with organic reach might see a few hundred
   downloads a month in its first year. At a 2 to 3 percent conversion on a $20 one-time unlock
   that is tens of dollars a month, less than the $99 Developer ID that selling would require.
5. **It is a week old.** There are no users to tell you what they'd pay for.

## What money is realistic

- **GitHub Sponsors / Buy Me a Coffee** link in the README and About. Costs nothing, no support
  burden, signals that the project is maintained.
- **Pay-what-you-want notarized DMG** once a Developer ID exists: source and a free build on
  GitHub, a convenience download with a suggested $5 on Gumroad. The same certificate removes the
  five-step "unidentified developer" dance from Tidy for Mac too, so the $99 is shared.
- **Not the Mac App Store.** Auto-paste needs Accessibility, which a sandboxed app can't get, and
  App Review has rejected background pasteboard polling before.

## Triggers to revisit selling

Any two of these:

- 1,000 GitHub stars or 5,000 installs (Homebrew cask analytics plus DMG downloads).
- Users asking for features that cost real engineering time (sync, iOS companion, team sharing).
- A Developer ID already paid for other reasons.
- Sponsorship income above $50 a month, which proves people will pay for it at all.

If revisited, the defensible shape is still the one in the spec: core free and MIT forever, the
assist layer as a one-time unlock in the $20 to $30 range, and nothing that phones home.

## Advertise: how

**Positioning line:** *A clipboard manager that refuses to capture secrets.* Lead with the refusal
rules, then local semantic search. Do not lead with the cloud AI tier; mention it as "optional,
your key, you see the redacted payload first".

**Before launch (2 to 3 weeks):**

1. Daily use for two weeks. Paste timing, restore delay and panel focus are where clipboard apps
   get bad reviews.
2. Developer ID and notarization. The first-open warning is the biggest drop-off for direct
   downloads and the biggest source of "is this malware" comments.
3. A Homebrew cask (`brew install --cask clipmac`). Most of the target audience installs this way.
4. README top: one 15-second GIF of ⌥⌘V, type, paste. A comparison table against Maccy, Paste and
   Raycast on the four points that differ (refusal rules, secure-input check, semantic search,
   redaction-before-send). Be fair to Maccy; its users are the audience.
5. A one-page PRIVACY.md: what is stored, where, what leaves the machine (nothing unless a key is
   added), what FileVault covers.

**Launch order:**

1. Flip the repo public, tag 0.2.0, attach the notarized DMG and its SHA-256.
2. Show HN with the positioning line. Answer every comment for the first six hours.
3. r/macapps and r/MacOS the next day, with the GIF.
4. Submit to MacUpdate and Product Hunt within the week.
5. Post in the Maccy discussion threads where people ask about secrets or semantic search, once,
   politely, with a link.

**What to measure:** stars per week, Homebrew installs, issues opened by strangers, and whether
anyone mentions the refusal rules unprompted. If the security angle doesn't come up in the first
50 comments, the positioning is wrong and it's "just another Maccy".

## Keep private until

- The two-week daily-use pass is done and the paste path is boring.
- Notarization works.
- The README and PRIVACY page are written.

Until then the repository stays local with no remote. When ready:
`gh repo create keithadler/clipmac --private --source . --push`, then flip to public at launch.
