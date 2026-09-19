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

if [[ "$major.$minor" != "$original_major.$original_minor" ]]; then
  echo "[WARNING] spoofing across kernel families ($original_major.$original_minor -> $major.$minor) can select incompatible compile-time APIs" >&2
fi

sed -i -E   -e "0,/^VERSION[[:space:]]*=/{s//VERSION = $major/}"   -e "0,/^PATCHLEVEL[[:space:]]*=/{s//PATCHLEVEL = $minor/}"   -e "0,/^SUBLEVEL[[:space:]]*=/{s//SUBLEVEL = $sublevel/}"   Makefile

actual_major=$(read_make_version VERSION)
actual_minor=$(read_make_version PATCHLEVEL)
actual_sublevel=$(read_make_version SUBLEVEL)
actual="$actual_major.$actual_minor.$actual_sublevel"
[[ "$actual" == "$requested" ]] || {
  echo "[ERROR] Makefile version verification failed: expected $requested, got $actual" >&2
  exit 1
}

if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'KERNEL_VERSION_SPOOF_STATUS=applied\nKERNEL_SPOOFED_VERSION=%s\n' "$actual" >> "$GITHUB_ENV"
fi
printf '[+] Kernel Makefile version spoofed: %s -> %s\n' "$original_major.$original_minor.$original_sublevel" "$actual"
