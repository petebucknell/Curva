#!/bin/sh
# Serves a copy of docs/ against the staging project on http://localhost:8081, with the QA test login on.
# Run it from anywhere: ./qa/serve-staging.sh   Stop it with Ctrl+C.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT=/tmp/curva-staging
rm -rf "$OUT" && mkdir -p "$OUT"
cp -R "$ROOT/docs/." "$OUT/"
cp "$ROOT/qa/staging-config.js" "$OUT/config.js"
lsof -ti tcp:8081 | xargs kill 2>/dev/null || true
echo "Serving $(git -C "$ROOT" branch --show-current) at http://localhost:8081 (staging)"
cd "$OUT" && exec python3 -m http.server 8081 --bind 127.0.0.1
