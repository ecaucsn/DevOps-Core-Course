#!/usr/bin/env bash
# Проверка окружения перед установкой. Ничего не меняет.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

log "ОС: $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -s)"
log "Архитектура: $(uname -m) -> $ARCH"
log "CPU: $(nproc) ядер"
log "RAM: $(free -h 2>/dev/null | awk '/^Mem:/{print $2" всего, "$7" доступно"}' || echo n/a)"
log "Диск ($HOME): $(df -h "$HOME" | awk 'NR==2{print $4" свободно"}')"

have docker || die "Docker не найден. Установите Docker Engine 23+."
docker info >/dev/null 2>&1 || die "Демон Docker недоступен. Проверьте, что вы в группе docker и он запущен."
ok "Docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
if docker compose version >/dev/null 2>&1; then
  ok "Docker Compose: $(docker compose version --short 2>/dev/null)"
else
  warn "Docker Compose v2 не найден (нужен для лаб. 6-8)."
fi

have git && ok "git: $(git --version)" || warn "git не найден"
have curl || die "curl не найден"
have jq || warn "jq не найден (нужен для части проверок)"
have unzip || warn "unzip не найден (нужен для tflint)"
have tar || die "tar не найден"

case ":$PATH:" in
  *":$BIN:"*) ok "$BIN уже в PATH" ;;
  *) warn "$BIN НЕ в PATH. Добавьте: export PATH=\"$BIN:\$PATH\"" ;;
esac

for u in https://github.com https://dl.k8s.io/release/stable.txt https://get.helm.sh https://pypi.org; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -I "$u" 2>/dev/null || echo ERR)
  log "сеть: $u -> $code"
done

[ -e /dev/kvm ] && ok "/dev/kvm есть (можно поднять локальную VM через Multipass)" || warn "/dev/kvm нет"

log "Проверка завершена."
