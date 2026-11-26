#!/usr/bin/env bash
# Ansible: ansible-core (через uv tool), коллекции, ansible-lint.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

have uv || die "uv не найден. Сначала запустите 10-base.sh"

# --- ansible-core ---
if have ansible && [ "${FORCE:-0}" != "1" ]; then
  ok "ansible-core уже установлен: $(ansible --version | head -1)"
else
  log "Устанавливаю ansible-core"
  uv tool install --force ansible-core
  ok "ansible-core -> $(ansible --version | head -1)"
fi

# --- ansible-lint ---
if have ansible-lint && [ "${FORCE:-0}" != "1" ]; then
  ok "ansible-lint уже установлен: $(ansible-lint --version | head -1)"
else
  log "Устанавливаю ansible-lint"
  uv tool install --force ansible-lint
  ok "ansible-lint -> $(ansible-lint --version | head -1)"
fi

# --- коллекции ---
log "Устанавливаю коллекции community.docker, community.general"
ansible-galaxy collection install community.docker community.general
ansible-galaxy collection list 2>/dev/null | grep -E 'community\.(docker|general)' || true
ok "Ansible готов"
