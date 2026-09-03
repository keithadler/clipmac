#!/bin/bash
# Generates Metadata.appintents inside the built app so the Shortcuts app can see Clip for Mac's
# actions. Needs Xcode (the metadata processor ships with it, not with the Command Line Tools);
# without Xcode the app still builds and the clipmac:// URL scheme covers scripting.
#
#   ./make-appintents.sh "build/Clip for Mac.app"      (build-app.sh calls this)
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-build/Clip for Mac.app}"
PROC=$(xcrun --find appintentsmetadataprocessor 2>/dev/null || true)
if [ -z "$PROC" ]; then echo "App Intents metadata: skipped (needs Xcode)"; exit 0; fi

SDK=$(xcrun --show-sdk-path)
TOOLCHAIN=$(dirname "$(dirname "$(xcrun --find swiftc)")")
XCODE_BUILD=$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}')
WORK=$(mktemp -d "${TMPDIR:-/tmp}/clipmac-intents.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# 1. Ask the compiler for the constant-value metadata of the App Intents types. Only Intents.swift
#    declares them, so it is the one primary file; the rest are context for type checking.
echo '["AppIntent","AppEntity","AppEnum","AppShortcutsProvider","EntityQuery","TransientAppEntity","AppIntentsPackage","DynamicOptionsProvider","EntityPropertyQuery","EntityStringQuery","ResolverSpecification","AssistantSchemaIntent","AssistantSchemaEntity","AssistantSchemaEnum"]' > "$WORK/protocols.json"
OTHERS=$(find Sources/ClipMac -name '*.swift' ! -name Intents.swift)
xcrun swiftc -frontend -c -primary-file Sources/ClipMac/Intents.swift $OTHERS \
  -module-name ClipMac -parse-as-library -target arm64-apple-macos14.0 -sdk "$SDK" \
  -const-gather-protocols-file "$WORK/protocols.json" -emit-const-values-path "$WORK/Intents.swiftconstvalues" \
  -o "$WORK/Intents.o" 2>&1 | grep -v "warning:" || true
[ -s "$WORK/Intents.swiftconstvalues" ] || { echo "App Intents metadata: const values not produced"; exit 0; }

# 2. Run Apple's processor with the same inputs Xcode would give it.
find "$PWD/Sources/ClipMac" -name '*.swift' > "$WORK/sources.txt"
echo "$WORK/Intents.swiftconstvalues" > "$WORK/constvals.txt"
OUT="$APP/Contents/Resources/Metadata.appintents"
rm -rf "$OUT"
# --output is the folder the processor creates Metadata.appintents inside.
"$PROC" --output "$APP/Contents/Resources" --toolchain-dir "$TOOLCHAIN" --module-name ClipMac --sdk-root "$SDK" \
  --xcode-version "$XCODE_BUILD" --platform-family macOS --deployment-target 14.0 --target-triple arm64-apple-macos14.0 \
  --source-file-list "$WORK/sources.txt" --swift-const-vals-list "$WORK/constvals.txt" --force --quiet-warnings 2>&1 | tail -3 || true
if [ -d "$OUT" ]; then echo "App Intents metadata: $OUT ($(ls "$OUT" | tr '\n' ' '))"; else echo "App Intents metadata: processor produced nothing"; fi
