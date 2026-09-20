#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fake_bin="$work/bin"
mkdir -p "$fake_bin"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'out=out' \
  'for arg in "$@"; do' \
  '  case "$arg" in O=*) out=${arg#O=} ;; esac' \
  'done' \
  'if [[ " $* " == *" kernelrelease "* ]]; then' \
  "  printf '%s\\n' '4.19.325-test'" \
  '  exit 0' \
  'fi' \
  'if [[ " $* " == *" test_defconfig "* ]]; then' \
  '  mkdir -p "$out"' \
  "  printf '%s\\n' '# CONFIG_QCA_CLD_WLAN is not set' > \"\$out/.config\"" \
  'fi' \
  > "$fake_bin/make"
chmod +x "$fake_bin/make"

run_configure() {
  local kernel_root=$1 github_env=$2
  PATH="$fake_bin:$PATH" \
  GITHUB_ENV="$github_env" \
  KERNEL_ROOT="$kernel_root" \
  OUT_DIR=out \
  DEFCONFIG_RESOLVED=test_defconfig \
  KERNEL_NAME=test \
  KERNEL_VERSION=v1 \
  BUILD_TIME='2026-09-20 00:00:00' \
    bash "$repo_root/.github/scripts/configure-kernel.sh"
}

qcom_root="$work/qcom-kernel"
qcom_env="$work/qcom.env"
module_root="$qcom_root/drivers/staging/qcacld-3.0"
mkdir -p "$module_root" \
  "$qcom_root/drivers/staging/qca-wifi-host-cmn" \
  "$qcom_root/drivers/staging/fw-api"
printf '%s\n' 'config QCA_CLD_WLAN' 'tristate "Qualcomm WLAN"' > "$module_root/Kconfig"
printf '%s\n' \
  'UMAC_TARGET_GPIO_INC := -I $(srctree)/$(WLAN_COMMON_INC)/target_if/gpio' \
  'UMAC_GPIO_INC += -I $(srctree)/$(WLAN_COMMON_INC)/$(UMAC_TARGET_GPIO_INC)' \
  > "$module_root/Kbuild"
: > "$qcom_env"
run_configure "$qcom_root" "$qcom_env"

grep -qx 'CONFIG_QCA_CLD_WLAN=y' "$qcom_root/out/.config"
grep -Fqx 'UMAC_GPIO_INC += $(UMAC_TARGET_GPIO_INC)' "$module_root/Kbuild"
! grep -Fq -- '-I $(srctree)/$(WLAN_COMMON_INC)/$(UMAC_TARGET_GPIO_INC)' "$module_root/Kbuild"
grep -qx 'WLAN_DRIVER_STATUS=builtin' "$qcom_env"

other_root="$work/other-kernel"
other_env="$work/other.env"
mkdir -p "$other_root"
: > "$other_env"
run_configure "$other_root" "$other_env"

grep -qx '# CONFIG_QCA_CLD_WLAN is not set' "$other_root/out/.config"
grep -qx 'WLAN_DRIVER_STATUS=not-present' "$other_env"

artifact_dir="$work/artifacts"
mkdir -p "$qcom_root/out/arch/arm64/boot" "$artifact_dir"
printf fake-image > "$qcom_root/out/arch/arm64/boot/Image.gz-dtb"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'dest=${!#}' \
  'mkdir -p "$dest/tools" "$dest/modules/system/lib/modules"' \
  ': > "$dest/tools/ak3-core.sh"' \
  ': > "$dest/modules/system/lib/modules/placeholder"' \
  > "$fake_bin/git"
chmod +x "$fake_bin/git"

PATH="$fake_bin:$PATH" \
GITHUB_ENV="$work/package.env" \
KERNEL_ROOT="$qcom_root" \
OUT_DIR=out \
ARTIFACT_DIR="$artifact_dir" \
PACKAGE_AK3=true \
WLAN_DRIVER_STATUS=builtin \
AK3_KERNEL_TARGET=Image.gz-dtb \
CODENAME=polaris \
  bash "$repo_root/.github/scripts/package-anykernel.sh"

ak3_zip="$artifact_dir/polaris-SukiSU-Non-GKI-AK3.zip"
test -f "$ak3_zip"
unzip -p "$ak3_zip" anykernel.sh | grep -qx 'do.modules=0'
! unzip -l "$ak3_zip" | grep -q 'modules/'
unzip -p "$ak3_zip" README_FLASH.txt | grep -qx 'Qualcomm WLAN driver: builtin'

echo '[+] built-in WLAN tests passed'
