#!/usr/bin/env bash
set -euo pipefail

artifact=${ARTIFACT_DIR:?}
destination="$artifact/patch-diagnostics"
mkdir -p "$destination"

if [[ -d "${KERNEL_ROOT:-}" ]]; then
  cd "$KERNEL_ROOT"
  find . -type f \( -name '*.rej' -o -name '*.orig' \) -print0 |
    while IFS= read -r -d '' file; do
      printf '%s\n' "${file#./}"
      cp --parents "$file" "$destination/"
    done | tee "$destination/reject-files.txt"
fi

if [[ -d "$artifact/device-patches" ]]; then
  mkdir -p "$destination/device-patches"
  cp -a "$artifact/device-patches/." "$destination/device-patches/"
fi

reject_count=$(find "$destination" -type f -name '*.rej' | wc -l)
orig_count=$(find "$destination" -type f -name '*.orig' | wc -l)
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'PATCH_REJECT_COUNT=%s\n' "$reject_count" >> "$GITHUB_ENV"
  printf 'PATCH_ORIG_COUNT=%s\n' "$orig_count" >> "$GITHUB_ENV"
fi
echo "[+] Patch diagnostics collected: rejects=$reject_count, originals=$orig_count"
