#!/usr/bin/env bash
# Smoke-тесты установленных инструментов.
#   ./verify.sh            # быстрые проверки
#   ./verify.sh --cluster  # плюс создание/удаление тестового k3d-кластера
set -uo pipefail
source "$(dirname "$0")/lib.sh"

with_cluster=0
[ "${1:-}" = "--cluster" ] && with_cluster=1

fail=0
check() { # команда, аргументы
  local c="$1"
  shift
  if have "$c"; then
    printf '  \033[1;32m✓\033[0m %-22s %s\n' "$c" "$("$@" 2>&1 | head -1)"
  else
    printf '  \033[1;31m✗\033[0m %-22s НЕ НАЙДЕН\n' "$c"
    fail=$((fail + 1))
  fi
}

log "Версии инструментов"
check docker docker --version
check docker docker compose version
check git git --version
check uv uv --version
check trivy trivy --version
check yq yq --version
check tofu tofu version
check terraform terraform version
check pulumi pulumi version
check tflint tflint --version
check ansible ansible --version
check ansible-playbook ansible-playbook --version
check ansible-lint ansible-lint --version
check kubectl kubectl version --client
check k3d k3d version
check helm helm version --short
check argocd argocd version --client
check kubectl-argo-rollouts kubectl-argo-rollouts version
check bao bao version
check node node --version
check npm npm --version
check wrangler wrangler --version
check nix nix --version

echo
if [ "$with_cluster" = "1" ]; then
  log "Тест k3d: создаю временный кластер verify"
  if k3d cluster create verify --wait >/dev/null 2>&1; then
    kubectl get nodes || true
    k3d cluster delete verify >/dev/null 2>&1 && ok "кластер k3d создаётся и удаляется"
  else
    warn "не удалось создать k3d-кластер (проверьте Docker/ресурсы)"
    fail=$((fail + 1))
  fi
fi

echo
if [ "$fail" -eq 0 ]; then
  ok "Все проверки пройдены."
else
  warn "Проблем: $fail. См. вывод выше. Полный список — в INFRASTRUCTURE.md."
fi
exit 0
