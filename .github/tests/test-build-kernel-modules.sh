#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
kernel_root="$work/kernel"
artifact_dir="$work/artifacts"
fake_bin="$work/bin"
module_root="$kernel_root/drivers/staging/qcacld-3.0"
mkdir -p "$module_root" "$kernel_root/out" "$artifact_dir" "$fake_bin"
printf 'CONFIG_QCA_CLD_WLAN=m\n' > "$module_root/Makefile"
printf 'config QCA_CLD_WLAN\n' > "$module_root/Kconfig"
printf '%s\n' \
  'UMAC_TARGET_GPIO_INC := -I $(srctree)/$(WLAN_COMMON_INC)/target_if/gpio' \
  'UMAC_GPIO_INC += -I $(srctree)/$(WLAN_COMMON_INC)/$(UMAC_TARGET_GPIO_INC)' \
  > "$module_root/Kbuild"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "$@" > "$FAKE_MAKE_ARGS"' \
  'kernel_root= output_dir= module_rel=' \
  'previous=' \
  'for arg in "$@"; do' \
  '  if [[ "$previous" == -C ]]; then kernel_root=$arg; fi' \
  '  case "$arg" in O=*) output_dir=${arg#O=} ;; M=*) module_rel=${arg#M=} ;; esac' \
  '  previous=$arg' \
  'done' \
  '[[ -n "$kernel_root" && -n "$output_dir" && -n "$module_rel" ]]' \
  '[[ "$module_rel" != /* ]]' \
  'mkdir -p "$output_dir/$module_rel"' \
  'printf fake-module > "$output_dir/$module_rel/wlan.ko"' \
  > "$fake_bin/make"
chmod +x "$fake_bin/make"

PATH="$fake_bin:$PATH" \
FAKE_MAKE_ARGS="$work/make.args" \
GITHUB_ENV="$work/github.env" \
KERNEL_ROOT="$kernel_root" \
OUT_DIR=out \
ARTIFACT_DIR="$artifact_dir" \
PACKAGE_AK3=true \
KERNEL_RELEASE=4.19.325-test \
  bash "$repo_root/.github/scripts/build-kernel-modules.sh"

test -f "$artifact_dir/modules/vendor/lib/modules/wlan.ko"
grep -qx 'WLAN_MODULE_STATUS=built' "$work/github.env"
grep -qx 'WLAN_MODULE_NAMES=wlan.ko' "$work/github.env"
grep -qx 'KERNELRELEASE=4.19.325-test' "$work/make.args"
grep -qx -- "-C" "$work/make.args"
grep -qx "$kernel_root" "$work/make.args"
grep -qx "O=$kernel_root/out" "$work/make.args"
grep -qx 'M=drivers/staging/qcacld-3.0' "$work/make.args"
grep -qx 'CONFIG_QCA_CLD_WLAN=m' "$work/make.args"
grep -qx 'modules' "$work/make.args"
! grep -q '^M=/' "$work/make.args"
! grep -q '^WLAN_ROOT=' "$work/make.args"
! grep -q '^MODNAME=' "$work/make.args"
grep -Fqx 'UMAC_GPIO_INC += $(UMAC_TARGET_GPIO_INC)' "$module_root/Kbuild"
! grep -Fq -- '-I $(srctree)/$(WLAN_COMMON_INC)/$(UMAC_TARGET_GPIO_INC)' "$module_root/Kbuild"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'dest=${!#}' \
  'mkdir -p "$dest/tools" "$dest/modules/system/lib/modules"' \
  ': > "$dest/tools/ak3-core.sh"' \
  ': > "$dest/modules/system/lib/modules/placeholder"' \
  > "$fake_bin/git"
chmod +x "$fake_bin/git"
mkdir -p "$kernel_root/out/arch/arm64/boot"
printf fake-image > "$kernel_root/out/arch/arm64/boot/Image.gz-dtb"

PATH="$fake_bin:$PATH" \
GITHUB_ENV="$work/package.env" \
KERNEL_ROOT="$kernel_root" \
OUT_DIR=out \
ARTIFACT_DIR="$artifact_dir" \
PACKAGE_AK3=true \
WLAN_MODULE_STATUS=built \
AK3_KERNEL_TARGET=Image.gz-dtb \
CODENAME=polaris \
  bash "$repo_root/.github/scripts/package-anykernel.sh"

ak3_zip="$artifact_dir/polaris-SukiSU-Non-GKI-AK3.zip"
test -f "$ak3_zip"
unzip -l "$ak3_zip" | grep -q 'modules/vendor/lib/modules/wlan.ko'
! unzip -l "$ak3_zip" | grep -q 'modules/modules/'
unzip -p "$ak3_zip" anykernel.sh | grep -qx 'do.modules=1'
unzip -p "$ak3_zip" anykernel.sh | grep -qx 'IS_SLOT_DEVICE=auto;'
unzip -p "$ak3_zip" anykernel.sh | grep -qx 'SLOT_SELECT=active;'

mtk_root="$work/mtk-kernel"
mkdir -p "$mtk_root"
rm -f "$work/make.args"
: > "$work/mtk.env"
PATH="$fake_bin:$PATH" \
FAKE_MAKE_ARGS="$work/make.args" \
GITHUB_ENV="$work/mtk.env" \
KERNEL_ROOT="$mtk_root" \
OUT_DIR=out \
ARTIFACT_DIR="$work/mtk-artifacts" \
PACKAGE_AK3=true \
  bash "$repo_root/.github/scripts/build-kernel-modules.sh"

test ! -e "$work/make.args"
test ! -e "$work/mtk-artifacts/modules"
grep -qx 'WLAN_MODULE_STATUS=skipped' "$work/mtk.env"

echo '[+] kernel module tests passed'
