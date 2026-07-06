#!/usr/bin/env bash
# Kill existing servers, then start backend + frontend.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

lsof -ti:8000 -ti:3000 -ti:3001 2>/dev/null | sort -u | xargs kill -9 2>/dev/null || true
sleep 1

echo "Starting backend on :8000..."
PLAYWRIGHT_HEADED="${PLAYWRIGHT_HEADED:-1}" \
PLAYWRIGHT_SLOW_MO="${PLAYWRIGHT_SLOW_MO:-400}" \
"$ROOT/backend/.venv/bin/python" -m uvicorn backend.app:app --host 0.0.0.0 --port 8000 &
BACKEND_PID=$!

sleep 2
echo "Starting frontend..."
cd "$ROOT/frontend"
npm run dev &
FRONTEND_PID=$!

trap 'kill $BACKEND_PID $FRONTEND_PID 2>/dev/null' EXIT
wait
