#!/usr/bin/env bash
# Infrastructure as Code: OpenTofu (+ shim terraform), Pulumi, tflint.
# Примечание: релизы releases.hashicorp.com в этом окружении недоступны,
# поэтому Terraform ставится как OpenTofu (курс официально поддерживает OpenTofu)
# плюс обёртка `terraform`, вызывающая `tofu`.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# --- OpenTofu ---
if have tofu && [ "${FORCE:-0}" != "1" ]; then
  ok "OpenTofu уже установлен: $(tofu version | head -1)"
else
  install_tar_member \
    "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${ARCH}.tar.gz" \
    tofu tofu
fi

# --- terraform shim ---
if have terraform; then
  ok "terraform найден: $(terraform version 2>/dev/null | head -1)"
else
  cat >"$BIN/terraform" <<'EOF'
#!/usr/bin/env bash
# Shim: Terraform-совместимый CLI на базе OpenTofu (tofu).
exec tofu "$@"
EOF
  chmod +x "$BIN/terraform"
  ok "Создан shim $BIN/terraform -> tofu"
fi

# --- Pulumi ---
if have pulumi && [ "${FORCE:-0}" != "1" ]; then
  ok "Pulumi уже установлен: $(pulumi version)"
else
  install_pulumi_tar \
    "https://github.com/pulumi/pulumi/releases/download/v${PULUMI_VERSION}/pulumi-v${PULUMI_VERSION}-linux-${PULUMI_ARCH}.tar.gz"
fi

# --- tflint ---
if have tflint && [ "${FORCE:-0}" != "1" ]; then
  ok "tflint уже установлен: $(tflint --version | head -1)"
else
  install_zip_member \
    "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${ARCH}.zip" \
    tflint tflint
fi
