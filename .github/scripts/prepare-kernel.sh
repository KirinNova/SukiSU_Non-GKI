#!/usr/bin/env bash
set -euo pipefail
die() { echo "[ERROR] $*" >&2; exit 1; }
cd "${KERNEL_ROOT:?KERNEL_ROOT is required}"
major=$(sed -n 's/^VERSION[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' Makefile | head -n1)
minor=$(sed -n 's/^PATCHLEVEL[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' Makefile | head -n1)
sublevel=$(sed -n 's/^SUBLEVEL[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' Makefile | head -n1)
[[ -n "$major" && -n "$minor" && -n "$sublevel" ]] || die 'unable to read VERSION/PATCHLEVEL/SUBLEVEL from Makefile'
echo "SOURCE_KERNEL_VERSION=$major.$minor" >> "$GITHUB_ENV"
find_config() { local requested=$1 suffix=$2 path=$1; [[ -z "$requested" ]] && return 0; [[ -f "$path" ]] || path="arch/$ARCH/configs/$path"; [[ -f "$path" ]] || die "config file not found: $requested"; [[ "$path" == *"$suffix" ]] || die "$requested must end with $suffix"; printf '%s' "${path#arch/$ARCH/configs/}"; }
defconfig=$(find_config "${DEFCONFIG:-}" '_defconfig')
device_config=$(find_config "${DEVICE_CONFIG:-}" '.config')
if [[ -z "$defconfig" ]]; then
  mapfile -t candidates < <(find "arch/$ARCH/configs" -type f \( -name "*${CODENAME}*_defconfig" -o -name "${CODENAME}_defconfig" \) | sort -u)
  [[ ${#candidates[@]} -eq 1 ]] || { echo '[ERROR] defconfig is ambiguous; set DEFCONFIG explicitly. Candidates:' >&2; printf '  %s\n' "${candidates[@]}" >&2; exit 2; }
  defconfig=${candidates[0]#arch/$ARCH/configs/}
fi
echo "DEFCONFIG_RESOLVED=$defconfig" >> "$GITHUB_ENV"
echo "DEVICE_CONFIG_RESOLVED=$device_config" >> "$GITHUB_ENV"
echo "KERNEL_SOURCE_NAME=$(basename "$(git config --get remote.origin.url || pwd)" .git)" >> "$GITHUB_ENV"
echo "KERNEL_VERSION_CODE=$major.$minor.$sublevel" >> "$GITHUB_ENV"
echo "[+] Kernel version: $major.$minor.$sublevel; defconfig: $defconfig"
