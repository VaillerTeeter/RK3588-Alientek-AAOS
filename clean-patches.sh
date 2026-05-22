#!/bin/bash
# 清理 apply-patches.sh 合入到 Android 工程目录的所有文件。
#
# 用法：
#   bash clean-patches.sh <ANDROID_ROOT>
#
# 参数：
#   ANDROID_ROOT  Android 13 工程根目录（必填）
#
# 配套脚本：
#   apply-patches.sh  将补丁合入指定 Android 13 工程目录

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# GCC 工具链常量
GCC_BASE="prebuilts/gcc/linux-x86"
ARM_TOOLCHAIN="gcc-linaro-6.3.1-2017.05-x86_64_arm-linux-gnueabihf"
AARCH64_TOOLCHAIN="gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu"

# ---------- 参数检查 ----------
if [[ $# -lt 1 ]]; then
    echo "[ERROR] 未指定 Android 工程目录"
    echo "        用法: bash clean-patches.sh <ANDROID_ROOT>"
    exit 1
fi

ANDROID_ROOT="${1%/}"

if [[ ! -d "$ANDROID_ROOT" ]]; then
    echo "[ERROR] 目标目录不存在: $ANDROID_ROOT"
    exit 1
fi

echo "========================================"
echo " RK3588-Alientek-AAOS 补丁清理脚本"
echo "========================================"
echo "[INFO] 目标目录: $ANDROID_ROOT"
echo ""

# 补丁 1：build.sh
TARGET="$ANDROID_ROOT/build.sh"
if [[ -f "$TARGET" ]]; then
    rm -f "$TARGET"
    echo "[DONE] 已删除 build.sh"
else
    echo "[SKIP] build.sh 不存在"
fi

# 补丁 2：u-boot
TARGET="$ANDROID_ROOT/u-boot"
if [[ -d "$TARGET" ]]; then
    rm -rf "$TARGET"
    echo "[DONE] 已删除 u-boot/"
else
    echo "[SKIP] u-boot/ 不存在"
fi

# 补丁 3：rkbin
TARGET="$ANDROID_ROOT/rkbin"
if [[ -d "$TARGET" ]]; then
    rm -rf "$TARGET"
    echo "[DONE] 已删除 rkbin/"
else
    echo "[SKIP] rkbin/ 不存在"
fi

# 补丁 4：kernel-5.10
TARGET="$ANDROID_ROOT/kernel-5.10"
if [[ -d "$TARGET" ]]; then
    rm -rf "$TARGET"
    echo "[DONE] 已删除 kernel-5.10/"
else
    echo "[SKIP] kernel-5.10/ 不存在"
fi

# 补丁 5：GCC 工具链（仅删除解压目录，保留压缩包）
ARM_DIR="$ANDROID_ROOT/$GCC_BASE/arm/$ARM_TOOLCHAIN"
if [[ -d "$ARM_DIR" ]]; then
    rm -rf "$ARM_DIR"
    echo "[DONE] 已删除 32 位工具链目录"
else
    echo "[SKIP] 32 位工具链目录不存在"
fi

AARCH64_DIR="$ANDROID_ROOT/$GCC_BASE/aarch64/$AARCH64_TOOLCHAIN"
if [[ -d "$AARCH64_DIR" ]]; then
    rm -rf "$AARCH64_DIR"
    echo "[DONE] 已删除 64 位工具链目录"
else
    echo "[SKIP] 64 位工具链目录不存在"
fi

# 补丁 6：bionic（git diff 补丁）
BIONIC_PATCH_FILE="$REPO_DIR/Android-13/patches/rk3588-bionic.patch"
if [[ -f "$BIONIC_PATCH_FILE" ]]; then
    if git -C "$REPO_DIR" apply -R --check --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$BIONIC_PATCH_FILE" 2>/dev/null; then
        git -C "$REPO_DIR" apply -R --reject --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$BIONIC_PATCH_FILE" 2>/dev/null \
            || echo "[WARN] git apply -R 部分失败，请检查 .rej 文件"
        echo "[DONE] bionic git diff 补丁已撤销"
    else
        echo "[SKIP] bionic git diff 补丁未应用，跳过"
    fi
else
    echo "[SKIP] 补丁文件不存在: $BIONIC_PATCH_FILE"
fi

# 补丁 7：bootable/recovery（git diff 补丁 + RK 专有目录）
BOOTABLE_PATCH_FILE="$REPO_DIR/Android-13/patches/rk3588-bootable.patch"
if [[ -f "$BOOTABLE_PATCH_FILE" ]]; then
    if git -C "$REPO_DIR" apply -R --check --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$BOOTABLE_PATCH_FILE" 2>/dev/null; then
        git -C "$REPO_DIR" apply -R --reject --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$BOOTABLE_PATCH_FILE" 2>/dev/null \
            || echo "[WARN] git apply -R 部分失败，请检查 .rej 文件"
        echo "[DONE] bootable/recovery git diff 补丁已撤销"
    else
        echo "[SKIP] bootable/recovery git diff 补丁未应用，跳过"
    fi
else
    echo "[SKIP] 补丁文件不存在: $BOOTABLE_PATCH_FILE"
fi

for rk_dir in mtdutils pcba_core rkupdate rkutility; do
    TARGET="$ANDROID_ROOT/bootable/recovery/$rk_dir"
    if [[ -d "$TARGET" ]]; then
        rm -rf "$TARGET"
        echo "[DONE] 已删除 bootable/recovery/$rk_dir"
    else
        echo "[SKIP] bootable/recovery/$rk_dir 不存在"
    fi
done

# 补丁 8：build 目录（git diff 补丁）
BUILD_PATCH_FILE="$REPO_DIR/Android-13/patches/rk3588-build.patch"
if [[ -f "$BUILD_PATCH_FILE" ]]; then
    if git -C "$REPO_DIR" apply -R --check --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$BUILD_PATCH_FILE" 2>/dev/null; then
        git -C "$REPO_DIR" apply -R --reject --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$BUILD_PATCH_FILE" 2>/dev/null \
            || echo "[WARN] git apply -R 部分失败，请检查 .rej 文件"
        echo "[DONE] build 目录 git diff 补丁已撤销"
    else
        echo "[SKIP] build git diff 补丁未应用，跳过"
    fi
else
    echo "[SKIP] 补丁文件不存在: $BUILD_PATCH_FILE"
fi

# 补丁 9：external 目录（git diff 补丁 + RK 专有目录）
EXT_PATCH_FILE="$REPO_DIR/Android-13/patches/rk3588-external.patch"
if [[ -f "$EXT_PATCH_FILE" ]]; then
    if git -C "$REPO_DIR" apply -R --check --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$EXT_PATCH_FILE" 2>/dev/null; then
        git -C "$REPO_DIR" apply -R --reject --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$EXT_PATCH_FILE" 2>/dev/null \
            || echo "[WARN] git apply -R 部分失败，请检查 .rej 文件"
        echo "[DONE] external git diff 补丁已撤销"
    else
        echo "[SKIP] external git diff 补丁未应用，跳过"
    fi
else
    echo "[SKIP] 补丁文件不存在: $EXT_PATCH_FILE"
fi

for rk_dir in \
    external/camera_engine_rkaiq \
    external/can-utils \
    external/e2fsprogs/lib/blkid/libiconv \
    external/io \
    external/libdrm/rockchip \
    external/ntfs-3g \
    external/rk_tee_user \
    external/wifi_driver; do
    TARGET="$ANDROID_ROOT/$rk_dir"
    if [[ -e "$TARGET" ]]; then
        rm -rf "$TARGET"
        echo "[DONE] 已删除 $rk_dir"
    else
        echo "[SKIP] $rk_dir 不存在"
    fi
done

# 补丁 10：device/rockchip（RK 专有目录）
TARGET="$ANDROID_ROOT/device/rockchip"
if [[ -d "$TARGET" ]]; then
    rm -rf "$TARGET"
    echo "[DONE] 已删除 device/rockchip"
else
    echo "[SKIP] device/rockchip 不存在"
fi

# 补丁 11：全部 frameworks（av / base / base-packages / base-services / ex / native / opt）
for _fw_patch in \
    "$REPO_DIR/Android-13/patches/rk3588-frameworks.patch"; do
    if [[ -f "$_fw_patch" ]]; then
        if git -C "$REPO_DIR" apply -R --check --unsafe-paths \
                --directory="$ANDROID_ROOT" \
                "$_fw_patch" 2>/dev/null; then
            git -C "$REPO_DIR" apply -R --reject --unsafe-paths \
                --directory="$ANDROID_ROOT" \
                "$_fw_patch" 2>/dev/null \
                || echo "[WARN] git apply -R 部分失败，请检查 .rej 文件"
            echo "[DONE] $(basename "$_fw_patch" .patch) 补丁已撤销"
        else
            echo "[SKIP] $(basename "$_fw_patch" .patch) 未应用，跳过"
        fi
    else
        echo "[SKIP] 补丁文件不存在: $_fw_patch"
    fi
done

# 删除全部 frameworks RK 专有文件/目录
for rk_path in \
    "frameworks/av/media/libstagefright/wifi-display" \
    "frameworks/base/core/java/android/os/IRKBoxManagementService.aidl" \
    "frameworks/base/core/java/android/os/IRkDisplayDeviceManagementService.aidl" \
    "frameworks/base/core/java/android/os/RkDisplayOutputManager.java" \
    "frameworks/base/core/java/android/os/audio" \
    "frameworks/base/data/etc/wakeup-alarmalign-whitelist.xml" \
    "frameworks/base/media/java/android/media/AudioStream.java" \
    "frameworks/base/services/core/java/com/android/server/rkdisplay" \
    "frameworks/base/services/core/jni/rkbox" \
    "frameworks/base/services/core/java/com/android/server/RKBoxManagementService.java" \
    "frameworks/base/services/core/java/com/android/server/RkDisplayDeviceManagementService.java" \
    "frameworks/base/services/core/java/com/android/server/audio/RkAudioSetting.java" \
    "frameworks/base/services/core/java/com/android/server/audio/RkAudioSettingService.java" \
    "frameworks/base/services/core/java/com/android/server/pm/PackagePerformanceSetting.java" \
    "frameworks/base/services/core/jni/com_android_server_RKBoxService.cpp" \
    "frameworks/base/services/core/jni/com_android_server_audio_RkAudioSetting.cpp" \
    "frameworks/base/services/core/jni/com_android_server_rkdisplay_RkDisplayModes.cpp" \
    "frameworks/native/libs/renderengine/Android.go" \
    "frameworks/native/services/inputflinger/reader/mapper/KeyMouseInputMapper.cpp" \
    "frameworks/native/services/inputflinger/reader/mapper/KeyMouseInputMapper.h" \
    "frameworks/native/services/surfaceflinger/Android.go" \
    "frameworks/native/services/surfaceflinger/CompositionEngine/Android.go" \
    "frameworks/opt/net/wifi/libwifi_hal/include/hardware_legacy/rk_wifi.h" \
    "frameworks/opt/net/wifi/libwifi_hal/rk_wifi_ctrl.cpp"; do
    TARGET="$ANDROID_ROOT/$rk_path"
    if [[ -e "$TARGET" ]]; then
        rm -rf "$TARGET"
        echo "[DONE] 已删除 $rk_path"
    else
        echo "[SKIP] $rk_path 不存在"
    fi
done
# art-profile：移除末尾 rkdisplay 4 行（截断到 rkdisplay 条目之前）
ART_PROFILE="$ANDROID_ROOT/frameworks/base/services/art-profile"
if [[ -f "$ART_PROFILE" ]] && grep -qF "Lcom/android/server/rkdisplay/RkDisplayModes;" "$ART_PROFILE"; then
    grep -v "^Lcom/android/server/rkdisplay/" "$ART_PROFILE" > "${ART_PROFILE}.tmp"
    mv "${ART_PROFILE}.tmp" "$ART_PROFILE"
    echo "[DONE] art-profile 已移除 rkdisplay ART 预编译条目"
fi

# 补丁 12：hardware（git diff 补丁 + RK 专有目录/文件）
HW_PATCH_FILE="$REPO_DIR/Android-13/patches/rk3588-hardware.patch"
if [[ -f "$HW_PATCH_FILE" ]]; then
    if git -C "$REPO_DIR" apply -R --check --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$HW_PATCH_FILE" 2>/dev/null; then
        git -C "$REPO_DIR" apply -R --reject --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$HW_PATCH_FILE" 2>/dev/null \
            || echo "[WARN] git apply -R 部分失败，请检查 .rej 文件"
        echo "[DONE] rk3588-hardware.patch 已撤销"
    else
        echo "[SKIP] rk3588-hardware.patch 未应用，跳过"
    fi
else
    echo "[SKIP] 补丁文件不存在: $HW_PATCH_FILE"
fi

# 删除 hardware RK 专有目录
for rk_path in \
    "hardware/aic" \
    "hardware/bes" \
    "hardware/realtek" \
    "hardware/rockchip" \
    "hardware/broadcom/libbt/include/vnd_rksdk.txt" \
    "hardware/interfaces/audio/core/all-versions/default/Android.go" \
    "hardware/interfaces/camera/device/3.4/default/ExternalCameraGralloc.cpp" \
    "hardware/interfaces/camera/device/3.4/default/ExternalCameraGralloc4.cpp" \
    "hardware/interfaces/camera/device/3.4/default/ExternalCameraMemManager.cpp" \
    "hardware/interfaces/camera/device/3.4/default/ExternalFakeCameraDevice.cpp" \
    "hardware/interfaces/camera/device/3.4/default/ExternalFakeCameraDeviceSession.cpp" \
    "hardware/interfaces/camera/device/3.4/default/RgaCropScale.cpp" \
    "hardware/interfaces/camera/device/3.4/default/include/ext_device_v3_4_impl/ExternalCameraDeviceSession_3.4.h" \
    "hardware/interfaces/camera/device/3.4/default/include/ext_device_v3_4_impl/ExternalCameraGralloc.h" \
    "hardware/interfaces/camera/device/3.4/default/include/ext_device_v3_4_impl/ExternalCameraGralloc4.h" \
    "hardware/interfaces/camera/device/3.4/default/include/ext_device_v3_4_impl/ExternalCameraMemManager.h" \
    "hardware/interfaces/camera/device/3.4/default/include/ext_device_v3_4_impl/ExternalCameraUtils_3.4.h" \
    "hardware/interfaces/camera/device/3.4/default/include/ext_device_v3_4_impl/ExternalFakeCameraDeviceSession_3.4.h" \
    "hardware/interfaces/camera/device/3.4/default/include/ext_device_v3_4_impl/ExternalFakeCameraDevice_3_4.h" \
    "hardware/interfaces/camera/device/3.4/default/include/ext_device_v3_4_impl/RgaCropScale.h" \
    "hardware/interfaces/camera/device/3.4/default/include/ext_device_v3_4_impl/osd.h" \
    "hardware/interfaces/camera/device/3.4/default/include/ext_device_v3_4_impl/rkvpu_dec_api.h" \
    "hardware/interfaces/camera/device/3.4/default/include/ext_device_v3_4_impl/subvideo.h" \
    "hardware/interfaces/camera/device/3.4/default/include/vpu_inc" \
    "hardware/interfaces/camera/device/3.4/default/osd.cpp" \
    "hardware/interfaces/camera/device/3.4/default/rkvpu_dec_api.cpp" \
    "hardware/interfaces/camera/device/3.4/default/subvideo.cpp" \
    "hardware/interfaces/camera/provider/2.4/default/DeviceV4L2Event.cpp" \
    "hardware/interfaces/camera/provider/2.4/default/DeviceV4L2Event.h" \
    "hardware/ril/libril/lib32" \
    "hardware/ril/libril/lib64"; do
    TARGET="$ANDROID_ROOT/$rk_path"
    if [[ -e "$TARGET" ]]; then
        rm -rf "$TARGET"
        echo "[DONE] 已删除 $rk_path"
    else
        echo "[SKIP] $rk_path 不存在"
    fi
done

# 补丁 13：system（git diff 补丁 + RK 专有文件）
SYS_PATCH_FILE="$REPO_DIR/Android-13/patches/rk3588-system.patch"
if [[ -f "$SYS_PATCH_FILE" ]]; then
    if git -C "$REPO_DIR" apply -R --check --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$SYS_PATCH_FILE" 2>/dev/null; then
        git -C "$REPO_DIR" apply -R --reject --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$SYS_PATCH_FILE" 2>/dev/null \
            || echo "[WARN] git apply -R 部分失败，请检查 .rej 文件"
        echo "[DONE] rk3588-system.patch 已撤销"
    else
        echo "[SKIP] rk3588-system.patch 未应用，跳过"
    fi
else
    echo "[SKIP] 补丁文件不存在: $SYS_PATCH_FILE"
fi

# 删除 system RK 专有文件
for rk_path in \
    "system/vold/fs/Ntfs.cpp" \
    "system/vold/fs/Ntfs.h"; do
    TARGET="$ANDROID_ROOT/$rk_path"
    if [[ -e "$TARGET" ]]; then
        rm -f "$TARGET"
        echo "[DONE] 已删除 $rk_path"
    else
        echo "[SKIP] $rk_path 不存在"
    fi
done

# ---------- 补丁 14：packages ----------
PKG_PATCH_FILE="$REPO_DIR/Android-13/patches/rk3588-packages.patch"
if [[ -f "$PKG_PATCH_FILE" ]]; then
    if git -C "$REPO_DIR" apply -R --check --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$PKG_PATCH_FILE" 2>/dev/null; then
        git -C "$REPO_DIR" apply -R --reject --unsafe-paths \
            --directory="$ANDROID_ROOT" \
            "$PKG_PATCH_FILE" 2>/dev/null \
            || echo "[WARN] git apply -R 部分失败，请检查 .rej 文件"
        echo "[DONE] rk3588-packages.patch 已撤销"
    else
        echo "[SKIP] rk3588-packages.patch 未应用，跳过"
    fi
else
    echo "[SKIP] 补丁文件不存在: $PKG_PATCH_FILE"
fi

# 删除 packages RK-only app
for rk_path in \
    "packages/apps/DisplayAdjust" \
    "packages/apps/ExactCalculator" \
    "packages/apps/SoundRecorder" \
    "packages/apps/rkCamera2"; do
    TARGET="$ANDROID_ROOT/$rk_path"
    if [[ -e "$TARGET" ]]; then
        rm -rf "$TARGET"
        echo "[DONE] 已删除 $rk_path"
    else
        echo "[SKIP] $rk_path 不存在"
    fi
done
echo "[INFO] packages 中各现有 app 的 RK 专有资源文件（Camera2/TvSettings 等图片）已由 patch -R 还原修改部分"
echo "[INFO] 如需完全还原纯新增文件，请在各子目录执行 git checkout -- ."

# ---------- 补丁 15：vendor（整个 vendor/ 目录为 RK-only，直接删除即可） ----------
echo "  删除 vendor/ RK 专有目录..."
for rk_path in \
    "vendor/widevine" \
    "vendor/rockchip/hardware" \
    "vendor/rockchip/common/gpu/MaliG610" \
    "vendor/rockchip/common/gpu/Android.mk" \
    "vendor/rockchip/common/gpu/MaliG610.mk" \
    "vendor/rockchip/common/gpu/libs" \
    "vendor/rockchip/common/apps" \
    "vendor/rockchip/common/eptz" \
    "vendor/rockchip/common/vpu" \
    "vendor/rockchip/common/wifi" \
    "vendor/rockchip/common/bin" \
    "vendor/rockchip/common/bluetooth" \
    "vendor/rockchip/common/copybit" \
    "vendor/rockchip/common/data_clone" \
    "vendor/rockchip/common/etc" \
    "vendor/rockchip/common/ethernet" \
    "vendor/rockchip/common/fec" \
    "vendor/rockchip/common/gms" \
    "vendor/rockchip/common/gps" \
    "vendor/rockchip/common/hdcp2" \
    "vendor/rockchip/common/ipp" \
    "vendor/rockchip/common/modular_kernel" \
    "vendor/rockchip/common/nand" \
    "vendor/rockchip/common/phone" \
    "vendor/rockchip/common/pluginsvc" \
    "vendor/rockchip/common/pppoe" \
    "vendor/rockchip/common/rftesttool" \
    "vendor/rockchip/common/samba" \
    "vendor/rockchip/common/webkit" \
    "vendor/rockchip/common/BoardConfigVendor.mk" \
    "vendor/rockchip/common/device-vendor.mk" \
    "vendor/rockchip/common/gms-express.xml"; do
    TARGET="$ANDROID_ROOT/$rk_path"
    if [[ -e "$TARGET" ]]; then
        rm -rf "$TARGET"
        echo "[DONE] 已删除 $rk_path"
    else
        echo "[SKIP] $rk_path 不存在"
    fi
done
# 清理可能变空的父目录
for empty_dir in \
    "vendor/rockchip/common/gpu" \
    "vendor/rockchip/common" \
    "vendor/rockchip" \
    "vendor"; do
    TARGET="$ANDROID_ROOT/$empty_dir"
    if [[ -d "$TARGET" ]] && [[ -z "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
        rmdir "$TARGET"
        echo "[DONE] 已移除空目录 $empty_dir"
    fi
done

echo ""
echo "========================================"
echo " 清理完成"
echo "========================================"
