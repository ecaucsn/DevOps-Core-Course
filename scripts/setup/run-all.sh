#!/usr/bin/env bash
# Последовательно выполняет все фазы установки и проверку.
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"

for s in 00-preflight.sh 10-base.sh 20-iac.sh 30-ansible.sh 40-k8s.sh 50-edge-nix.sh; do
  echo
  echo "############################################################"
  echo "# $s"
  echo "############################################################"
  bash "$dir/$s"
done

echo
bash "$dir/verify.sh"
