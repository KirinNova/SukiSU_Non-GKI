#!/usr/bin/env bash
set -euo pipefail
die() { echo "[ERROR] $*" >&2; exit 1; }
: "${CODENAME:?CODENAME is required}"
: "${KERNEL_REPO:?KERNEL_REPO is required}"
[[ "$CODENAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "codename contains unsupported characters"
[[ "$KERNEL_REPO" == *.git ]] || die "kernel repository must be a complete .git URL"
[[ -n "${AUTHOR:-}" ]] || die "author must not be empty"
[[ -z "${DEFCONFIG:-}" || "$DEFCONFIG" == *_defconfig ]] || die "defconfig must end with _defconfig"
[[ -z "${DEVICE_CONFIG:-}" || "$DEVICE_CONFIG" == *.config ]] || die "device config must end with .config"
[[ -z "${BUILD_TIME:-}" || "$BUILD_TIME" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}:[0-9]{2})?)?$ ]] || die "build time must be ISO-8601"
for name in AB_PARTITION DISABLE_LTO INTEGRATE_SUSFS INTEGRATE_DROIDSPACES PACKAGE_AK3; do case "${!name:-false}" in true|false) ;; *) die "$name must be true or false" ;; esac; done
export KERNEL_NAME=${KERNEL_NAME:-by_XiZi} KERNEL_VERSION=${KERNEL_VERSION:-v1.0} ARCH=${ARCH:-arm64} BUILD_TARGET=${BUILD_TARGET:-Image.gz-dtb} OUT_DIR=${OUT_DIR:-out}
printf '[+] Inputs validated: %s (%s), defconfig=%s, config=%s\n' "$CODENAME" "$KERNEL_REPO" "${DEFCONFIG:-auto}" "${DEVICE_CONFIG:-none}"
