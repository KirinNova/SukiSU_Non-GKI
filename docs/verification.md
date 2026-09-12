# Verification

## Environment

- Date: 2026-09-12
- Kernel: Evolution-X-Devices `kernel_xiaomi_sdm845`, branch `bka`
- Kernel commit: `b0fb2a6d2d20c1f3219183e8590fff50a3a39fd6`
- Kernel version: `4.9.337`
- Architecture: `arm64`
- Compiler: clang 12 with Android GCC 64/32 cross toolchains
- Config: `vendor/xiaomi/mi845_defconfig` plus `vendor/xiaomi/dipper.config`
- SUSFS: `CONFIG_KSU_SUSFS=y`, with the supplied 4.9 patch and inline hook script applied
- LTO: disabled, matching the test build script's selectable fast-build path

## Results

The following stages completed successfully:

1. Kernel configuration and generated SELinux headers.
2. `drivers/kernelsu/built-in.o` including all `kernel/non_gki/` objects.
3. `vmlinux.o` MODPOST and final `vmlinux` link.
4. kallsyms, `System.map`, DTB compilation, `Image.gz`, and `Image.gz-dtb`.
5. `setup.sh` first install, repeated install, single-entry idempotence, relative symlink, and cleanup.

Final image:

```text
size:   24880853 bytes
sha256: d45504d5754569a42badbba6409b0029c545bdab7f1c59ef5d86f0476b2c4a9f
```

Relevant symbols found in the linked `vmlinux`:

```text
ksu_handle_post_execveat_sucompat
ksu_handle_selinux_setprocattr
ksu_init_symbol_resolver
ksu_selinux_hide_init
ksu_su_compat_enabled
```

The original 4.9 build stopped with 11 KernelSU errors: missing `fallthrough`, missing kernel umount setter, two undeclared SELinux hide boot handlers, missing `strncpy_from_user_nofault`, and five missing `current_sid()` declarations. Those errors are no longer present.

The first complete-link attempt also exposed two mismatches with the supplied legacy SUSFS inline hook script: its `ksu_su_compat_enabled` static-key contract and its call to the removed `ksu_handle_post_execveat_sucompat`. The port includes compatibility adapters for both, and the subsequent complete link succeeded.

## Scope

This is a compile and link verification against the named 4.9 kernel tree. Runtime boot and device-side SELinux hide behavior require flashing on the target device and are not claimed by this verification.
