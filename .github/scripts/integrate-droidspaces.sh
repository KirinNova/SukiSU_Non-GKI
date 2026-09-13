#!/usr/bin/env bash
set -euo pipefail
[[ "${INTEGRATE_DROIDSPACES:-false}" == true ]] || { echo '[+] DroidSpaces integration disabled'; exit 0; }
cd "${KERNEL_ROOT:?}"; patch_root=${PATCH_ROOT:?}; artifact=${ARTIFACT_DIR:?}
patch_dir="$patch_root/Droidspaces"
config_fragment="$patch_dir/droidspaces.config"
xt_patch="$patch_dir/fix_kernel_panic_in_xt_qtaguid.cocci"
cgroup_patch="$patch_dir/fix_restore_cgroup_file_prefix_handling.cocci"
[[ -f "$config_fragment" ]] || { echo "[ERROR] DroidSpaces config fragment is missing: $config_fragment" >&2; exit 1; }
[[ -f "$xt_patch" ]] || { echo "[ERROR] DroidSpaces xt_qtaguid patch is missing: $xt_patch" >&2; exit 1; }
[[ -f "$cgroup_patch" ]] || { echo "[ERROR] DroidSpaces cgroup patch is missing: $cgroup_patch" >&2; exit 1; }
config_dest="arch/${ARCH:-arm64}/configs/droidspaces.config"
mkdir -p "$(dirname "$config_dest")"
cp "$config_fragment" "$config_dest"
if [[ -n "${GITHUB_ENV:-}" ]]; then printf 'DROIDSPACES_CONFIG=applied\n' >> "$GITHUB_ENV"; fi

record_status() {
  local name=$1 status=$2
  printf '[+] DroidSpaces %s: %s\n' "$name" "$status"
  if [[ -n "${GITHUB_ENV:-}" ]]; then printf 'DROIDSPACES_%s=%s\n' "$name" "$status" >> "$GITHUB_ENV"; fi
}
apply_cocci() {
  local name=$1 patch_file=$2 target=$3 before after
  if [[ ! -f "$target" ]]; then record_status "$name" skipped; return 0; fi
  before=$(sha256sum "$target" | cut -d' ' -f1)
  spatch --sp-file "$patch_file" --in-place "$target"
  after=$(sha256sum "$target" | cut -d' ' -f1)
  [[ "$before" == "$after" ]] && record_status "$name" unchanged || record_status "$name" applied
}

command -v spatch >/dev/null 2>&1 || { echo '[ERROR] spatch is required for DroidSpaces Coccinelle fixes' >&2; exit 1; }
apply_cocci XT_QTAGUID_PATCH "$xt_patch" net/netfilter/xt_qtaguid.c
cgroup_file=''; [[ -f kernel/cgroup/cgroup.c ]] && cgroup_file=kernel/cgroup/cgroup.c; [[ -z "$cgroup_file" && -f kernel/cgroup.c ]] && cgroup_file=kernel/cgroup.c
if [[ -z "$cgroup_file" ]]; then
  record_status CGROUP_PATCH skipped
elif grep -q kernfs_create_link "$cgroup_file"; then
  record_status CGROUP_PATCH unchanged
else
  apply_cocci CGROUP_PATCH "$cgroup_patch" "$cgroup_file"
fi
echo '[WARNING] DroidSpaces and SUSFS are not officially supported together; disable HIDE SUS MOUNTS FOR ALL PROCESSES when both are enabled.'
release=$(curl -fsSL -H 'User-Agent: SukiSU-Non-GKI' https://api.github.com/repos/ravindu644/Droidspaces-OSS/releases/latest)
tag=$(printf '%s' "$release" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
apk=$(printf '%s' "$release" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.apk\)".*/\1/p' | head -n1)
tarball=$(printf '%s' "$release" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.tar\.gz\)".*/\1/p' | head -n1)
[[ -n "$apk" && -n "$tarball" ]] || { echo '[ERROR] latest DroidSpaces release is missing APK/runtime assets' >&2; exit 1; }
mkdir -p "$artifact/droidspaces"; curl -fL "$apk" -o "$artifact/droidspaces/$(basename "$apk")"; curl -fL "$tarball" -o "$artifact/droidspaces/$(basename "$tarball")"
echo "DROIDSPACES_RELEASE=$tag" >> "$GITHUB_ENV"
