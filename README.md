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
- `kernel/Makefile` 保留官方 builtin 的版本/UAPI 契约；GitHub API 或 `main` 引用不可用时使用本地提交计数或 `VERSION_BASE`，避免错误回退到管理器拒绝的 `KSU_VERSION=13000`。
- 兼容旧版 Manager 的 app-profile v2/v3 ioctl：按用户空间版本读写 776 字节前缀，并迁移到当前 v4 profile。
- `post-fs-data` 在 observer 注册后增加一次性 manager UID 扫描，覆盖 `packages.list` 已存在的旧版 Android 启动时序。
- Non-GKI 的每条 SELinux policy 更新路径都会刷新 SUSFS SID 缓存；原补丁的 `kernel/selinux/rules.c` hunk 不会覆盖实际编译的 `kernel/non_gki/rules.c`，已按实际入口移植。

这些兼容修改已经直接合并在本仓库源码中。GitHub Actions 会从当前 checkout 直接运行 `kernel/setup.sh`，不再额外应用 Manager 兼容补丁，避免重复修改或上下文冲突。

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

## GitHub Actions 通用构建

`.github/workflows/build-custom-kernel.yml` 提供 `workflow_dispatch` 构建入口。必须填写设备 `codename` 和以 `.git` 结尾的纯净内核仓库；`kernel_branch` 默认 `bka`。`defconfig` 请输入目录下的 `*_defconfig` 路径，例如 `vendor/xiaomi/mi845_defconfig`，也可以留空让工作流按 codename 自动探测；只有唯一候选才会自动使用，多个候选会直接失败并列出候选。`device_config` 是可选的 `目录/*.config` 路径。

其余输入覆盖作者、A/B 分区、LTO、SUSFS + SukiSU 兼容版、内核名（空值为 `by_XiZi`）、构建时间、内核版本、DroidSpaces 和 AnyKernel3。构建身份会写入 `KBUILD_BUILD_USER`，自定义时间写入 `KBUILD_BUILD_TIMESTAMP`，内核 localversion 延续 `build.sh` 的 `-名称-版本-日期` 规则。

工作流会严格读取内核根 `Makefile` 的 `VERSION`/`PATCHLEVEL`，选择 `susfs_patch_to_<版本>.patch`；补丁产生 `.rej` 时失败并保留日志。启用 DroidSpaces 会从官方最新 release 下载 APK/runtime，并在 SUSFS 同时启用时显示官方兼容性警告。启用 AnyKernel3 后会按 codename 和 A/B 选择生成 `anykernel.sh`，并写入指定的刷入提示文案。

示范模板位于 `.github/workflows/temple/build-custom-kernel-example.yml`。GitHub 不会执行 `temple/` 子目录中的文件；需要实际运行时请使用根目录的活动工作流。

## 已验证配置

验证使用 clang 12、arm64 GCC 交叉工具链、`vendor/xiaomi/mi845_defconfig` 和 `vendor/xiaomi/dipper.config`。具体结果见 `docs/verification.md`。

## 许可证以及鸣谢名单

沿用上游项目的 GPL-2.0 许可证，详见 `LICENSE`。
## 🙏 鸣谢

感谢所有为本项目提供帮助、建议、代码贡献的朋友：

- @JackAltMan 

> 特别感谢开源社区相关项目带来的启发。




