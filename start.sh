#!/usr/bin/env bash
# Serve The Last Can of Beans with multiplayer on port 8000 (override with PORT=xxxx ./start.sh)
cd "$(dirname "$0")"
exec python3 server.py "${PORT:-8000}"
