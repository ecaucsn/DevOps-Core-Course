#!/usr/bin/env bash
# Базовые инструменты: uv + Python 3.13, Trivy, yq. Node проверяется (уже есть через nvm).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# --- uv ---
if have uv && [ "${FORCE:-0}" != "1" ]; then
  ok "uv уже установлен: $(uv --version)"
else
  install_tar_member \
    "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_ARCH}.tar.gz" \
    uv uv
  # uvx рядом с uv
  d=$(mktemp -d)
  fetch "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_ARCH}.tar.gz" "$d/u.tgz"
  tar -xzf "$d/u.tgz" -C "$d"
  f=$(find "$d" -type f -name uvx | head -1)
  [ -n "$f" ] && install -m 0755 "$f" "$BIN/uvx"
  rm -rf "$d"
fi

# --- Python 3.13 (managed by uv, user-local) ---
if uv python find 3.13 >/dev/null 2>&1; then
  ok "Python 3.13 уже доступен"
else
  log "Устанавливаю Python 3.13 через uv"
  uv python install 3.13
  ok "Python 3.13 установлен"
fi

# --- Trivy ---
if have trivy && [ "${FORCE:-0}" != "1" ]; then
  ok "Trivy уже установлен: $(trivy --version | head -1)"
else
  if [ "$TRIVY_VERSION" = "0.69.4" ]; then
    die "Trivy 0.69.4 скомпрометирован (CVE-2026-33634). Выберите другую версию."
  fi
  install_tar_member \
    "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
    trivy trivy
fi

# --- yq ---
if have yq && [ "${FORCE:-0}" != "1" ]; then
  ok "yq уже установлен: $(yq --version)"
else
  install_direct \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}" \
    yq --version
fi

# --- Node (для лаб. 17) ---
if have node; then
  ok "Node.js: $(node --version), npm: $(npm --version 2>/dev/null || echo n/a)"
else
  warn "Node.js не найден. Установите nvm + Node 20+ (нужно для лаб. 17)."
fi
