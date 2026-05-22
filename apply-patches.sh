#!/bin/bash
# 将 RK3588-Alientek-AAOS 仓库中的所有补丁合入 Android 13 工程目录。
#
# 用法：
#   bash apply-patches.sh <ANDROID_ROOT>
#
# 参数：
#   ANDROID_ROOT  Android 13 工程根目录（必填）
#
# 配套脚本：
#   clean-patches.sh  撤销本脚本的所有改动（回滚到纯 repo 状态）

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="$REPO_DIR/Android-13"

# GCC 工具链常量
GCC_BASE="prebuilts/gcc/linux-x86"
ARM_TOOLCHAIN="gcc-linaro-6.3.1-2017.05-x86_64_arm-linux-gnueabihf"
AARCH64_TOOLCHAIN="gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu"

# ---------- 辅助函数 ----------
# extract_tar <tar_gz_path> <dest_dir>
# 支持完整文件和分卷文件（.part-aa, .part-ab, ...）两种形式。
# 返回 0 表示成功，1 表示源文件不存在。
extract_tar() {
    local tar_path="$1"
    local dest_dir="$2"
    if [[ -f "${tar_path}.part-aa" ]]; then
        cat "${tar_path}.part-"* | tar -xz -C "$dest_dir"
    elif [[ -f "$tar_path" ]]; then
        tar -xzf "$tar_path" -C "$dest_dir"
    else
        return 1
    fi
}

