#!/usr/bin/env bash
# Локальная «VM» для лаб. 4-6: контейнер Ubuntu 24.04 с SSH и sudo.
# Полностью локально и бесплатно (реальный systemd не нужен для лаб. 5-6).
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p .ssh
KEY=.ssh/lab46
if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -N '' -C lab46-target -f "$KEY"
fi
cp "$KEY.pub" authorized_keys
chmod 600 "$KEY"

echo "==> Собираю образ devops-target:24.04"
docker build -f Dockerfile.target -t devops-target:24.04 .

echo "==> Перезапускаю контейнер lab46-target"
docker rm -f lab46-target >/dev/null 2>&1 || true
docker run -d --name lab46-target -p 2222:22 -p 8080:80 devops-target:24.04

echo
echo "Готово. Цель:"
echo "  host: 127.0.0.1  port: 2222  user: ansible  key: $PWD/$KEY"
echo
echo "Проверка:"
echo "  ssh -i $PWD/$KEY -p 2222 ansible@127.0.0.1 'sudo whoami'   # => root"
echo
echo "Инвентарь для Ansible:"
echo "  ansible -i inventory.ssh.ini web -m ping"
