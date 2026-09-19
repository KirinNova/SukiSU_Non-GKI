#!/usr/bin/env bash
set -euo pipefail

artifact=${ARTIFACT_DIR:?ARTIFACT_DIR is required}
mkdir -p "$artifact"
report="$artifact/build-report.md"
end=$(date +%s)
start=${BUILD_START_EPOCH:-$end}

{
  echo '# SukiSU Non-GKI build report'
  echo
  echo "- 编译内核的名字: ${KERNEL_NAME:-by_XiZi}"
  echo "- 内核版本: ${KERNEL_RELEASE:-unknown}"
  echo "- 源码真实版本: ${KERNEL_VERSION_CODE:-unknown}"
  echo "- 纯净内核源码仓库名字: ${KERNEL_SOURCE_NAME:-unknown}"
  echo "- 编译总时间: $((end-start)) 秒"
  echo "- 内核工具版本检测脚本: ${MIN_TOOL_VERSION_STATUS:-not-run}"
  echo "- 上游发行后缀处理: ${VENDOR_LOCALVERSION_STATUS:-not-run}"
  echo "- TAS2557 speaker-ID 厂商依赖: ${VENDOR_SPK_ID_STATUS:-not-needed}"
  echo "- 编译器 Werror 降级: ${IGNORE_WERROR_REQUESTED:-false}"
  echo "- 集成选择: SukiSU Ultra=是; SUSFS=${INTEGRATE_SUSFS:-false}; DroidSpaces=${INTEGRATE_DROIDSPACES:-false}; 机型专属补丁=${APPLY_DEVICE_PATCHES:-false}; 内核版本伪装=${SPOOF_KERNEL_VERSION:-false}; LTO关闭=${DISABLE_LTO_REQUESTED:-false}; Werror降级=${IGNORE_WERROR_REQUESTED:-false}; A/B=${AB_PARTITION:-false}; AK3=${PACKAGE_AK3:-false}"

  if [[ "${SPOOF_KERNEL_VERSION:-false}" == true ]]; then
    echo "- 内核版本伪装目标: ${KERNEL_SPOOFED_VERSION:-${SPOOFED_KERNEL_VERSION:-unknown}}"
    echo "- 内核版本伪装状态: ${KERNEL_VERSION_SPOOF_STATUS:-not-run}"
  fi
  if [[ "${INTEGRATE_SUSFS:-false}" == true ]]; then
    echo "- SUSFS 补丁状态: ${SUSFS_PATCH_STATUS:-not-run}"
    echo "- SUSFS 与机型补丁重叠验证: ${SUSFS_DEVICE_OVERLAP_STATUS:-not-run}"
    echo "- SUSFS 已修复拒绝文件: ${SUSFS_REPAIRED_REJECT_COUNT:-0}"
    echo "- SUSFS inline hook 状态: ${SUSFS_INLINE_HOOK_STATUS:-not-run}"
    echo "- 补丁拒绝文件: ${PATCH_REJECT_COUNT:-0}"
    echo "- 补丁原始备份文件: ${PATCH_ORIG_COUNT:-0}"
  fi
  if [[ "${APPLY_DEVICE_PATCHES:-false}" == true ]]; then
    echo "- 机型补丁仓库: ${DEVICE_PATCH_REPO_NAME:-unknown}@${DEVICE_PATCH_BRANCH:-unknown}"
    echo "- 机型补丁数量: ${DEVICE_PATCH_COUNT:-unknown}"
    echo "- SUSFS 前置机型补丁数量: ${DEVICE_PATCH_PRE_COUNT:-0}"
    echo "- SUSFS 修复机型补丁数量: ${DEVICE_PATCH_REPAIR_COUNT:-0}"
    echo "- 已执行 SUSFS 修复补丁数量: ${DEVICE_PATCH_REPAIR_APPLIED_COUNT:-0}"
    echo "- 机型补丁状态: ${DEVICE_PATCH_STATUS:-not-run}"
  fi
  if [[ "${INTEGRATE_DROIDSPACES:-false}" == true ]]; then
    echo "- DroidSpaces 配置片段: ${DROIDSPACES_CONFIG:-applied}"
    echo "- DroidSpaces xt_qtaguid 修复: ${DROIDSPACES_XT_QTAGUID_PATCH:-not-run}"
    echo "- DroidSpaces cgroup 修复: ${DROIDSPACES_CGROUP_PATCH:-not-run}"
  fi

  echo
  echo '## 产物校验'
  echo '| 文件 | 大小 | SHA-256 |'
  echo '| --- | ---: | --- |'
  while IFS= read -r -d '' file; do
    printf '| `%s` | %s | `%s` |\n' \
      "${file#$artifact/}" \
      "$(du -h "$file" | cut -f1)" \
      "$(sha256sum "$file" | cut -d' ' -f1)"
  done < <(find "$artifact" -type f ! -path "$report" -print0 | sort -z)
} > "$report"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$report" >> "$GITHUB_STEP_SUMMARY"
else
  cat "$report"
fi
