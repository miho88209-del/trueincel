#!/usr/bin/env bash
# Serve The Last Can of Beans on http://localhost:8000 (override with PORT=xxxx ./start.sh)
cd "$(dirname "$0")"
PORT="${PORT:-8000}"
echo "The Last Can of Beans is ready: open http://localhost:${PORT}/ in your browser (Ctrl+C to stop)."
exec python3 -m http.server "$PORT"
