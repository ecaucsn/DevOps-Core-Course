#!/usr/bin/env bash
# Edge (Wrangler для Cloudflare Workers) и воспроизводимые сборки (Nix без root).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# --- Wrangler (лаб. 17) — актуальные версии требуют Node >= 22.12 ---
node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "${node_major:-0}" -lt 22 ] && [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"
  nvm install 22 >/dev/null 2>&1 || true
  nvm use 22 >/dev/null 2>&1 || true
  node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
fi
# убрать возможный устаревший локальный дубль, перекрывающий nvm
[ -L "$BIN/wrangler" ] && rm -f "$BIN/wrangler"

if have wrangler && [ "${FORCE:-0}" != "1" ]; then
  ok "wrangler уже установлен: $(wrangler --version 2>/dev/null | tail -1) (Node $(node --version 2>/dev/null))"
elif have npm && [ "${node_major:-0}" -ge 22 ]; then
  log "Устанавливаю wrangler@latest (Node $(node --version))"
  npm install -g wrangler@latest
  ok "wrangler -> $(wrangler --version 2>/dev/null | tail -1)"
else
  warn "wrangler требует Node >= 22.12. Установите Node 22 (например: nvm install 22) и повторите."
fi

# --- Nix через nix-portable (без sudo) ---
case "$ARCH" in
  amd64) NP_ARCH=x86_64 ;;
  arm64) NP_ARCH=aarch64 ;;
esac

if have nix && [ "${FORCE:-0}" != "1" ]; then
  ok "nix уже доступен: $(nix --version 2>/dev/null | head -1)"
else
  log "Скачиваю nix-portable"
  fetch "https://github.com/DavHau/nix-portable/releases/download/v012/nix-portable-${NP_ARCH}" "$BIN/nix"
  chmod +x "$BIN/nix"
  for c in nix-shell nix-build nix-store nix-env; do
    ln -sf nix "$BIN/$c"
  done
  ok "nix-portable установлен в $BIN/nix"
fi

# Фолбэк-обёртка через контейнер (если nix-portable не завёлся)
cat >"$BIN/nix-docker" <<EOF
#!/usr/bin/env bash
# Запасной путь: Nix в контейнере. Пробрасывает cwd и docker.sock (для docker load).
set -euo pipefail
args=(-i)
[ -t 0 ] && [ -t 1 ] && args+=(-t)
exec docker run --rm "\${args[@]}" \\
  -v "\$PWD:/work" -w /work \\
  -v /var/run/docker.sock:/var/run/docker.sock \\
  -e NIX_CONFIG="experimental-features = nix-command flakes" \\
  ${NIX_IMAGE} nix "\$@"
EOF
chmod +x "$BIN/nix-docker"
ok "создан $BIN/nix-docker (фолбэк)"

if have nix; then
  log "Прогреваю nix-portable (первый запуск скачивает бандл, может занять время)"
  timeout 300 nix --version 2>&1 | head -3 || warn "nix-portable пока не прогрет; запустите 'nix --version' вручную"
fi
