#!/bin/bash
# Builds a universal, ad-hoc signed app and wraps it in a disk image for the GitHub release.
#   ./make-dmg.sh            -> build/Clip-for-Mac-<version>.dmg
# Ad-hoc on purpose: the local development certificate means nothing on other Macs, and a
# Developer ID (see notarize.sh) is the only thing that removes the first-open warning.
set -euo pipefail
cd "$(dirname "$0")"

SIGN_IDENTITY="${SIGN_IDENTITY:--}" ./build-app.sh >/dev/null
APP="build/Clip for Mac.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/Clip-for-Mac-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/First time - read me.txt" <<'TXT'
Clip for Mac — how to install (no experience needed)

1. Drag the "Clip for Mac" icon onto the "Applications" folder next to it.
   That copies the app onto your Mac. You can close this window afterwards.

2. Open the app: open Launchpad (the rocket in the Dock) or your Applications
   folder and click "Clip for Mac".

3. macOS will say it can't check the app for malicious software. Click "Done".
   This is normal for any app not sold through Apple. Nothing is wrong.

4. Click the Apple menu (top-left) > System Settings > Privacy & Security.
   Scroll all the way down. Next to "Clip for Mac was blocked", click
   "Open Anyway", type your Mac password, and click "Open".

5. Done. It opens like any other app from now on, and macOS never asks again.
   When it asks to see your Downloads folder, click "Allow".

Why the warning? Apple charges $99 a year for the certificate that skips it.
This is a free, open-source project without one. All the code is public at
https://github.com/keithadler/clipmac
TXT

rm -f "$DMG"
hdiutil create -volname "Clip for Mac" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
echo "Built: $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG"
