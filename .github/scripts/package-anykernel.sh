#!/usr/bin/env bash
set -euo pipefail
[[ "${PACKAGE_AK3:-false}" == true ]] || { echo '[+] AnyKernel3 packaging disabled'; exit 0; }
cd "${KERNEL_ROOT:?}"; out=${OUT_DIR:-out}; artifact=${ARTIFACT_DIR:?}; git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git "$artifact/AnyKernel3"
ak="$artifact/AnyKernel3"; slot=0; [[ "${AB_PARTITION:-false}" == true ]] && slot=1; cat > "$ak/anykernel.sh" <<EOF
do.devicecheck=1
device.name1=${CODENAME:?}
is_slot_device=$slot
block=auto
EOF
cp "$out/arch/${ARCH:-arm64}/boot/${BUILD_TARGET:-Image.gz-dtb}" "$ak/"
printf '%s SukiSU+Susfs集成内核 by%s\n内核版本:%s\n' "$CODENAME" "${AUTHOR:-XiZi}" "${KERNEL_NAME:-by_XiZi}" > "$ak/README_FLASH.txt"
(cd "$ak" && zip -qr "$artifact/${CODENAME}-SukiSU-Non-GKI-AK3.zip" .)
