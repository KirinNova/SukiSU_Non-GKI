#!/usr/bin/env bash
set -euo pipefail
[[ "${INTEGRATE_SUSFS:-false}" == true ]] || { echo '[+] SUSFS integration disabled'; exit 0; }
cd "${KERNEL_ROOT:?}"; patch_root=${PATCH_ROOT:?}
patch_file="$patch_root/Patch/susfs_patch_to_${SOURCE_KERNEL_VERSION}.patch"
diagnostics="${ARTIFACT_DIR:?}/susfs-diagnostics"
mkdir -p "$diagnostics"
set_github_env() {
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"
  fi
}
if [[ ! -f "$patch_file" ]]; then
  printf '[ERROR] no SUSFS patch for kernel %s\n' "$SOURCE_KERNEL_VERSION" | tee "$diagnostics/susfs-patch.log" >&2
  set_github_env SUSFS_PATCH_STATUS missing
  set_github_env SUSFS_DEVICE_OVERLAP_STATUS not-run
  exit 1
fi
cp "$patch_file" "$diagnostics/"
set_github_env SUSFS_PATCH_STATUS applying
set_github_env SUSFS_DEVICE_OVERLAP_STATUS not-needed

# Preserve diagnostics which may already exist in a vendor tree. Only artifacts
# created by this patch attempt are removed after overlap verification succeeds.
mapfile -d '' existing_patch_artifacts < <(
  find . -type f \( -name '*.rej' -o -name '*.orig' \) -print0
)
cleanup_new_patch_artifacts() {
  local file previous known
  while IFS= read -r -d '' file; do
    known=false
    for previous in "${existing_patch_artifacts[@]}"; do
      if [[ "$file" == "$previous" ]]; then
        known=true
        break
      fi
    done
    [[ "$known" == true ]] || rm -f -- "$file"
  done < <(find . -type f \( -name '*.rej' -o -name '*.orig' \) -print0)
}
is_existing_patch_artifact() {
  local candidate=$1 previous
  for previous in "${existing_patch_artifacts[@]}"; do
    [[ "$candidate" == "$previous" ]] && return 0
  done
  return 1
}
apply_device_repairs() {
  local repair_root="${ARTIFACT_DIR:?}/device-patches"
  local repair_manifest="$repair_root/susfs-repair.txt"
  local coverage_file="$diagnostics/device-repair-covered-paths.txt"
  local rejects_dir="$diagnostics/rejected-before-device-repair"
  local patch_name repair_patch rejected_file rejected_path
  local rejected_count=0 repair_count=0

  [[ -s "$repair_manifest" ]] || return 1
  : > "$coverage_file"
  while IFS= read -r patch_name; do
    [[ -n "$patch_name" ]] || continue
    repair_patch="$repair_root/$patch_name"
    [[ -f "$repair_patch" ]] || {
      echo "[ERROR] staged device repair patch is missing: $repair_patch" >&2
      return 1
    }
    sed -n 's#^+++ b/##p' "$repair_patch" | grep -v '^/dev/null$' >> "$coverage_file" || true
  done < "$repair_manifest"
  sort -u -o "$coverage_file" "$coverage_file"

  while IFS= read -r -d '' rejected_file; do
    is_existing_patch_artifact "$rejected_file" && continue
    rejected_path=${rejected_file#./}
    rejected_path=${rejected_path%.rej}
    if ! grep -Fxq -- "$rejected_path" "$coverage_file"; then
      echo "[ERROR] no staged device repair patch covers rejected SUSFS file: $rejected_path" >&2
      return 1
    fi
    rejected_count=$((rejected_count + 1))
  done < <(find . -type f -name '*.rej' -print0)
  (( rejected_count > 0 )) || return 1

  mkdir -p "$rejects_dir"
  while IFS= read -r -d '' rejected_file; do
    is_existing_patch_artifact "$rejected_file" && continue
    cp --parents "$rejected_file" "$rejects_dir/"
  done < <(find . -type f \( -name '*.rej' -o -name '*.orig' \) -print0)

  while IFS= read -r patch_name; do
    [[ -n "$patch_name" ]] || continue
    repair_patch="$repair_root/$patch_name"
    echo "[+] Applying staged SUSFS device repair: $patch_name"
    set +e
    patch --forward --batch -p1 < "$repair_patch" 2>&1 |
      tee -a "$diagnostics/susfs-device-repair.log"
    repair_status=${PIPESTATUS[0]}
    set -e
    if (( repair_status != 0 )); then
      echo "[ERROR] staged SUSFS device repair failed: $patch_name" >&2
      return 1
    fi
    printf '%s\n' "$patch_name" >> "$repair_root/applied-after-susfs.txt"
    repair_count=$((repair_count + 1))
  done < "$repair_manifest"

  cleanup_new_patch_artifacts
  set_github_env SUSFS_REPAIRED_REJECT_COUNT "$rejected_count"
  set_github_env DEVICE_PATCH_REPAIR_APPLIED_COUNT "$repair_count"
  set_github_env DEVICE_PATCH_STATUS applied-as-susfs-repair
  return 0
}

set +e
patch --forward --batch -p1 < "$patch_file" 2>&1 | tee "$diagnostics/susfs-patch.log"
patch_status=${PIPESTATUS[0]}
set -e
if (( patch_status != 0 )); then
  overlap_status=unresolved
  if [[ "${APPLY_DEVICE_PATCHES:-false}" == true ]]; then
    echo '[WARNING] SUSFS forward application reported conflicts; verifying whether device patches already provide every SUSFS hunk'
    set +e
    patch --dry-run --reverse --batch -p1 < "$patch_file" 2>&1 |
      tee "$diagnostics/susfs-device-overlap-verification.log"
    reverse_status=${PIPESTATUS[0]}
    set -e
    if (( reverse_status == 0 )); then
      overlap_status=verified
      cleanup_new_patch_artifacts
      set_github_env SUSFS_PATCH_STATUS applied-with-verified-device-overlap
      set_github_env SUSFS_DEVICE_OVERLAP_STATUS "$overlap_status"
      echo '[+] Full reverse dry-run succeeded; device patches already supplied the rejected SUSFS hunks'
    elif apply_device_repairs; then
      overlap_status=repaired
      set_github_env SUSFS_PATCH_STATUS applied-with-device-repair
      set_github_env SUSFS_DEVICE_OVERLAP_STATUS "$overlap_status"
      echo '[+] Staged device patches repaired every rejected SUSFS file'
    fi
  fi
  if [[ "$overlap_status" != verified && "$overlap_status" != repaired ]]; then
    set_github_env SUSFS_PATCH_STATUS failed
    set_github_env SUSFS_DEVICE_OVERLAP_STATUS "$overlap_status"
    echo '[ERROR] SUSFS patch is not fully present; reject files and patch logs will be uploaded as build artifacts' >&2
    exit "$patch_status"
  fi
else
  set_github_env SUSFS_PATCH_STATUS applied
fi

hook_script="$patch_root/susfs_inline_hook_patches.sh"
[[ -f "$hook_script" ]] || {
  set_github_env SUSFS_INLINE_HOOK_STATUS missing
  echo "[ERROR] SUSFS inline hook script is missing: $hook_script" >&2
  exit 1
}

# Upstream briefly changed the stat hook declaration anchor to the literal
# "lookup_flags = 0". Vendor 4.19 trees commonly initialize it with LOOKUP_*
# flags, so the hook body was inserted without its local fname declaration.
# Broaden only that exact upstream anchor when the target has a compatible
# declaration with a different initializer.
hook_compat_status=not-needed
if [[ -f fs/stat.c ]] &&
   grep -Fq "sed -i '/unsigned int lookup_flags = 0;/a" "$hook_script" &&
   ! grep -Fq 'unsigned int lookup_flags = 0;' fs/stat.c &&
   grep -Eq '^[[:space:]]*unsigned int lookup_flags[[:space:]]*=' fs/stat.c; then
  sed -i 's|/unsigned int lookup_flags = 0;/a|/unsigned int lookup_flags =/a|g' "$hook_script"
  hook_compat_status=normalized-stat-anchor
  echo '[+] normalized SUSFS stat hook anchor for vendor lookup_flags initialization'
fi
set_github_env SUSFS_HOOK_COMPAT_STATUS "$hook_compat_status"

set +e
bash "$hook_script" 2>&1 | tee "$diagnostics/susfs-inline-hooks.log"
hook_status=${PIPESTATUS[0]}
set -e
if (( hook_status != 0 )); then
  set_github_env SUSFS_INLINE_HOOK_STATUS failed
  echo '[ERROR] SUSFS inline hook patching failed; diagnostics will be uploaded as build artifacts' >&2
  exit "$hook_status"
fi

# Do not trust the helper's count-only success message. A body without the
# declaration is syntactically invalid but otherwise looks "patched" to it.
if [[ -f fs/stat.c ]] && grep -q 'fname = getname_flags' fs/stat.c; then
  fname_decl_line=$(grep -n -m1 'struct filename \*fname = NULL;' fs/stat.c | cut -d: -f1 || true)
  fname_use_line=$(grep -n -m1 'fname = getname_flags' fs/stat.c | cut -d: -f1 || true)
  if [[ -z "$fname_decl_line" || -z "$fname_use_line" || "$fname_decl_line" -ge "$fname_use_line" ]]; then
    set_github_env SUSFS_INLINE_HOOK_STATUS invalid-stat-hook
    {
      echo '[ERROR] SUSFS stat hook uses fname without an in-scope declaration'
      echo "declaration line: ${fname_decl_line:-missing}; first use line: ${fname_use_line:-missing}"
    } | tee -a "$diagnostics/susfs-inline-hooks.log" >&2
    exit 1
  fi
fi
set_github_env SUSFS_INLINE_HOOK_STATUS applied
echo '[+] SUSFS and inline hooks applied'
