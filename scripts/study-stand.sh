#!/usr/bin/env bash
# Запуск браузерного VS Code (code-server) — учебного стенда.
set -euo pipefail

PORT="${PORT:-8011}"
BIND="${BIND:-0.0.0.0}"
CONFIG="${HOME}/.config/code-server/config.yaml"

if ! command -v code-server >/dev/null 2>&1; then
  echo "code-server не установлен. См. LEARNING.md / INFRASTRUCTURE.md." >&2
  exit 1
fi

if curl -s -o /dev/null --max-time 2 "http://localhost:${PORT}/healthz"; then
  echo "code-server уже работает: http://localhost:${PORT}"
else
  setsid code-server --bind-addr "${BIND}:${PORT}" </dev/null >/tmp/code-server.log 2>&1 &
  echo "Запускаю code-server на ${BIND}:${PORT}..."
  for _ in 1 2 3 4 5 6 7 8; do
    sleep 1
    curl -s -o /dev/null --max-time 2 "http://localhost:${PORT}/healthz" && break
  done
  if curl -s -o /dev/null --max-time 2 "http://localhost:${PORT}/healthz"; then
    echo "OK: http://localhost:${PORT}"
  else
    echo "Не удалось запустить. Логи: /tmp/code-server.log" >&2
    exit 1
  fi
fi

if [ -f "$CONFIG" ]; then
  pw="$(awk '/^password:/{print $2}' "$CONFIG")"
  [ -n "$pw" ] && echo "Пароль: ${pw}  (файл: ${CONFIG})"
fi
