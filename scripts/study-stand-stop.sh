#!/usr/bin/env bash
# Остановка браузерного VS Code (code-server).
set -euo pipefail

pids="$(pgrep -f 'code-server.*/out/node/entry' || true)"
if [ -z "$pids" ]; then
  echo "code-server не запущен."
  exit 0
fi

kill $pids 2>/dev/null || true
sleep 1
if pgrep -f 'code-server.*/out/node/entry' >/dev/null 2>&1; then
  echo "Не удалось остановить полностью; проверьте процессы вручную." >&2
  exit 1
fi
echo "code-server остановлен."
