#!/bin/bash
# Launches the built app, checks it stays up and idle, then renders a preview
# image of the line with sample content.
set -euo pipefail
APP="${1:-build/Clothesline.app}"
BIN="$APP/Contents/MacOS/Clothesline"

"$BIN" &
PID=$!
sleep 6
if ! kill -0 "$PID" 2>/dev/null; then
  echo "FAIL: app exited during launch"; exit 1
fi
CPU=$(ps -o %cpu= -p "$PID" | tr -d ' ')
RSS=$(ps -o rss= -p "$PID" | tr -d ' ')
echo "Running after 6 s: pid $PID, cpu ${CPU}%, rss ${RSS} KB"
sleep 10
CPU_IDLE=$(ps -o %cpu= -p "$PID" | tr -d ' ')
echo "Idle after 16 s: cpu ${CPU_IDLE}%"
kill "$PID"; wait "$PID" 2>/dev/null || true

mkdir -p build
"$BIN" --render-preview build/preview.png
test -s build/preview.png
sips -Z 1500 -s format jpeg -s formatOptions 60 build/preview.png --out build/preview.jpg >/dev/null
if [[ "${PREVIEW_BASE64:-0}" == 1 ]]; then
  echo "PREVIEW-BASE64-BEGIN"
  base64 -i build/preview.jpg | fold -w 1000
  echo "PREVIEW-BASE64-END"
fi
echo "Preview: build/preview.png"
