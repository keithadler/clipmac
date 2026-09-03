#!/bin/bash
# End-to-end test against the real app: launches a second instance with its own data directory
# (CLIPMAC_HOME) and defaults suite, copies things, and checks what the CLI reports.
#
#   ./tests/integration.sh ["path/to/Clip for Mac.app"]     default: build/Clip for Mac.app
#
# The installed copy, if running, is paused for the duration so it doesn't record the test strings.
set -uo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Clip for Mac.app}"
BIN="$APP/Contents/MacOS/ClipMac"
[ -x "$BIN" ] || { echo "no app at $APP; run ./build-app.sh first"; exit 2; }

export CLIPMAC_HOME
CLIPMAC_HOME=$(mktemp -d "${TMPDIR:-/tmp}/clipmac-it.XXXXXX")
SUITE=com.keithadler.clipmac.test
INSTALLED_PAUSED=0
if command -v clipmac >/dev/null 2>&1 && pgrep -x ClipMac >/dev/null; then
  (unset CLIPMAC_HOME; clipmac pause 10m >/dev/null 2>&1) && INSTALLED_PAUSED=1
fi
cleanup() {
  if [ -n "${PID:-}" ]; then kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; fi
  rm -rf "$CLIPMAC_HOME"
  defaults delete "$SUITE" >/dev/null 2>&1 || true
  [ "$INSTALLED_PAUSED" = 1 ] && (unset CLIPMAC_HOME; clipmac resume >/dev/null 2>&1)
}
trap cleanup EXIT

defaults write "$SUITE" welcomed -bool true
"$BIN" >/dev/null 2>&1 &
PID=$!
sleep 2
pgrep -q -x ClipMac || { echo "app did not start"; exit 2; }

# The monitor polls every 300 ms while someone is at the keyboard and once a second when the person
# has been away for two minutes. A CI runner never sees a keystroke, so it always polls slowly: every
# wait here must outlast one slow poll (1 s plus 400 ms leeway) or the capture is checked before it
# has happened.
SETTLE=1.6
fail=0
check() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=1; fi; }
copy() { printf '%s' "$1" | pbcopy; sleep "$SETTLE"; }

copy "integration alpha $$"
check "captures plain text"            '"$BIN" list --json | grep -q "integration alpha"'
copy "https://example.com/it/$$"
check "detects links"                  '"$BIN" list --limit 1 --json | grep -q "\"kind\" : \"url\""'
copy "export ANTHROPIC_API_KEY=sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdef"
check "flags secrets"                  '"$BIN" list --limit 1 --json | grep -q "\"sensitive\" : true"'
swift tests/concealed.swift >/dev/null 2>&1; sleep "$SETTLE"
check "skips concealed pasteboards"    '! "$BIN" list --json | grep -q hunter2'
CLIPMAC_SETTLE="$SETTLE" swift tests/richcontent.swift >/dev/null 2>&1; sleep "$SETTLE"
check "captures rtf"                   '"$BIN" list --json | grep -q "\"kind\" : \"rtf\""'
check "captures images"                '"$BIN" list --json | grep -q "\"kind\" : \"image\""'
check "captures file urls"             '"$BIN" list --json | grep -q "\"kind\" : \"file\""'
before=$("$BIN" status --json | grep '"items"' | tr -dc 0-9)
copy "integration alpha $$"
after=$("$BIN" status --json | grep '"items"' | tr -dc 0-9)
check "dedups identical copies"        '[ "$before" = "$after" ] && "$BIN" list --limit 1 | grep -q "integration alpha"'
"$BIN" pause 1m >/dev/null; copy "while paused $$"
check "pause stops capture"            '! "$BIN" list --json | grep -q "while paused"'
"$BIN" resume >/dev/null; copy "after resume $$"
check "resume restarts capture"        '"$BIN" list --limit 1 | grep -q "after resume"'
check "search finds words"             '"$BIN" search alpha | grep -q "integration alpha"'
ID=$("$BIN" list --json | grep -B20 "integration alpha" | grep '"id"' | tail -1 | tr -dc 0-9)
"$BIN" pin "#$ID" --keyword itsnip >/dev/null
check "pin and snip"                   '"$BIN" snip itsnip | grep -q "integration alpha"'
check "forget --sensitive"             '"$BIN" forget --sensitive >/dev/null && ! "$BIN" list --json | grep -q sk-ant'
# status exits 1 on purpose when FileVault is off (CI runners have it off), 0 otherwise; either way it
# must print the report.
status_contract() {
  local out rc; out=$("$BIN" status --json); rc=$?
  echo "$out" | grep -q '"items"' || return 1
  if echo "$out" | grep -q '"filevault" : false'; then [ $rc = 1 ]; else [ $rc = 0 ]; fi
}
check "status prints and exit code matches FileVault" 'status_contract'
check "isolated data directory"        '[ -f "$CLIPMAC_HOME/history.db" ]'
check "selftest passes"                '"$BIN" selftest --json | grep -q "\"failed\" : 0"'
check "wipe"                           '"$BIN" wipe --yes >/dev/null && [ "$("$BIN" status --json | grep "\"items\"" | tr -dc 0-9)" = 0 ]'

[ $fail = 0 ] && echo "integration: all passed" || echo "integration: FAILURES"
exit $fail
