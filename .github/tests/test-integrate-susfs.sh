#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

make_fixture() {
  local name=$1
  local root="$work/$name"
  mkdir -p "$root/kernel" "$root/patches/Patch" "$root/artifacts"
  printf 'alpha\nbeta\n' > "$root/kernel/one.txt"
  printf 'red\nblue\n' > "$root/kernel/two.txt"
  cp "$root/kernel/one.txt" "$root/one.old"
  cp "$root/kernel/two.txt" "$root/two.old"
  printf 'alpha\nbeta-susfs\n' > "$root/kernel/one.txt"
  printf 'red\nblue-susfs\n' > "$root/kernel/two.txt"
  {
    diff -u --label a/one.txt --label b/one.txt "$root/one.old" "$root/kernel/one.txt" || true
    diff -u --label a/two.txt --label b/two.txt "$root/two.old" "$root/kernel/two.txt" || true
  } > "$root/patches/Patch/susfs_patch_to_4.19.patch"
  cp "$root/one.old" "$root/kernel/one.txt"
  cp "$root/two.old" "$root/kernel/two.txt"
  printf '#!/usr/bin/env bash\nset -euo pipefail\nprintf hook-ran > "$KERNEL_ROOT/hook-ran"\n' > "$root/patches/susfs_inline_hook_patches.sh"
  chmod +x "$root/patches/susfs_inline_hook_patches.sh"
  printf '%s' "$root"
}

run_integration() {
  local root=$1 device_patches=$2
  GITHUB_ENV="$root/github.env" \
  KERNEL_ROOT="$root/kernel" \
  PATCH_ROOT="$root/patches" \
  ARTIFACT_DIR="$root/artifacts" \
  SOURCE_KERNEL_VERSION=4.19 \
  INTEGRATE_SUSFS=true \
  APPLY_DEVICE_PATCHES="$device_patches" \
    bash "$repo_root/.github/scripts/integrate-susfs.sh"
}

normal=$(make_fixture normal)
run_integration "$normal" false
grep -qx 'beta-susfs' "$normal/kernel/one.txt"
grep -qx 'blue-susfs' "$normal/kernel/two.txt"
grep -qx 'SUSFS_PATCH_STATUS=applied' "$normal/github.env"
[[ -f "$normal/kernel/hook-ran" ]]

overlap=$(make_fixture overlap)
sed -i 's/^beta$/beta-susfs/' "$overlap/kernel/one.txt"
run_integration "$overlap" true
grep -qx 'beta-susfs' "$overlap/kernel/one.txt"
grep -qx 'blue-susfs' "$overlap/kernel/two.txt"
grep -qx 'SUSFS_PATCH_STATUS=applied-with-verified-device-overlap' "$overlap/github.env"
grep -qx 'SUSFS_DEVICE_OVERLAP_STATUS=verified' "$overlap/github.env"
[[ -f "$overlap/kernel/hook-ran" ]]
! find "$overlap/kernel" -type f \( -name '*.rej' -o -name '*.orig' \) | grep -q .

repair=$(make_fixture repair)
printf 'alpha\nvendor-beta\n' > "$repair/kernel/one.txt"
mkdir -p "$repair/artifacts/device-patches"
printf 'alpha\nvendor-beta\n' > "$repair/vendor.old"
printf 'alpha\nvendor-beta-susfs\n' > "$repair/vendor.new"
diff -u --label a/one.txt --label b/one.txt "$repair/vendor.old" "$repair/vendor.new" \
  > "$repair/artifacts/device-patches/vendor-repair.patch" || true
printf 'vendor-repair.patch\n' > "$repair/artifacts/device-patches/susfs-repair.txt"
run_integration "$repair" true
grep -qx 'vendor-beta-susfs' "$repair/kernel/one.txt"
grep -qx 'blue-susfs' "$repair/kernel/two.txt"
grep -qx 'SUSFS_PATCH_STATUS=applied-with-device-repair' "$repair/github.env"
grep -qx 'SUSFS_DEVICE_OVERLAP_STATUS=repaired' "$repair/github.env"
grep -qx 'SUSFS_REPAIRED_REJECT_COUNT=1' "$repair/github.env"
grep -qx 'DEVICE_PATCH_REPAIR_APPLIED_COUNT=1' "$repair/github.env"
[[ -f "$repair/kernel/hook-ran" ]]
[[ -f "$repair/artifacts/susfs-diagnostics/rejected-before-device-repair/one.txt.rej" ]]
! find "$repair/kernel" -type f \( -name '*.rej' -o -name '*.orig' \) | grep -q .

unresolved=$(make_fixture unresolved)
printf 'unrelated-vendor-line\n' > "$unresolved/kernel/one.txt"
if run_integration "$unresolved" true; then
  echo '[ERROR] unresolved SUSFS fixture unexpectedly succeeded' >&2
  exit 1
fi
grep -qx 'SUSFS_PATCH_STATUS=failed' "$unresolved/github.env"
grep -qx 'SUSFS_DEVICE_OVERLAP_STATUS=unresolved' "$unresolved/github.env"
find "$unresolved/kernel" -type f -name '*.rej' | grep -q .
[[ ! -f "$unresolved/kernel/hook-ran" ]]

echo '[+] integrate-susfs tests passed'
