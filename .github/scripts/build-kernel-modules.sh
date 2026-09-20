#!/usr/bin/env bash
set -euo pipefail

die() { echo "[ERROR] $*" >&2; exit 1; }
root=${KERNEL_ROOT:?KERNEL_ROOT is required}
out=${OUT_DIR:-out}
artifact=${ARTIFACT_DIR:?ARTIFACT_DIR is required}
module_root="$root/drivers/staging/qcacld-3.0"
status=skipped
module_path=vendor/lib/modules
if [[ "$out" == /* ]]; then
  out_abs=$out
else
  out_abs="$root/$out"
fi

write_status() {
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf 'WLAN_MODULE_STATUS=%s\nWLAN_MODULE_PATH=%s\n' "$status" "$module_path" >> "$GITHUB_ENV"
  fi
}
trap write_status EXIT

# The qcacld tree is an external Qualcomm module.  Do not touch any other
# kernel family, and do not make a module build a prerequisite for raw image
# artifacts unless an AK3 package was requested.
if [[ "${PACKAGE_AK3:-false}" != true ]]; then
  echo '[+] WLAN module build skipped (AnyKernel3 packaging disabled)'
  exit 0
fi
if [[ ! -f "$module_root/Makefile" || ! -f "$module_root/Kconfig" ]]; then
  echo '[+] WLAN module build skipped (qcacld-3.0 is not present)'
  exit 0
fi
grep -q 'CONFIG_QCA_CLD_WLAN' "$module_root/Makefile" || {
  echo '[+] WLAN module build skipped (unrecognised qcacld build layout)'
  exit 0
}

mkdir -p "$artifact/modules/vendor/lib/modules"
echo '[+] Building Qualcomm qcacld-3.0 WLAN module'
cd "$module_root"
kernel_kcflags=${KCFLAGS:-}
if [[ "${IGNORE_WERROR_REQUESTED:-false}" == true ]]; then
  kernel_kcflags="${kernel_kcflags:+$kernel_kcflags }-Wno-error"
fi
make_args=(
  -j"$(nproc)" -C "$module_root"
  KERNEL_SRC="$root" KBUILD_OUTPUT="$out_abs" M="$module_root"
  ARCH="${ARCH:-arm64}" CC="${CC:-clang}" LD="${LD:-ld.lld}"
  CLANG_TRIPLE="${CLANG_TRIPLE:-aarch64-linux-gnu-}"
  CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
  CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32:-arm-linux-gnueabi-}"
  KCFLAGS="$kernel_kcflags"
)
[[ -n "${KERNEL_RELEASE:-}" ]] && make_args+=("KERNELRELEASE=$KERNEL_RELEASE")
make_args+=(all)
set +e
make "${make_args[@]}" 2>&1 | tee "$artifact/wlan-module-build.log"
build_rc=${PIPESTATUS[0]}
set -e
[[ $build_rc -eq 0 ]] || die "qcacld-3.0 WLAN module build failed (exit $build_rc)"

mapfile -t modules < <(find "$module_root" -maxdepth 1 -type f -name '*.ko' -print | sort)
[[ ${#modules[@]} -gt 0 ]] || die 'qcacld build completed but produced no .ko module'
for module in "${modules[@]}"; do
  cp -f "$module" "$artifact/modules/vendor/lib/modules/"
done
status=built
module_names=$(printf '%s ' "${modules[@]##*/}")
module_names=${module_names% }
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'WLAN_MODULE_NAMES=%s\n' "$module_names" >> "$GITHUB_ENV"
fi
echo "[+] WLAN module(s): $module_names"
