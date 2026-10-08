#!/bin/bash
# End-to-end test of screenshot collection with the real app binary.
#
# Simulates what /usr/sbin/screencapture does (write a hidden temp file,
# stamp the kMDItemIsScreenCapture attribute, rename into place) so it can run
# headless without Screen Recording permission. Verifies:
#   1. a screenshot is hung once
#   2. a burst of 5 rapid screenshots is hung completely, without duplicates
#   3. an image *named* like a screenshot but written by another app is ignored
#   4. touching an already-hung screenshot does not hang it again
#   5. changing the macOS screenshot location (defaults write) is followed live
#
# Phase 5 modifies com.apple.screencapture `location` and restores it after.
set -euo pipefail
APP="${1:-build/Clothesline.app}"
BIN="$APP/Contents/MacOS/Clothesline"
SRC_IMG="${2:-build/preview.png}"
TMP=$(mktemp -d)
trap 'kill $PID 2>/dev/null || true; restore_location; rm -rf "$TMP"' EXIT
OLD_LOCATION=$(defaults read com.apple.screencapture location 2>/dev/null || echo "__unset__")
restore_location() {
  if [[ "$OLD_LOCATION" == "__unset__" ]]; then defaults delete com.apple.screencapture location 2>/dev/null || true
  else defaults write com.apple.screencapture location "$OLD_LOCATION"; fi
}

fake_screenshot() { # dir name
  local tmp="$1/.$2"
  cp "$SRC_IMG" "$tmp"
  xattr -w com.apple.metadata:kMDItemIsScreenCapture 1 "$tmp"
  mv "$tmp" "$1/$2"
}

count_screenshots() { # state-dir
  python3 - "$1/state.json" <<'PY'
import json, sys
try:
    items = json.load(open(sys.argv[1]))["items"]
except Exception:
    print(0); sys.exit()
print(sum(1 for i in items if i["source"] == "screenshot"))
PY
}

titles() {
  python3 -c 'import json,sys; print(sorted(i["title"] for i in json.load(open(sys.argv[1]))["items"]))' "$1/state.json"
}

fail() { echo "FAIL: $*"; titles "$STATE" || true; exit 1; }

# ---- Phases 1-4: explicit folder --------------------------------------------
SHOTS="$TMP/shots"; STATE="$TMP/state"; mkdir -p "$SHOTS" "$STATE"
"$BIN" --state-dir "$STATE" --screenshot-folder "$SHOTS" &
PID=$!
sleep 4

fake_screenshot "$SHOTS" "Screenshot 2026-10-08 at 10.00.00.png"
sleep 2
[[ $(count_screenshots "$STATE") == 1 ]] || fail "single screenshot not hung"
echo "PASS 1: single screenshot hung"

for i in 1 2 3 4 5; do fake_screenshot "$SHOTS" "Screenshot 2026-10-08 at 10.01.0$i.png"; done
sleep 3
[[ $(count_screenshots "$STATE") == 6 ]] || fail "burst: expected 6, got $(count_screenshots "$STATE")"
echo "PASS 2: burst of 5 hung, no duplicates"

cp "$SRC_IMG" "$SHOTS/Screenshot 2026-10-08 at 10.02.00.png"   # no attribute
cp "$SRC_IMG" "$SHOTS/holiday.png"
sleep 2
[[ $(count_screenshots "$STATE") == 6 ]] || fail "impostor files were hung"
echo "PASS 3: impostor files ignored"

touch "$SHOTS/Screenshot 2026-10-08 at 10.00.00.png"
xattr -w com.apple.metadata:kMDItemIsScreenCapture 1 "$SHOTS/Screenshot 2026-10-08 at 10.01.01.png"
sleep 2
[[ $(count_screenshots "$STATE") == 6 ]] || fail "touch caused a duplicate"
echo "PASS 4: re-touching does not duplicate"
kill $PID; wait $PID 2>/dev/null || true

# ---- Phase 5: follow the macOS screenshot location ---------------------------
DIR1="$TMP/loc1"; DIR2="$TMP/loc2"; STATE="$TMP/state2"; mkdir -p "$DIR1" "$DIR2" "$STATE"
defaults write com.apple.screencapture location "$DIR1"
"$BIN" --state-dir "$STATE" &
PID=$!
sleep 4
fake_screenshot "$DIR1" "Screenshot in one.png"
sleep 2
[[ $(count_screenshots "$STATE") == 1 ]] || fail "macOS location not followed"
defaults write com.apple.screencapture location "$DIR2"
sleep 3
fake_screenshot "$DIR2" "Screenshot in two.png"
sleep 2
[[ $(count_screenshots "$STATE") == 2 ]] || fail "location change not followed (got $(count_screenshots "$STATE"))"
echo "PASS 5: follows macOS screenshot location changes live"
echo "All screenshot end-to-end checks passed."
