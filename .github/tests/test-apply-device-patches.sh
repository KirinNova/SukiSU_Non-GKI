#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
source_repo="$work/source"
kernel_root="$work/kernel"
artifact_dir="$work/artifacts"
runner_temp="$work/runner"
mkdir -p "$source_repo/Patches" "$kernel_root" "$artifact_dir" "$runner_temp"

printf 'before\n' > "$work/pre.old"
printf 'after-pre\n' > "$work/pre.new"
diff -u --label a/base.txt --label b/base.txt "$work/pre.old" "$work/pre.new" \
  > "$source_repo/Patches/pre.patch" || true

printf 'vendor\n' > "$work/repair.old"
printf 'vendor\n#ifdef CONFIG_KSU_SUSFS\nsusfs_device_fix();\n#endif\n' > "$work/repair.new"
diff -u --label a/vendor.txt --label b/vendor.txt "$work/repair.old" "$work/repair.new" \
  > "$source_repo/Patches/repair.patch" || true

git -C "$source_repo" init -q -b main
git -C "$source_repo" add Patches
git -C "$source_repo" -c user.name=test -c user.email=test@example.invalid commit -qm fixtures
printf 'before\n' > "$kernel_root/base.txt"
printf 'vendor\n' > "$kernel_root/vendor.txt"

GITHUB_ENV="$work/github.env" \
KERNEL_ROOT="$kernel_root" \
ARTIFACT_DIR="$artifact_dir" \
RUNNER_TEMP="$runner_temp" \
APPLY_DEVICE_PATCHES=true \
DEVICE_PATCH_REPO="file://$source_repo" \
DEVICE_PATCH_BRANCH=main \
DEVICE_PATCH_NAMES='pre.patch repair.patch' \
  bash "$repo_root/.github/scripts/apply-device-patches.sh"

grep -qx 'after-pre' "$kernel_root/base.txt"
grep -qx 'vendor' "$kernel_root/vendor.txt"
grep -qx 'pre.patch' "$artifact_dir/device-patches/pre-applied.txt"
grep -qx 'repair.patch' "$artifact_dir/device-patches/susfs-repair.txt"
grep -qx 'DEVICE_PATCH_COUNT=2' "$work/github.env"
grep -qx 'DEVICE_PATCH_PRE_COUNT=1' "$work/github.env"
grep -qx 'DEVICE_PATCH_REPAIR_COUNT=1' "$work/github.env"
grep -qx 'DEVICE_PATCH_STATUS=applied-pre-and-staged-susfs-repair' "$work/github.env"

echo '[+] apply-device-patches tests passed'
