#!/usr/bin/env bash
set -euo pipefail
[[ "${INTEGRATE_SUSFS:-false}" == true ]] || { echo '[+] SUSFS integration disabled'; exit 0; }
cd "${KERNEL_ROOT:?}"; patch_root=${PATCH_ROOT:?}
patch_file="$patch_root/Patch/susfs_patch_to_${SOURCE_KERNEL_VERSION}.patch"
[[ -f "$patch_file" ]] || { echo "[ERROR] no SUSFS patch for kernel $SOURCE_KERNEL_VERSION" >&2; exit 1; }
patch --forward --batch -p1 < "$patch_file"
[[ ! -e "$patch_file.rej" ]] || { echo '[ERROR] SUSFS patch produced rejects' >&2; exit 1; }
bash "$patch_root/susfs_inline_hook_patches.sh"
echo '[+] SUSFS and inline hooks applied'
