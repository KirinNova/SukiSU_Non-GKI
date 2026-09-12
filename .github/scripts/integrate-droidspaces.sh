#!/usr/bin/env bash
set -euo pipefail
[[ "${INTEGRATE_DROIDSPACES:-false}" == true ]] || { echo '[+] DroidSpaces integration disabled'; exit 0; }
cd "${KERNEL_ROOT:?}"; patch_root=${PATCH_ROOT:?}; artifact=${ARTIFACT_DIR:?}
cp "$patch_root/Droidspaces/droidspaces.config" "arch/${ARCH:-arm64}/configs/droidspaces.config"
if command -v spatch >/dev/null 2>&1; then
  [[ ! -f net/netfilter/xt_qtaguid.c ]] || spatch --sp-file "$patch_root/Droidspaces/fix_kernel_panic_in_xt_qtaguid.cocci" --in-place net/netfilter/xt_qtaguid.c
  cgroup_file=''; [[ -f kernel/cgroup/cgroup.c ]] && cgroup_file=kernel/cgroup/cgroup.c; [[ -z "$cgroup_file" && -f kernel/cgroup.c ]] && cgroup_file=kernel/cgroup.c
  [[ -z "$cgroup_file" || -n "$(grep -l kernfs_create_link "$cgroup_file" || true)" ]] || spatch --sp-file "$patch_root/Droidspaces/fix_restore_cgroup_file_prefix_handling.cocci" --in-place "$cgroup_file"
else echo '[WARNING] spatch unavailable; Coccinelle fixes were not applied' >&2; fi
echo '[WARNING] DroidSpaces and SUSFS are not officially supported together; disable HIDE SUS MOUNTS FOR ALL PROCESSES when both are enabled.'
release=$(curl -fsSL -H 'User-Agent: SukiSU-Non-GKI' https://api.github.com/repos/ravindu644/Droidspaces-OSS/releases/latest)
tag=$(printf '%s' "$release" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
apk=$(printf '%s' "$release" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.apk\)".*/\1/p' | head -n1)
tarball=$(printf '%s' "$release" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\.tar\.gz\)".*/\1/p' | head -n1)
[[ -n "$apk" && -n "$tarball" ]] || { echo '[ERROR] latest DroidSpaces release is missing APK/runtime assets' >&2; exit 1; }
mkdir -p "$artifact/droidspaces"; curl -fL "$apk" -o "$artifact/droidspaces/$(basename "$apk")"; curl -fL "$tarball" -o "$artifact/droidspaces/$(basename "$tarball")"
echo "DROIDSPACES_RELEASE=$tag" >> "$GITHUB_ENV"
