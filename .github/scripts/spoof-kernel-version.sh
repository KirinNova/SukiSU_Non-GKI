#!/usr/bin/env bash
set -euo pipefail

[[ "${SPOOF_KERNEL_VERSION:-false}" == true ]] || {
  echo '[+] Kernel version spoofing disabled'
  exit 0
}

cd "${KERNEL_ROOT:?KERNEL_ROOT is required}"
requested=${SPOOFED_KERNEL_VERSION:?SPOOFED_KERNEL_VERSION is required when spoofing is enabled}

if [[ ! "$requested" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
  echo '[ERROR] spoofed kernel version must use numeric major.minor.sublevel format, for example 4.9.337' >&2
  exit 1
fi

IFS=. read -r major minor sublevel <<< "$requested"

read_make_version() {
  local key=$1
  sed -n "s/^${key}[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p" Makefile | head -n1
}

original_major=$(read_make_version VERSION)
original_minor=$(read_make_version PATCHLEVEL)
original_sublevel=$(read_make_version SUBLEVEL)
[[ -n "$original_major" && -n "$original_minor" && -n "$original_sublevel" ]] || {
  echo '[ERROR] unable to read VERSION/PATCHLEVEL/SUBLEVEL from the kernel Makefile' >&2
  exit 1
}

# Do not rewrite VERSION/PATCHLEVEL/SUBLEVEL.  Those values define
# LINUX_VERSION_CODE and select the kernel's compile-time APIs.  Rewriting a
# 4.19 vendor tree to 5.15, for example, makes SUSFS select APIs that the tree
# does not actually provide.  The final KERNELRELEASE override is applied by
# configure-kernel.sh after the explicit local version has been assembled.
if [[ "$major.$minor" != "$original_major.$original_minor" ]]; then
  echo "[INFO] cross-family release spoof requested ($original_major.$original_minor -> $major.$minor); compile-time kernel version remains unchanged" >&2
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'KERNEL_VERSION_SPOOF_STATUS=deferred-release-only\nKERNEL_SPOOFED_VERSION=%s\nKERNELRELEASE_OVERRIDE_BASE=%s\n' "$requested" "$requested" >> "$GITHUB_ENV"
fi
printf '[+] Kernel release spoof queued: %s (source compile-time version remains %s)\n' "$requested" "$original_major.$original_minor.$original_sublevel"
