#!/usr/bin/env bash
set -euo pipefail
[[ "${INTEGRATE_SUSFS:-false}" == true ]] || { echo '[+] SUSFS integration disabled'; exit 0; }
cd "${KERNEL_ROOT:?}"; patch_root=${PATCH_ROOT:?}
patch_file="$patch_root/Patch/susfs_patch_to_${SOURCE_KERNEL_VERSION}.patch"
diagnostics="${ARTIFACT_DIR:?}/susfs-diagnostics"
mkdir -p "$diagnostics"
if [[ ! -f "$patch_file" ]]; then
  printf '[ERROR] no SUSFS patch for kernel %s\n' "$SOURCE_KERNEL_VERSION" | tee "$diagnostics/susfs-patch.log" >&2
  if [[ -n "${GITHUB_ENV:-}" ]]; then printf 'SUSFS_PATCH_STATUS=missing\n' >> "$GITHUB_ENV"; fi
  exit 1
fi
cp "$patch_file" "$diagnostics/"
if [[ -n "${GITHUB_ENV:-}" ]]; then printf 'SUSFS_PATCH_STATUS=applying\n' >> "$GITHUB_ENV"; fi

set +e
patch --forward --batch -p1 < "$patch_file" 2>&1 | tee "$diagnostics/susfs-patch.log"
patch_status=${PIPESTATUS[0]}
set -e
if (( patch_status != 0 )); then
  if [[ -n "${GITHUB_ENV:-}" ]]; then printf 'SUSFS_PATCH_STATUS=failed\n' >> "$GITHUB_ENV"; fi
  echo '[ERROR] SUSFS patch failed; reject files and patch log will be uploaded as build artifacts' >&2
  exit "$patch_status"
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then printf 'SUSFS_PATCH_STATUS=applied\n' >> "$GITHUB_ENV"; fi

set +e
bash "$patch_root/susfs_inline_hook_patches.sh" 2>&1 | tee "$diagnostics/susfs-inline-hooks.log"
hook_status=${PIPESTATUS[0]}
set -e
if (( hook_status != 0 )); then
  if [[ -n "${GITHUB_ENV:-}" ]]; then printf 'SUSFS_INLINE_HOOK_STATUS=failed\n' >> "$GITHUB_ENV"; fi
  echo '[ERROR] SUSFS inline hook patching failed; diagnostics will be uploaded as build artifacts' >&2
  exit "$hook_status"
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then printf 'SUSFS_INLINE_HOOK_STATUS=applied\n' >> "$GITHUB_ENV"; fi
echo '[+] SUSFS and inline hooks applied'
