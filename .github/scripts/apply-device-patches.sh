#!/usr/bin/env bash
set -euo pipefail

[[ "${APPLY_DEVICE_PATCHES:-false}" == true ]] || { echo '[+] Device-specific patches disabled'; exit 0; }
cd "${KERNEL_ROOT:?}"
repo=${DEVICE_PATCH_REPO:?}
branch=${DEVICE_PATCH_BRANCH:?}
patch_names=${DEVICE_PATCH_NAMES:?}
patch_root=${ARTIFACT_DIR:?}/device-patches
checkout=${RUNNER_TEMP:-/tmp}/device-patch-source

rm -rf "$checkout"
git clone --depth=1 --branch "$branch" "$repo" "$checkout"
patch_dir="$checkout/Patches"
[[ -d "$patch_dir" ]] || { echo "[ERROR] device patch repository has no Patches directory: $patch_dir" >&2; exit 1; }
mkdir -p "$patch_root"

applied=0
for patch_name in $patch_names; do
  [[ "$patch_name" != -* && "$patch_name" != */* && "$patch_name" != *..* ]] || {
    echo "[ERROR] invalid device patch filename: $patch_name" >&2
    exit 1
  }
  patch_file="$patch_dir/$patch_name"
  [[ -f "$patch_file" ]] || { echo "[ERROR] device patch not found: Patches/$patch_name" >&2; exit 1; }
  echo "[+] Applying device patch: Patches/$patch_name"
  patch --forward --batch -p1 < "$patch_file"
  cp "$patch_file" "$patch_root/"
  applied=$((applied + 1))
done

printf '%s\n' "$patch_names" > "$patch_root/applied.txt"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'DEVICE_PATCH_STATUS=applied\n' >> "$GITHUB_ENV"
  printf 'DEVICE_PATCH_COUNT=%s\n' "$applied" >> "$GITHUB_ENV"
  printf 'DEVICE_PATCH_REPO_NAME=%s\n' "$(basename "$repo" .git)" >> "$GITHUB_ENV"
  printf 'DEVICE_PATCH_BRANCH=%s\n' "$branch" >> "$GITHUB_ENV"
fi
echo "[+] Applied $applied device-specific patch(es) from $(basename "$repo" .git)@$branch"
