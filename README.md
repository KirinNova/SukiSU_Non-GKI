# SukiSU Non-GKI

这是基于 SukiSU Ultra `builtin` 分支的增量兼容移植，目标是在旧版 Non-GKI 内核中保留 SukiSU Ultra 的工作流，并补齐 SELinux hide 所需的接口和运行时 hook。

> 这是非官方移植。5.10 及以上内核继续使用 SukiSU Ultra 原有实现；新增兼容代码只在 `< 5.10` 时编译。

## 基线

- SukiSU Ultra `builtin`: `e2912817f4e1b194e582a06e0b5eacf6a3fb7083`
- ReSukiSU `main`: `fa1da13f890a19335d3f8f5c62bb5bde466fc384`
- 验证内核: Evolution-X-Devices `kernel_xiaomi_sdm845` `bka`
- 验证内核提交: `b0fb2a6d2d20c1f3219183e8590fff50a3a39fd6` (`4.9.337`)

## 移植范围

- `< 5.10` 单独编译 `kernel/non_gki/`，包含 SELinux hide、policydb/sidtab 备份、符号解析和 arm64 文本修补。
- 根据内核源码能力探测 SELinux/LSM 数据结构，不仅依赖版本号判断厂商回移。
- 修复 4.9 缺失的 `fallthrough`、`current_sid()`、`strncpy_from_user_nofault()` 和 kernel umount feature setter。
- 保持 SukiSU Ultra 5.10+ SELinux hide 实现和现有 SUSFS inline hook 路径不变。
- 如果 SUSFS 已提供新版 SELinux hide hook，则直接复用；否则使用 ReSukiSU 风格的运行时 function/LSM slot patch。

## 集成到内核源码树

在内核源码根目录运行：

```sh
curl -LSs https://raw.githubusercontent.com/xiziya/SukiSU_Non-GKI/builtin/kernel/setup.sh | sh
```

脚本会自动识别 `drivers/` 或 `common/drivers/`，克隆 `builtin` 分支，创建 `drivers/kernelsu` 软链接，并幂等更新驱动 Makefile/Kconfig。也可以指定提交或标签：

```sh
curl -LSs https://raw.githubusercontent.com/xiziya/SukiSU_Non-GKI/builtin/kernel/setup.sh | sh -s -- <commit-or-tag>
```

清理脚本所做的集成：

```sh
curl -LSs https://raw.githubusercontent.com/xiziya/SukiSU_Non-GKI/builtin/kernel/setup.sh | sh -s -- --cleanup
```

本地调试可以通过 `KSU_REPO`、`KSU_BRANCH`、`KSU_DIR` 覆盖默认来源。

## 4.9 + SUSFS 手动 hook 顺序

1. 在纯净内核树应用对应版本的 SUSFS patch。
2. 运行本仓库 `kernel/setup.sh`，使 `drivers/kernelsu` 可见。
3. 从内核根目录运行 SUSFS inline hook 脚本。
4. 启用 `CONFIG_KSU=y` 与所需的 `CONFIG_KSU_SUSFS*` 配置后正常编译。

旧版 `susfs_inline_hook_patches.sh` 会搜索 `ksu_hide_setprocattr`。本移植不伪造该旧接口，因此脚本会跳过那一个 hook；SELinux hide 由 Non-GKI 运行时兼容层接管。脚本中的其他 SukiSU/SUSFS inline hooks 不受影响。

## 已验证配置

验证使用 clang 12、arm64 GCC 交叉工具链、`vendor/xiaomi/mi845_defconfig` 和 `vendor/xiaomi/dipper.config`。具体结果见 `docs/verification.md`。

## 许可证

沿用上游项目的 GPL-2.0 许可证，详见 `LICENSE`。