# ---------- 参数检查 ----------
if [[ $# -lt 1 ]]; then
    echo "[ERROR] 未指定 Android 工程目录"
    echo "        用法: bash apply-patches.sh <ANDROID_ROOT>"
    exit 1
fi

ANDROID_ROOT="${1%/}"

echo "========================================"
echo " RK3588-Alientek-AAOS 补丁合入脚本"
echo "========================================"
echo "[INFO] 仓库目录: $REPO_DIR"
echo "[INFO] 目标目录: $ANDROID_ROOT"
echo ""

# ---------- 目录校验 ----------
if [[ ! -d "$ANDROID_ROOT" ]]; then
    echo "[ERROR] 目标目录不存在: $ANDROID_ROOT"
    exit 1
fi

UBOOT_DIR="$PATCHES_DIR/u-boot"
RKBIN_DIR="$PATCHES_DIR/rkbin"
KERNEL_DIR="$PATCHES_DIR/rk-kernel-5.10"

# ---------- 冲突检测 ----------
# git diff 补丁：用 --check 探测能否干净应用（失败 = 已应用或存在冲突）
# 目录/文件添加类：检查目标是否已存在
CONFLICT=0
CONFLICT_REASON=""

# 文件/目录添加类
if [[ -f "$ANDROID_ROOT/build.sh" ]]; then
    CONFLICT=1; CONFLICT_REASON="build.sh 已存在"
fi
if [[ $CONFLICT -eq 0 && -d "$UBOOT_DIR" && -d "$ANDROID_ROOT/u-boot" ]]; then
    CONFLICT=1; CONFLICT_REASON="u-boot/ 已存在"
fi
if [[ $CONFLICT -eq 0 && -d "$RKBIN_DIR" && -d "$ANDROID_ROOT/rkbin" ]]; then
    CONFLICT=1; CONFLICT_REASON="rkbin/ 已存在"
fi
if [[ $CONFLICT -eq 0 && -d "$KERNEL_DIR" && -d "$ANDROID_ROOT/kernel-5.10" ]]; then
    CONFLICT=1; CONFLICT_REASON="kernel-5.10/ 已存在"
fi
if [[ $CONFLICT -eq 0 && -d "$ANDROID_ROOT/bootable/recovery/mtdutils" ]]; then
    CONFLICT=1; CONFLICT_REASON="bootable/recovery/mtdutils 已存在"
fi
if [[ $CONFLICT -eq 0 && -d "$ANDROID_ROOT/device/rockchip" ]]; then
    CONFLICT=1; CONFLICT_REASON="device/rockchip 已存在"
fi
if [[ $CONFLICT -eq 0 && -d "$ANDROID_ROOT/external/can-utils" ]]; then
    CONFLICT=1; CONFLICT_REASON="external/can-utils 已存在"
fi
if [[ $CONFLICT -eq 0 && -d "$ANDROID_ROOT/frameworks/av/media/libstagefright/wifi-display" ]]; then
    CONFLICT=1; CONFLICT_REASON="frameworks/av/media/libstagefright/wifi-display 已存在"
fi
if [[ $CONFLICT -eq 0 && -d "$ANDROID_ROOT/frameworks/base/services/core/java/com/android/server/rkdisplay" ]]; then
    CONFLICT=1; CONFLICT_REASON="frameworks/base/services/core/java/com/android/server/rkdisplay 已存在"
fi
if [[ $CONFLICT -eq 0 && -d "$ANDROID_ROOT/hardware/rockchip" ]]; then
    CONFLICT=1; CONFLICT_REASON="hardware/rockchip 已存在"
fi

# git diff 补丁：--check 探测（与 clean-patches.sh 对称）
for _patch in \
    "bionic:rk3588-bionic.patch" \
    "bootable:rk3588-bootable.patch" \
    "build:rk3588-build.patch" \
    "external:rk3588-external.patch" \
    "frameworks:rk3588-frameworks.patch" \
    "hardware:rk3588-hardware.patch" \
    "system:rk3588-system.patch" \
    "packages:rk3588-packages.patch"; do
    [[ $CONFLICT -eq 0 ]] || break
    _label="${_patch%%:*}"
    _file="$PATCHES_DIR/patches/${_patch##*:}"
    [[ -f "$_file" ]] || continue
    if ! git -C "$REPO_DIR" apply --check --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$_file"; then
        CONFLICT=1
        CONFLICT_REASON="${_label} 补丁已应用或存在冲突"
    fi
done

if [[ $CONFLICT -eq 1 ]]; then
    echo "[WARN] 检测到冲突（${CONFLICT_REASON}），为避免覆盖现有文件，本次合入已终止。"
    echo ""
    echo "       如需重新合入，可通过以下任一方式清理后重试："
    echo "         bash clean-patches.sh $ANDROID_ROOT  （推荐，精确回滚补丁文件）"
    echo "         repo sync -c -d --no-tags -j4        （完整同步，重置整个工程）"
    echo "       然后重新执行本脚本。"
    exit 1
fi

# ---------- 补丁 1：build.sh ----------
# 主编译脚本，负责环境检查、源码修复、source build/envsetup.sh、lunch 及各模块构建
echo "[1/15] 复制 build.sh 到 $ANDROID_ROOT ..."
cp "$PATCHES_DIR/build.sh" "$ANDROID_ROOT/build.sh"
chmod +x "$ANDROID_ROOT/build.sh"
echo "[DONE] $ANDROID_ROOT/build.sh"

# ---------- 补丁 2：u-boot ----------
# 移植项目的 u-boot 部分，复制到 Android 工程根目录
echo "[2/15] 复制 u-boot ..."
if [[ -d "$UBOOT_DIR" ]]; then
    cp -r "$UBOOT_DIR" "$ANDROID_ROOT/u-boot"
    # u-boot 是子模块，内含指向父仓库的 .git 文件（gitdir 相对路径）。
    # cp 后路径失效会导致 git 报错；Android 构建不需要 git 历史，直接删除。
    rm -f "$ANDROID_ROOT/u-boot/.git"
    echo "[DONE] u-boot 已复制到 $ANDROID_ROOT/u-boot"
else
    echo "[SKIP] Android-13/u-boot 目录不存在，跳过"
fi

# ---------- 补丁 3：rkbin ----------
# Rockchip 固件 bin 文件，u-boot 打包时依赖
echo "[3/15] 复制 rkbin ..."
if [[ -d "$RKBIN_DIR" ]]; then
    cp -r "$RKBIN_DIR" "$ANDROID_ROOT/rkbin"
    # 同上，删除子模块遗留的 .git 文件，避免路径失效报错
    rm -f "$ANDROID_ROOT/rkbin/.git"
    echo "[DONE] rkbin 已复制到 $ANDROID_ROOT/rkbin"
else
    echo "[SKIP] Android-13/rkbin 目录不存在，跳过"
fi

# ---------- 补丁 4：kernel-5.10 ----------
# Android 13 内核源码，build.sh 编译内核时从 kernel-5.10/ 目录读取
echo "[4/15] 复制 kernel-5.10 ..."
if [[ -d "$KERNEL_DIR" ]]; then
    cp -r "$KERNEL_DIR" "$ANDROID_ROOT/kernel-5.10"
    # 同上，删除子模块遗留的 .git 文件
    rm -f "$ANDROID_ROOT/kernel-5.10/.git"

    # 读取外层仓库的分支名和 short hash，供 git 初始化和 .scmversion 共用
    OUTER_BRANCH="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
    OUTER_HASH="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || true)"

    # 初始化 git 仓库，同步分支名并创建空 commit 使 HEAD 有效。
    # 消除内核 Makefile 触发的两类 git 警告：
    #   "fatal: not a git repository"
    #   "fatal: your current branch '...' does not have any commits yet"
    # scripts/setlocalversion 优先读取 .scmversion，存在时跳过所有 git 调用。
    git -C "$ANDROID_ROOT/kernel-5.10" init -q
    git -C "$ANDROID_ROOT/kernel-5.10" symbolic-ref HEAD "refs/heads/${OUTER_BRANCH}"
    GIT_AUTHOR_NAME="build" GIT_AUTHOR_EMAIL="build@local" \
    GIT_COMMITTER_NAME="build" GIT_COMMITTER_EMAIL="build@local" \
    git -C "$ANDROID_ROOT/kernel-5.10" commit --allow-empty -q \
        -m "sync: ${OUTER_BRANCH}@${OUTER_HASH}"
    echo "[DONE] kernel-5.10 已复制到 $ANDROID_ROOT/kernel-5.10"

    # 生成 .scmversion：写入来自外层仓库的版本后缀，
    # setlocalversion 读到此文件后直接返回，不再调用 git describe。
    SCMVER="${OUTER_HASH:+-g${OUTER_HASH}}"
    printf '%s' "$SCMVER" > "$ANDROID_ROOT/kernel-5.10/.scmversion"
    echo "[DONE] .scmversion = \"${SCMVER}\" (来自 RK3588-Alientek-AAOS 仓库 HEAD)"
else
    echo "[SKIP] Android-13/rk-kernel-5.10 目录不存在，跳过"
fi

# ---------- 补丁 5：GCC 工具链 ----------
# gcc-linaro-6.3.1 是 U-Boot 构建脚本硬编码的工具链，不可替换
echo "[5/15] 解压 GCC 工具链 (gcc-linaro-6.3.1) ..."
ARM_SRC="$PATCHES_DIR/$GCC_BASE/arm/${ARM_TOOLCHAIN}.tar.xz"
AARCH64_SRC="$PATCHES_DIR/$GCC_BASE/aarch64/${AARCH64_TOOLCHAIN}.tar.xz"
ARM_DEST="$ANDROID_ROOT/$GCC_BASE/arm"
AARCH64_DEST="$ANDROID_ROOT/$GCC_BASE/aarch64"

if [[ -d "$ARM_DEST/$ARM_TOOLCHAIN" ]]; then
    echo "[SKIP] 32 位工具链已存在，跳过"
elif [[ -f "$ARM_SRC" ]]; then
    echo "  [32位] 解压 arm-linux-gnueabihf 工具链 ..."
    mkdir -p "$ARM_DEST"
    tar -xf "$ARM_SRC" -C "$ARM_DEST"
    echo "[DONE] 32 位工具链: $ARM_DEST/$ARM_TOOLCHAIN"
else
    echo "[WARN] 32 位工具链压缩包不存在: $ARM_SRC，跳过"
fi

if [[ -d "$AARCH64_DEST/$AARCH64_TOOLCHAIN" ]]; then
    echo "[SKIP] 64 位工具链已存在，跳过"
elif [[ -f "$AARCH64_SRC" ]]; then
    echo "  [64位] 解压 aarch64-linux-gnu 工具链 ..."
    mkdir -p "$AARCH64_DEST"
    tar -xf "$AARCH64_SRC" -C "$AARCH64_DEST"
    echo "[DONE] 64 位工具链: $AARCH64_DEST/$AARCH64_TOOLCHAIN"
else
    echo "[WARN] 64 位工具链压缩包不存在: $AARCH64_SRC，跳过"
fi

# ---------- 补丁 6：bionic ----------
# git diff 补丁修改 1 个文件（bionic/libc/Android.bp：libstdc++ 新增 vendor_available: true）
echo "[6/15] 应用 bionic git diff 补丁 ..."
BIONIC_PATCH_FILE="$PATCHES_DIR/patches/rk3588-bionic.patch"

if [[ -f "$BIONIC_PATCH_FILE" ]]; then
    git -C "$REPO_DIR" apply --unsafe-paths \
        --directory="$ANDROID_ROOT" \
        "$BIONIC_PATCH_FILE"
    echo "[DONE] bionic git diff 补丁已应用（1 个文件）"
else
    echo "[WARN] 补丁文件不存在: $BIONIC_PATCH_FILE，跳过"
fi

# ---------- 补丁 7：bootable/recovery ----------
# git diff 补丁修改 21 个文件（bootable/recovery 各子目录）
# tar.gz 包含 4 个 RK 专有目录（mtdutils pcba_core rkupdate rkutility）
echo "[7/15] 应用 bootable/recovery git diff 补丁并解压 RK 专有目录 ..."
BOOTABLE_PATCH_FILE="$PATCHES_DIR/patches/rk3588-bootable.patch"
RK_DIRS_TAR="$PATCHES_DIR/patches/rk3588-recovery-rk-dirs.tar.gz"

if [[ -f "$BOOTABLE_PATCH_FILE" ]]; then
    git -C "$REPO_DIR" apply --unsafe-paths \
        --directory="$ANDROID_ROOT" \
        "$BOOTABLE_PATCH_FILE"
    echo "[DONE] bootable/recovery git diff 补丁已应用（21 个文件）"
else
    echo "[WARN] 补丁文件不存在: $BOOTABLE_PATCH_FILE，跳过"
fi

if [[ -f "$RK_DIRS_TAR" ]]; then
    tar -xzf "$RK_DIRS_TAR" -C "$ANDROID_ROOT/bootable/recovery/"
    echo "[DONE] RK 专有目录已解压到 $ANDROID_ROOT/bootable/recovery/"
else
    echo "[WARN] tar.gz 不存在: $RK_DIRS_TAR，跳过"
fi

# ---------- 补丁 8：build 目录 ----------
# git diff 补丁修改 12 个文件 + 1 个新文件（package_loader_zip.py）
# 涵盖：core/Makefile、main.mk、soong_config.mk、sysprop.mk、version_util.mk、
#        envsetup.sh、releasetools/common.py、edify_generator.py、
#        soong/android/variable.go、soong/apex/apex_test.go + prebuilt.go、
#        soong/cc/config/global.go（加 -DANDROID_13）
# SKIP：build_id.mk（版本号差异）、generic_ramdisk.mk（AOSP 13 支持这些 ramdisk 工具）
echo "[8/15] 应用 build 目录 git diff 补丁 ..."
BUILD_PATCH_FILE="$PATCHES_DIR/patches/rk3588-build.patch"
if [[ -f "$BUILD_PATCH_FILE" ]]; then
    git -C "$REPO_DIR" apply --unsafe-paths \
        --directory="$ANDROID_ROOT" \
        "$BUILD_PATCH_FILE"
    echo "[DONE] build 目录补丁已应用（13 个文件）"
else
    echo "[WARN] 补丁文件不存在: $BUILD_PATCH_FILE，跳过"
fi

# ---------- 补丁 9：external 目录 ----------
# git diff 补丁修改/新增 26 个文件（e2fsprogs、iperf3、libdrm、skia、speex、tinyalsa、wpa_supplicant_8）
# tar.gz 包含 8 个 RK 专有目录（camera_engine_rkaiq、can-utils、e2fsprogs/libiconv、io、libdrm/rockchip、ntfs-3g、rk_tee_user、wifi_driver）
echo "[9/15] 应用 external 目录 git diff 补丁并解压 RK 专有目录 ..."
EXT_PATCH_FILE="$PATCHES_DIR/patches/rk3588-external.patch"
EXT_RK_DIRS_TAR="$PATCHES_DIR/patches/rk3588-external-rk-dirs.tar.gz"

if [[ -f "$EXT_PATCH_FILE" ]]; then
    git -C "$REPO_DIR" apply --unsafe-paths \
        --directory="$ANDROID_ROOT" \
        "$EXT_PATCH_FILE"
    echo "[DONE] external git diff 补䬁已应用5（26 个文件）"
else
    echo "[WARN] 补丁文件不存在: $EXT_PATCH_FILE，跳过"
fi

if extract_tar "$EXT_RK_DIRS_TAR" "$ANDROID_ROOT"; then
    echo "[DONE] external RK 专有目录已解压到 $ANDROID_ROOT/external/"
else
    echo "[WARN] tar.gz 不存在: $EXT_RK_DIRS_TAR，跳过"
fi

# ---------- 补丁 10：device/rockchip ----------
# RK3588 专有 device 目录，包含板级配置、overlay、脚本等
echo "[10/15] 解压 device/rockchip ..."
DEV_RK_TAR="$PATCHES_DIR/patches/rk3588-device-rk-dirs.tar.gz"
if extract_tar "$DEV_RK_TAR" "$ANDROID_ROOT"; then
    echo "[DONE] device/rockchip 已解压到 $ANDROID_ROOT/device/rockchip"
else
    echo "[WARN] tar.gz 不存在: $DEV_RK_TAR，跳过"
fi

# ---------- 补丁 11：frameworks（全部子目录合并）----------
# 1 个合并 patch（247 个文件），1 个合并 tar.gz（55 个 RK 专有文件）
# 涵盖 av / base / base-packages / base-services / ex / native / opt 所有改动
echo "[11/15] 应用全部 frameworks git diff 补丁并解压 RK 专有文件 ..."

FW_PATCH_FILE="$PATCHES_DIR/patches/rk3588-frameworks.patch"
FW_RK_FILES_TAR="$PATCHES_DIR/patches/rk3588-frameworks-rk-files.tar.gz"
if [[ -f "$FW_PATCH_FILE" ]]; then
    git -C "$REPO_DIR" apply --unsafe-paths --directory="$ANDROID_ROOT" "$FW_PATCH_FILE"
    echo "  [DONE] frameworks 全部子目录（247 个文件）"
else
    echo "  [WARN] 补丁不存在: $FW_PATCH_FILE"
fi
if [[ -f "$FW_RK_FILES_TAR" ]]; then
    tar -xzf "$FW_RK_FILES_TAR" -C "$ANDROID_ROOT/frameworks"
    echo "  [DONE] frameworks RK 专有文件已解压（55 个文件）"
else
    echo "  [WARN] tar.gz 不存在: $FW_RK_FILES_TAR"
fi
# art-profile：RK 在文件末尾追加 4 个 rkdisplay 预编译类（无扩展名，未被 patch 覆盖）
ART_PROFILE="$ANDROID_ROOT/frameworks/base/services/art-profile"
if [[ -f "$ART_PROFILE" ]]; then
    if ! grep -qF "Lcom/android/server/rkdisplay/RkDisplayModes;" "$ART_PROFILE"; then
        printf '\nLcom/android/server/rkdisplay/RkDisplayModes$RkPhysicalDisplayInfo;\nLcom/android/server/rkdisplay/RkDisplayModes$RkColorCapacityInfo;\nLcom/android/server/rkdisplay/RkDisplayModes$RkConnectorInfo;\nLcom/android/server/rkdisplay/RkDisplayModes;\n' >> "$ART_PROFILE"
        echo "  [DONE] art-profile 已追加 4 个 rkdisplay ART 预编译类"
    else
        echo "  [SKIP] art-profile rkdisplay 条目已存在"
    fi
else
    echo "  [WARN] art-profile 不存在: $ART_PROFILE"
fi

# ---------- 补丁 12：hardware ----------
# git diff 补丁修改 36 个文件（broadcom/libbt、interfaces/audio/bluetooth/camera/graphics/wifi、libhardware、ril）
# tar.gz 包含 4 个 RK-only 顶级目录（aic、bes、realtek、rockchip）+ 子目录和 RK 专有文件
# 解压后追加 rk3588-librga-android13.patch：
#   将 librga/include/drmrga.h 中 ANDROID_12 改为 ANDROID_13，与 global.go 的 -DANDROID_13 对齐
echo "[12/15] 应用 hardware git diff 补丁并解压 RK 专有文件 ..."

HW_PATCH_FILE="$PATCHES_DIR/patches/rk3588-hardware.patch"
HW_RK_FILES_TAR="$PATCHES_DIR/patches/rk3588-hardware-rk-files.tar.gz"
LIBRGA_PATCH="$PATCHES_DIR/patches/rk3588-librga-android13.patch"
if [[ -f "$HW_PATCH_FILE" ]]; then
    git -C "$REPO_DIR" apply --unsafe-paths --directory="$ANDROID_ROOT" "$HW_PATCH_FILE"
    echo "  [DONE] hardware git diff 补丁已应用（36 个文件）"
else
    echo "  [WARN] 补丁不存在: $HW_PATCH_FILE"
fi
if extract_tar "$HW_RK_FILES_TAR" "$ANDROID_ROOT/hardware"; then
    echo "  [DONE] hardware RK 专有文件已解压（aic/bes/realtek/rockchip 等）"
else
    echo "  [WARN] tar.gz 不存在: $HW_RK_FILES_TAR"
fi
# tar.gz 解压后立即修正 drmrga.h：ANDROID_12 → ANDROID_13
if [[ -f "$LIBRGA_PATCH" ]]; then
    git -C "$REPO_DIR" apply --unsafe-paths --directory="$ANDROID_ROOT" "$LIBRGA_PATCH"
    echo "  [DONE] librga/drmrga.h 已更新（ANDROID_12 → ANDROID_13）"
else
    echo "  [WARN] 补丁不存在: $LIBRGA_PATCH"
fi

# ---------- 补丁 13：system ----------
# git diff 补丁修改 18 个文件（core/healthd、core/init、core/libcutils、core/libsync、core/rootdir、extras/su、media/audio、vold）
# tar.gz 包含 2 个 RK-only 文件（system/vold/fs/Ntfs.cpp、Ntfs.h）
echo "[13/15] 应用 system git diff 补丁并解压 RK 专有文件 ..."

SYS_PATCH_FILE="$PATCHES_DIR/patches/rk3588-system.patch"
SYS_RK_FILES_TAR="$PATCHES_DIR/patches/rk3588-system-rk-files.tar.gz"
if [[ -f "$SYS_PATCH_FILE" ]]; then
    git -C "$REPO_DIR" apply --unsafe-paths --directory="$ANDROID_ROOT" "$SYS_PATCH_FILE"
    echo "  [DONE] system git diff 补丁已应用（18 个文件）"
else
    echo "  [WARN] 补丁不存在: $SYS_PATCH_FILE"
fi
if [[ -f "$SYS_RK_FILES_TAR" ]]; then
    tar -xzf "$SYS_RK_FILES_TAR" -C "$ANDROID_ROOT"
    echo "  [DONE] system RK 专有文件已解压（vold/fs/Ntfs.cpp + Ntfs.h）"
else
    echo "  [WARN] tar.gz 不存在: $SYS_RK_FILES_TAR"
fi

# ---------- 补丁 14：packages ----------
# git diff 补丁修改 394 个文件（Calendar/Camera2/Gallery2/KeyChain/Music/Settings/TvSettings/TV/
#   Bluetooth/Connectivity/Wifi/MediaProvider/Telecomm 等各子模块）
# tar.gz 包含 RK-only 整体 app（DisplayAdjust/ExactCalculator/SoundRecorder/rkCamera2）
#   + 现有 app 中的 RK-only 资源/源码文件（Camera2/Gallery2/Music/Settings/TvSettings/TV）
#   + Bluetooth APEX 签名文件（avbpubkey/pem）
echo "[14/15] 应用 packages git diff 补丁并解压 RK 专有文件 ..."

PKG_PATCH_FILE="$PATCHES_DIR/patches/rk3588-packages.patch"
PKG_RK_FILES_TAR="$PATCHES_DIR/patches/rk3588-packages-rk-files.tar.gz"
if [[ -f "$PKG_PATCH_FILE" ]]; then
    git -C "$REPO_DIR" apply --unsafe-paths --directory="$ANDROID_ROOT" "$PKG_PATCH_FILE"
    echo "  [DONE] packages git diff 补丁已应用（394 个文件）"
else
    echo "  [WARN] 补丁不存在: $PKG_PATCH_FILE"
fi
if [[ -f "$PKG_RK_FILES_TAR" ]]; then
    tar -xzf "$PKG_RK_FILES_TAR" -C "$ANDROID_ROOT"
    echo "  [DONE] packages RK 专有文件已解压（DisplayAdjust/ExactCalculator/SoundRecorder/rkCamera2 等）"
else
    echo "  [WARN] tar.gz 不存在: $PKG_RK_FILES_TAR"
fi

# ---------- 补丁 15：vendor ----------
# vendor/ 目录在 AOSP 标准树中不存在，全部为 RK-only 内容：
#   rk3588-vendor.tar.gz（~405 MB）：
#     vendor/widevine — Widevine DRM
#     vendor/rockchip/hardware/interfaces — RK HAL 接口
#     vendor/rockchip/common — common（gpu/MaliG610、apps、eptz、vpu、wifi 等）
#   注：打包时已排除其他芯片 GPU 变体（Mali400/G52/T760/T860/libG6110）
#   由于文件体积超过 GitHub 100 MB 单文件限制，需配置 Git LFS 后再 push：
#     git lfs install && git lfs track "Android-13/patches/rk3588-vendor.tar.gz"
echo "[15/15] 解压 vendor RK 专有内容 ..."

VENDOR_TAR="$PATCHES_DIR/patches/rk3588-vendor.tar.gz"

if extract_tar "$VENDOR_TAR" "$ANDROID_ROOT"; then
    echo "  [DONE] vendor 已解压（widevine + rockchip/hardware/interfaces + rockchip/common）"
else
    echo "  [WARN] tar.gz 不存在: $VENDOR_TAR（分卷或完整包均未找到），跳过"
    echo "         跳过 vendor/ 解压，系统可编译但 GPU 驱动、Widevine DRM 及预装 APK 缺失"
fi

echo ""
echo "========================================"
echo " 所有补丁已合入完成"
echo ""
echo " 常用编译命令："
echo "   bash $ANDROID_ROOT/build.sh -K   # 编译内核"
echo "   bash $ANDROID_ROOT/build.sh -U   # 编译 U-Boot"
echo "========================================"
