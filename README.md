# SukiSU Non-GKI

这是基于 SukiSU Ultra `builtin` 分支的增量兼容移植，目标是在旧版 Non-GKI 内核中保留 SukiSU Ultra 的工作流，并补齐 SELinux hide 所需的接口和运行时 hook。

> 这是非官方移植。5.10 及以上内核继续使用 SukiSU Ultra 原有实现；新增兼容代码只在 `< 5.10` 时编译。

## 基线

- SukiSU Ultra `builtin`: `b20dee702035af09cb2ecb5f35443bbc1747f3e6`
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

### Zygisk Next 兼容性说明

Zygisk Next 是用户空间模块，不由 KernelSU 内核驱动实现。上游识别依赖 `GET_INFO` 返回的 `KSU_VERSION`、UAPI 版本和功能位；本仓库保留了 SukiSU Ultra 的 UAPI 编号，并在离线/浅克隆时使用稳定的非零版本回退，避免管理器把内核误判为旧版或不支持。内核本身没有可安全添加的“Zygisk 已启用”位，因此“需要重启”提示不能通过伪造一个内核功能位解决；安装/升级 Zygisk Next 后按其模块说明重启一次是正常行为。若重启后仍显示该提示，应提供 Zygisk Next bugreport 及管理器版本，不能仅凭内核编译日志判断。

## GitHub Actions 通用构建

`.github/workflows/build-custom-kernel-Zh_CN.yml` 提供简体中文 `workflow_dispatch` 构建入口，`.github/workflows/build-custom-kernel-Eng.yml` 提供英文入口。两者使用完全相同的构建逻辑和输入参数，仅界面显示语言不同。必须填写设备 `codename` 和以 `.git` 结尾的纯净内核仓库；`kernel_branch` 默认 `bka`。`defconfig` 请输入目录下的 `*_defconfig` 路径，例如 `vendor/xiaomi/mi845_defconfig`，也可以留空让工作流按 codename 自动探测；只有唯一候选才会自动使用，多个候选会直接失败并列出候选。`device_config` 是可选的 `目录/*.config` 路径。

工作流最前面提供可选的内核版本伪装开关。启用后必须填写 `主版本.次版本.子版本` 三段纯数字版本号，例如 `4.9.337`；工作流会自动解析并分别写入内核根 `Makefile` 的 `VERSION`、`PATCHLEVEL` 和 `SUBLEVEL`。伪装步骤严格位于 SukiSU、机型补丁以及 SUSFS/inline hook 集成之后，因此 SUSFS 补丁仍按源码真实版本选择。跨主版本或次版本伪装可能令后续编译选择不兼容的内核 API，工作流会输出警告，通常应只调整同一内核系列的子版本号。

其余输入覆盖作者、A/B 分区、LTO、SUSFS + SukiSU 兼容版、内核名（空值为 `by_XiZi`）、构建时间、内核版本、DroidSpaces 和 AnyKernel3。构建身份会写入 `KBUILD_BUILD_USER`，自定义时间写入 `KBUILD_BUILD_TIMESTAMP`，内核 localversion 延续 `build.sh` 的 `-名称-版本-日期` 规则。启用 DroidSpaces 时，工作流会额外强制写入官方 Non-GKI 要求的 `CONFIG_USER_NS=y`，避免旧版配置片段遗漏该选项。构建报告会同时记录源码真实版本、版本伪装目标和伪装执行状态。

对于没有现代 VFS/backport 的碎片化 Non-GKI 内核，可以启用“机型专属补丁”。工作流会 clone 指定的 `.git` 仓库和分支，从其 `Patches/` 目录按空格分隔的文件名逐个应用，顺序位于 SukiSU、SUSFS 和 inline hook 之前；补丁失败会终止构建，应用数量、仓库、分支和状态会写入 build report。关闭开关时这些仓库和文件输入不会被读取。

工作流会严格读取内核根 `Makefile` 的 `VERSION`/`PATCHLEVEL`，选择 `susfs_patch_to_<版本>.patch`。SUSFS 或 inline hook 补丁失败时，工作流会在生成报告前收集内核树中的 `.rej`、`.orig`、补丁源文件和完整应用日志，并随构建产物上传供下载排查。启用 DroidSpaces 会从官方最新 release 下载 APK/runtime，并在 SUSFS 同时启用时显示官方兼容性警告。启用 AnyKernel3 后会按 codename 和 A/B 选择生成 `anykernel.sh`，并写入指定的刷入提示文案。

可用以下命令生成只包含兼容源码的上游基线补丁，默认基于 SukiSU Ultra `builtin` 提交 `b20dee702035af09cb2ecb5f35443bbc1747f3e6`：

```sh
bash .github/scripts/generate-upstream-compat-patch.sh
```

输出文件为 `artifacts/sukisu-ultra-builtin-non-gki-compat.patch`。更新上游基线后设置 `UPSTREAM_REF` 再生成，便于审查兼容逻辑并移植到后续版本。

示范模板位于 `.github/workflows/temple/build-custom-kernel-example.yml`。GitHub 不会执行 `temple/` 子目录中的文件；需要实际运行时请使用根目录的活动工作流。

## 已验证配置

验证使用 clang 12、arm64 GCC 交叉工具链、`vendor/xiaomi/mi845_defconfig` 和 `vendor/xiaomi/dipper.config`。具体结果见 `docs/verification.md`。

## 许可证以及鸣谢名单

沿用上游项目的 GPL-2.0 许可证，详见 `LICENSE`。
## 🙏 鸣谢
感谢所有为本项目提供帮助、建议、代码贡献的朋友：

- [@JackA1ltMan](https://github.com/JackA1ltMan)
- [@KirinNova](https://github.com/KirinNova)
- [@ShirkNeko](https://github.com/ShirkNeko)（SukiSU上游）

> 特别感谢开源社区相关项目带来的启发。
