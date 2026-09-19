#!/usr/bin/env bash
set -euo pipefail

[[ "${APPLY_DEVICE_PATCHES:-false}" == true ]] || { echo '[+] Device-specific patches disabled'; exit 0; }
cd "${KERNEL_ROOT:?}"
repo=${DEVICE_PATCH_REPO:?}
branch=${DEVICE_PATCH_BRANCH:?}
patch_names=${DEVICE_PATCH_NAMES:?}
patch_root=${ARTIFACT_DIR:?}/device-patches
checkout=${RUNNER_TEMP:-/tmp}/device-patch-source

case "$checkout" in
  "${RUNNER_TEMP:-/tmp}/device-patch-source"|/tmp/device-patch-source) rm -rf -- "$checkout" ;;
  *) echo "[ERROR] refusing unsafe temporary checkout path: $checkout" >&2; exit 1 ;;
esac
git clone --depth=1 --branch "$branch" "$repo" "$checkout"
patch_dir="$checkout/Patches"
[[ -d "$patch_dir" ]] || { echo "[ERROR] device patch repository has no Patches directory: $patch_dir" >&2; exit 1; }
mkdir -p "$patch_root"
pre_manifest="$patch_root/pre-applied.txt"
repair_manifest="$patch_root/susfs-repair.txt"
: > "$patch_root/applied.txt"
: > "$pre_manifest"
: > "$repair_manifest"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    printf 'DEVICE_PATCH_STATUS=applying\n'
    printf 'DEVICE_PATCH_COUNT=0\n'
    printf 'DEVICE_PATCH_PRE_COUNT=0\n'
    printf 'DEVICE_PATCH_REPAIR_COUNT=0\n'
    printf 'DEVICE_PATCH_REPO_NAME=%s\n' "$(basename "$repo" .git)"
    printf 'DEVICE_PATCH_BRANCH=%s\n' "$branch"
  } >> "$GITHUB_ENV"
fi

applied=0
pre_applied=0
repair_staged=0
for patch_name in $patch_names; do
  [[ "$patch_name" != -* && "$patch_name" != */* && "$patch_name" != *..* ]] || {
    echo "[ERROR] invalid device patch filename: $patch_name" >&2
    exit 1
  }
  patch_file="$patch_dir/$patch_name"
  [[ -f "$patch_file" ]] || { echo "[ERROR] device patch not found: Patches/$patch_name" >&2; exit 1; }
  cp "$patch_file" "$patch_root/"
  printf '%s\n' "$patch_name" >> "$patch_root/applied.txt"
  if grep -Eq '^\+[^+].*(CONFIG_KSU_SUSFS|susfs_)' "$patch_file"; then
    echo "[+] Staging SUSFS repair patch: Patches/$patch_name"
    printf '%s\n' "$patch_name" >> "$repair_manifest"
    repair_staged=$((repair_staged + 1))
  else
    echo "[+] Applying pre-SUSFS device patch: Patches/$patch_name"
    patch --forward --batch -p1 < "$patch_file"
    printf '%s\n' "$patch_name" >> "$pre_manifest"
    pre_applied=$((pre_applied + 1))
  fi
  applied=$((applied + 1))
done

if (( pre_applied > 0 && repair_staged > 0 )); then
  device_status=applied-pre-and-staged-susfs-repair
elif (( repair_staged > 0 )); then
  device_status=staged-susfs-repair
else
  device_status=applied-pre-susfs
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'DEVICE_PATCH_STATUS=%s\n' "$device_status" >> "$GITHUB_ENV"
  printf 'DEVICE_PATCH_COUNT=%s\n' "$applied" >> "$GITHUB_ENV"
  printf 'DEVICE_PATCH_PRE_COUNT=%s\n' "$pre_applied" >> "$GITHUB_ENV"
  printf 'DEVICE_PATCH_REPAIR_COUNT=%s\n' "$repair_staged" >> "$GITHUB_ENV"
  printf 'DEVICE_PATCH_REPO_NAME=%s\n' "$(basename "$repo" .git)" >> "$GITHUB_ENV"
  printf 'DEVICE_PATCH_BRANCH=%s\n' "$branch" >> "$GITHUB_ENV"
fi
echo "[+] Device patches from $(basename "$repo" .git)@$branch: pre-SUSFS=$pre_applied, SUSFS-repair=$repair_staged"
