#!/usr/bin/env bash
# Общие помощники для пользовательской установки без sudo.
set -euo pipefail

export PREFIX="${PREFIX:-$HOME/.local}"
export BIN="$PREFIX/bin"
mkdir -p "$BIN"

# Актуальные версии на момент установки (переопределяются переменными окружения).
: "${UV_VERSION:=0.13.10}"
: "${TRIVY_VERSION:=0.76.2}"
: "${YQ_VERSION:=4.54.3}"
: "${TOFU_VERSION:=1.13.10}"
: "${PULUMI_VERSION:=3.278.0}"
: "${TFLINT_VERSION:=0.66.0}"
: "${K3D_VERSION:=5.9.0}"
: "${HELM_VERSION:=4.3.2}"
: "${ARGOCD_VERSION:=3.6.3}"
: "${ARGO_ROLLOUTS_VERSION:=1.10.2}"
: "${OPENBAO_VERSION:=2.7.3}"
: "${NIX_IMAGE:=nixos/nix:2.34.0}"
: "${KUBECTL_VERSION:=}" # пусто => последняя стабильная

case "$(uname -m)" in
  x86_64 | amd64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *)
    echo "Неподдерживаемая архитектура: $(uname -m)" >&2
    exit 1
    ;;
esac

case "$ARCH" in
  amd64) UV_ARCH=x86_64-unknown-linux-gnu; PULUMI_ARCH=x64 ;;
  arm64) UV_ARCH=aarch64-unknown-linux-gnu; PULUMI_ARCH=arm64 ;;
esac

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[err]\033[0m %s\n' "$*" >&2
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

fetch() { curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$2" "$1"; }

# install_file <url> <имя_в_BIN> [флаг_версии]
install_direct() {
  local url="$1" name="$2" flag="${3:---version}"
  log "Устанавливаю $name"
  fetch "$url" "$BIN/$name"
  chmod +x "$BIN/$name"
  ok "$name -> $("$BIN/$name" "$flag" 2>/dev/null | head -1 || echo installed)"
}

# install_tar_member <url> <имя_члена> <имя_в_BIN>
install_tar_member() {
  local url="$1" member="$2" dest="$3" d f
  d=$(mktemp -d)
  log "Скачиваю $url"
  fetch "$url" "$d/archive.tgz"
  tar -xzf "$d/archive.tgz" -C "$d"
  f=$(find "$d" -type f -name "$member" | head -1)
  [ -n "$f" ] || {
    rm -rf "$d"
    die "в архиве не найден $member"
  }
  install -m 0755 "$f" "$BIN/$dest"
  rm -rf "$d"
  ok "$dest установлен в $BIN"
}

# install_zip_member <url> <имя_члена> <имя_в_BIN>
install_zip_member() {
  local url="$1" member="$2" dest="$3" d f
  d=$(mktemp -d)
  log "Скачиваю $url"
  fetch "$url" "$d/archive.zip"
  unzip -q -o "$d/archive.zip" -d "$d"
  f=$(find "$d" -type f -name "$member" | head -1)
  [ -n "$f" ] || {
    rm -rf "$d"
    die "в архиве не найден $member"
  }
  install -m 0755 "$f" "$BIN/$dest"
  rm -rf "$d"
  ok "$dest установлен в $BIN"
}

# install_pulumi_tar <url>
install_pulumi_tar() {
  local url="$1" d f
  d=$(mktemp -d)
  log "Скачиваю $url"
  fetch "$url" "$d/pulumi.tgz"
  tar -xzf "$d/pulumi.tgz" -C "$d"
  f=$(find "$d" -type f -name pulumi | head -1)
  [ -n "$f" ] || {
    rm -rf "$d"
    die "в архиве не найден pulumi"
  }
  install -m 0755 "$f" "$BIN/pulumi"
  rm -rf "$d"
  ok "pulumi установлен в $BIN"
}
