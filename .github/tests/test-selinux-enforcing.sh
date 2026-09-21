#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
fake_bin="$work/bin"
mkdir -p "$fake_bin"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'out=out' \
  'for arg in "$@"; do case "$arg" in O=*) out=${arg#O=} ;; esac; done' \
  'if [[ " $* " == *" kernelrelease "* ]]; then echo 4.19.325-test; exit 0; fi' \
  'if [[ " $* " == *" test_defconfig "* ]]; then' \
  '  mkdir -p "$out"' \
  '  printf "%s\n" "CONFIG_SECURITY_SELINUX=y" "CONFIG_SECURITY_SELINUX_DEVELOP=y" > "$out/.config"' \
  'fi' \
  > "$fake_bin/make"
chmod +x "$fake_bin/make"

run_configure() {
  local kernel_root=$1 github_env=$2 force=$3
  PATH="$fake_bin:$PATH" \
  GITHUB_ENV="$github_env" \
  KERNEL_ROOT="$kernel_root" \
  OUT_DIR=out \
  DEFCONFIG_RESOLVED=test_defconfig \
  KERNEL_NAME=test \
  KERNEL_VERSION=v1 \
  BUILD_TIME='2026-09-21 00:00:00' \
  FORCE_SELINUX_ENFORCING="$force" \
    bash "$repo_root/.github/scripts/configure-kernel.sh"
}

forced_root="$work/forced"
mkdir -p "$forced_root/security/selinux"
cat > "$forced_root/security/selinux/selinuxfs.c" <<'EOF'
static ssize_t sel_write_enforce(struct file *file)
{
	new_value = 0; /* forced permissive vendor hack */
}
EOF
: > "$work/forced.env"
run_configure "$forced_root" "$work/forced.env" true
grep -qx 'CONFIG_SECURITY_SELINUX=y' "$forced_root/out/.config"
grep -qx '# CONFIG_SECURITY_SELINUX_DEVELOP is not set' "$forced_root/out/.config"
! grep -qx 'CONFIG_SECURITY_SELINUX_DEVELOP=y' "$forced_root/out/.config"
grep -q '^\s*new_value = !!new_value;$' "$forced_root/security/selinux/selinuxfs.c"
grep -qx 'SELINUX_ENFORCING_STATUS=forced' "$work/forced.env"
grep -qx 'SELINUX_SOURCE_REPAIR_STATUS=repaired-forced-permissive' "$work/forced.env"

unchanged_root="$work/unchanged"
mkdir -p "$unchanged_root/security/selinux"
cat > "$unchanged_root/security/selinux/selinuxfs.c" <<'EOF'
static ssize_t sel_write_enforce(struct file *file)
{
	new_value = 0; /* forced permissive vendor hack */
}
EOF
: > "$work/unchanged.env"
run_configure "$unchanged_root" "$work/unchanged.env" false
grep -qx 'CONFIG_SECURITY_SELINUX_DEVELOP=y' "$unchanged_root/out/.config"
grep -q '^\s*new_value = 0;' "$unchanged_root/security/selinux/selinuxfs.c"
grep -qx 'SELINUX_ENFORCING_STATUS=unchanged' "$work/unchanged.env"
grep -qx 'SELINUX_SOURCE_REPAIR_STATUS=not-requested' "$work/unchanged.env"

artifact_dir="$work/artifacts"
ARTIFACT_DIR="$artifact_dir" \
FORCE_SELINUX_ENFORCING=true \
SELINUX_ENFORCING_STATUS=forced \
SELINUX_SOURCE_REPAIR_STATUS=repaired-forced-permissive \
  bash "$repo_root/.github/scripts/generate-build-report.sh" >/dev/null
grep -Fqx -- '- SELinux 固定 Enforcing: 请求=true; 状态=forced' "$artifact_dir/build-report.md"
grep -Fqx -- '- SELinux 强制宽容源码修复: repaired-forced-permissive' "$artifact_dir/build-report.md"
grep -Fq 'SELinux固定Enforcing=true' "$artifact_dir/build-report.md"

echo '[+] optional SELinux enforcing tests passed'
