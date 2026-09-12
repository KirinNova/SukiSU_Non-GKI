#!/usr/bin/env bash
set -euo pipefail
cd "${KERNEL_ROOT:?}"; out=${OUT_DIR:-out}; export ARCH=${ARCH:-arm64} SUBARCH=${SUBARCH:-$ARCH}
export KBUILD_BUILD_USER=${AUTHOR:-XiZi} KBUILD_BUILD_HOST=GitHub-Actions KBUILD_BUILD_TIMESTAMP=${BUILD_TIME:-$(date -u '+%Y-%m-%d %H:%M:%S')}
mkdir -p "$out"; config_targets=("${DEFCONFIG_RESOLVED:?}")
[[ -n "${DEVICE_CONFIG_RESOLVED:-}" ]] && config_targets+=("$DEVICE_CONFIG_RESOLVED")
[[ "${INTEGRATE_DROIDSPACES:-false}" == true ]] && config_targets+=(droidspaces.config)
make O="$out" "${config_targets[@]}"
if [[ "${DISABLE_LTO:-false}" == true ]]; then for key in CONFIG_LTO CONFIG_LTO_CLANG CONFIG_LTO_CLANG_THIN CONFIG_LTO_CLANG_FULL CONFIG_THINLTO; do sed -i "s/^${key}=y/# ${key} is not set/" "$out/.config"; done; echo CONFIG_LTO_NONE=y >> "$out/.config"; fi
date_part=$(date -u -d "$KBUILD_BUILD_TIMESTAMP" +%Y%m%d 2>/dev/null || date -u +%Y%m%d); local="-${KERNEL_NAME:-by_XiZi}-${KERNEL_VERSION:-v1.0}-$date_part"
sed -i '/^CONFIG_LOCALVERSION=/d' "$out/.config"; printf 'CONFIG_LOCALVERSION="%s"\n' "$local" >> "$out/.config"; make O="$out" olddefconfig
release=$(make O="$out" -s kernelrelease); [[ ${#release} -le 64 ]] || { echo "[ERROR] kernelrelease is ${#release} characters (>64): $release" >&2; exit 1; }; echo "KERNEL_RELEASE=$release" >> "$GITHUB_ENV"
