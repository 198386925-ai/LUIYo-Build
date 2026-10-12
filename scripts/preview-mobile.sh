#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PORT="${PORT:-8765}"
python3 -m http.server "$PORT" --directory YouYouLUI_iOS/YouYouLUI/Web &
PID=$!
trap 'kill $PID' EXIT
echo "Preview: http://127.0.0.1:$PORT/"
wait
