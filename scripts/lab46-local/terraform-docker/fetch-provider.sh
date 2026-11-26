#!/usr/bin/env bash
# Обходит недоступный реестр провайдеров: скачивает Docker-провайдер с GitHub
# и раскладывает его в локальное filesystem-зеркало для OpenTofu.
set -euo pipefail
cd "$(dirname "$0")"

PROVIDER_VERSION="${PROVIDER_VERSION:-4.7.0}"
ARCH="${ARCH:-amd64}"
MIRROR="$PWD/mirror"
DEST="$MIRROR/registry.opentofu.org/kreuzwerker/docker/${PROVIDER_VERSION}/linux_${ARCH}"
BIN="$DEST/terraform-provider-docker_v${PROVIDER_VERSION}"
URL="https://github.com/kreuzwerker/terraform-provider-docker/releases/download/v${PROVIDER_VERSION}/terraform-provider-docker_${PROVIDER_VERSION}_linux_${ARCH}.zip"

mkdir -p "$DEST"
if [ ! -x "$BIN" ]; then
  echo "==> Скачиваю Docker-провайдер v${PROVIDER_VERSION}"
  d=$(mktemp -d)
  curl -fsSL --retry 3 -o "$d/p.zip" "$URL"
  unzip -q -o "$d/p.zip" -d "$d"
  install -m 0755 "$d/terraform-provider-docker_v${PROVIDER_VERSION}" "$BIN"
  rm -rf "$d"
fi

cat >.terraformrc <<EOF
provider_installation {
  filesystem_mirror {
    path    = "$MIRROR"
    include = ["registry.opentofu.org/kreuzwerker/docker"]
  }
  direct {
    exclude = ["registry.opentofu.org/kreuzwerker/docker"]
  }
}
EOF

echo "Провайдер готов: $BIN"
echo "Перед запуском выполните:"
echo "  export TF_CLI_CONFIG_FILE=$PWD/.terraformrc"
