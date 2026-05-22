#!/bin/bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- 日志工具 ----------
_R='\033[0;31m'  # red
_G='\033[0;32m'  # green
_Y='\033[0;33m'  # yellow
_B='\033[0;34m'  # blue
_C='\033[0;36m'  # cyan
_W='\033[1;37m'  # bold white
_N='\033[0m'     # reset

log_info()    { echo -e "${_C}  ℹ  ${_N}$*"; }
log_ok()      { echo -e "${_G}  ✓  ${_N}$*"; }
log_warn()    { echo -e "${_Y}  ⚠  ${_N}$*"; }
log_error()   { echo -e "${_R}  ✗  ${_N}$*" >&2; }
log_step()    { echo -e "${_W}  ▶  ${_N}$*"; }
log_banner()  {
    echo -e "${_B}════════════════════════════════════════${_N}"
    echo -e "${_W}  $*${_N}"
    echo -e "${_B}════════════════════════════════════════${_N}"
}

# 执行命令并检测结果，失败时打印错误信息后退出
run_cmd() {
    local desc="$1"; shift
    log_info "${desc}"
    if "$@"; then
        log_ok "${desc} 完成"
    else
        log_error "${desc} 失败（exit $?）"
        exit 1
    fi
}

# ---------- 参数解析 ----------
usage() {
    cat <<EOF
用法: $(basename "$0") <-U | -K> [-c] [-h]

选项:
  -U    编译 U-Boot（含 SPL 三步打包流程）
  -K    编译内核 (kernel-5.10)
  -c    全量编译（编译前先 make clean，清除全部中间产物）
  -h    显示此帮助信息

示例:
  $(basename "$0") -U          # 增量编译 U-Boot
  $(basename "$0") -K          # 增量编译内核
  $(basename "$0") -K -c       # 全量重编内核
  $(basename "$0") -U -c       # 全量重编 U-Boot
EOF
}

BUILD_UBOOT=0
BUILD_KERNEL=0
BUILD_CLEAN=0

if [[ $# -eq 0 ]]; then
    log_error "需要至少一个选项"
    usage
    exit 1
fi

while getopts ":UKch" opt; do
    case $opt in
        U) BUILD_UBOOT=1 ;;
        K) BUILD_KERNEL=1 ;;
        c) BUILD_CLEAN=1 ;;
        h) usage; exit 0 ;;
        \?) log_error "未知选项 -${OPTARG}"; usage; exit 1 ;;
    esac
done

if [[ $BUILD_UBOOT -eq 0 && $BUILD_KERNEL -eq 0 ]]; then
    log_error "请指定 -U 或 -K 编译目标"
    usage
    exit 1
fi

# ---------- 初始化编译环境 ----------
# 注意：不能使用 set -u（nounset）。build/envsetup.sh 定义了大量 shell 函数，
# 这些函数在后续 make 阶段被调用时会引用 USE_RBE、TOP、ZSH_VERSION 等无默认值的
# 变量，set -u 会在调用时触发 unbound variable 报错，与整个 Android 构建环境不兼容。

# build.sh 由 apply-patches.sh 复制到 Android 工程根目录，SCRIPT_DIR 即为工程根。
ANDROID_ROOT="$SCRIPT_DIR"

log_banner "初始化编译环境"

# 验证当前目录是否为 Android 工程根（以 build/envsetup.sh 是否存在为判断依据）
if [[ ! -f "$ANDROID_ROOT/build/envsetup.sh" ]]; then
    log_error "未找到 build/envsetup.sh，请确认 build.sh 已由 apply-patches.sh 放置在 Android 13 工程根目录"
    log_error "当前路径: $ANDROID_ROOT"
    exit 1
fi
log_ok "Android 工程根目录: $ANDROID_ROOT"

# ---- 1. 环境检查 ----
log_step "[1/3] 检查编译环境..."

# -- 操作系统 --
if [[ -f /etc/os-release ]]; then
    OS_ID=$(. /etc/os-release && echo "$ID")
    OS_VER=$(. /etc/os-release && echo "$VERSION_ID")
    if [[ "$OS_ID" == "ubuntu" ]]; then
        log_info "操作系统: Ubuntu ${OS_VER}"
        if [[ "$OS_VER" != "20.04" && "$OS_VER" != "18.04" ]]; then
            log_warn "Android 13 官方支持 Ubuntu 18.04/20.04，当前 ${OS_VER} 可能遇到兼容问题"
        fi
    else
        log_warn "当前系统: ${OS_ID} ${OS_VER}，Android 13 推荐在 Ubuntu 20.04 上构建"
    fi
fi

# -- JDK 11（Android 13 强依赖，版本不对会导致 javac/kotlinc 编译失败）--
if command -v java &>/dev/null; then
    JAVA_VER=$(java -version 2>&1 | awk -F'"' 'NR==1{split($2,a,"."); print (a[1]=="1"?a[2]:a[1])}')
    JAVA_INFO=$(java -version 2>&1 | head -1)
    if [[ "$JAVA_VER" != "11" ]]; then
        log_warn "当前 Java 版本: ${JAVA_VER:-未知}，Android 13 需要 JDK 11，尝试切换..."
        export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
        export PATH=$JAVA_HOME/bin:$PATH
        if command -v java &>/dev/null; then
            JAVA_INFO=$(java -version 2>&1 | head -1)
            log_ok "已切换到 JDK 11: ${JAVA_INFO}"
        else
            log_error "JDK 11 未找到，请手动安装: sudo apt install openjdk-11-jdk"
            exit 1
        fi
    else
        log_info "JDK: ${JAVA_INFO}"
    fi
else
    log_error "未检测到 Java，Android 13 需要 JDK 11，请安装: sudo apt install openjdk-11-jdk"
    exit 1
fi

# -- Python 3（构建脚本依赖）--
if command -v python3 &>/dev/null; then
    log_info "Python: $(python3 --version 2>&1)"
else
    log_error "未找到 python3，请安装: sudo apt install python3"
    exit 1
fi

# -- GNU Make --
if command -v make &>/dev/null; then
    log_info "Make: $(make --version | head -1)"
else
    log_error "未找到 make，请安装: sudo apt install build-essential"
    exit 1
fi

# -- Git --
if command -v git &>/dev/null; then
    log_info "Git: $(git --version)"
else
    log_error "未找到 git，请安装: sudo apt install git"
    exit 1
fi

# -- curl --
if command -v curl &>/dev/null; then
    log_info "curl: $(curl --version | head -1)"
else
    log_warn "未找到 curl（部分步骤可能需要）: sudo apt install curl"
fi

# -- clang（内核编译依赖 AOSP 预编译 clang-r450784d）--
# Android 13 内核强制使用 clang 编译器，版本由 AOSP 13 源码树预置于 prebuilts/clang/
CLANG_VERSION="clang-r450784d"
CLANG_BIN="$ANDROID_ROOT/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin"
if [[ -d "$CLANG_BIN" ]]; then
    log_info "clang: $("$CLANG_BIN/clang" --version | head -1)"
else
    log_warn "未找到 AOSP 预编译 clang (${CLANG_VERSION})，内核编译将不可用"
    log_warn "期望路径: $CLANG_BIN"
fi

# -- 物理内存 --
# 官方 AOSP 要求：最少 64 GB RAM（source.android.com/docs/setup/start/requirements）
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
if [[ $TOTAL_RAM_GB -lt 32 ]]; then
    log_warn "物理内存: ${TOTAL_RAM_GB}GB，AOSP 官方要求最少 64GB，当前配置整编可能 OOM 或极慢"
elif [[ $TOTAL_RAM_GB -lt 64 ]]; then
    log_warn "物理内存: ${TOTAL_RAM_GB}GB（AOSP 官方要求 64GB，当前可能影响并行编译速度）"
else
    log_info "物理内存: ${TOTAL_RAM_GB}GB"
fi

# -- CPU 核心数 --
CPU_CORES=$(nproc)
log_info "CPU 核心: ${CPU_CORES} 核（make 并行度参考）"

# -- 磁盘空间 --
# 官方 AOSP 要求：400 GB（250 GB 源码 + 150 GB 构建产物）
AVAIL_GB=$(df -BG "$ANDROID_ROOT" 2>/dev/null | awk 'NR==2{gsub("G",""); print $4}') || AVAIL_GB=0
if [[ "$AVAIL_GB" -lt 200 ]]; then
    log_warn "可用磁盘: ${AVAIL_GB}GB（AOSP 官方要求 400GB，当前空间可能不足以完成整编）"
elif [[ "$AVAIL_GB" -lt 400 ]]; then
    log_warn "可用磁盘: ${AVAIL_GB}GB（AOSP 官方推荐 400GB，建议扩容后再整编）"
else
    log_info "可用磁盘: ${AVAIL_GB}GB"
fi

log_ok "环境检查通过"

# ---- 2. 源码 patch ----
log_step "[2/3] 应用源码修复..."

cd "$ANDROID_ROOT"

# Fix #1: car emulator sepolicy 引用了 goldfish 专用类型（qemu_device 等），
#   aosp_car_arm64 不含 goldfish sepolicy，导致 checkpolicy 报 unknown type。
#   注释掉相关行，对真机无影响（该模块不在真机上运行）。
SEPOLICY_FILE="device/generic/car/emulator/usbpt/bluetooth/btusb/sepolicy/domain.te"
if [[ -f "$SEPOLICY_FILE" ]]; then
    sed -i \
        -e 's/^allow domain qemu_device/# [FIXED] allow domain qemu_device/' \
        -e 's/^get_prop(domain, vendor_qemu_prop)/# [FIXED] get_prop(domain, vendor_qemu_prop)/' \
        -e 's/^get_prop(domain, vendor_build_prop)/# [FIXED] get_prop(domain, vendor_build_prop)/' \
        "$SEPOLICY_FILE"
    log_ok "已修复 $SEPOLICY_FILE"
else
    log_info "跳过 $SEPOLICY_FILE（文件不存在）"
fi

PROP_CTX_FILE="device/generic/car/emulator/usbpt/bluetooth/btusb/sepolicy/property_contexts"
if [[ -f "$PROP_CTX_FILE" ]]; then
    sed -i 's/^[^#].*vendor_qemu_prop.*$/# [FIXED] &/' "$PROP_CTX_FILE"
    log_ok "已修复 $PROP_CTX_FILE"
else
    log_info "跳过 $PROP_CTX_FILE（文件不存在）"
fi

# ---- 3. 加载编译工具链 ----
log_step "[3/3] 加载 Android 编译工具链（envsetup + lunch）..."

source build/envsetup.sh

# 选择编译目标：
#   aosp_car_arm64  - ARM64 架构的通用 AOSP Car target，适合 RK3588 等真机移植起点
#   userdebug       - 保留 root 权限和调试能力，移植开发阶段使用
lunch aosp_car_arm64-userdebug || { log_error "lunch 失败"; exit 1; }

log_ok "编译环境初始化完成"
cd "$SCRIPT_DIR"

# ---------- 编译 U-Boot ----------
if [[ $BUILD_UBOOT -eq 1 ]]; then
    log_banner "编译 U-Boot"
    # 三步流程确保 SPL 来自本地源码而非 rkbin 预编译版本，详见 README.md

    if [[ ! -d "$SCRIPT_DIR/u-boot" ]]; then
        log_error "未找到 u-boot 目录: $SCRIPT_DIR/u-boot"
        log_error "请先通过 apply-patches.sh 将 u-boot 复制到 Android 工程根目录"
        exit 1
    fi

    cd "$SCRIPT_DIR/u-boot"

    if [[ $BUILD_CLEAN -eq 1 ]]; then
        log_step "[0/3] 全量清理旧产物..."
        run_cmd "make clean"     make clean
        run_cmd "make mrproper"  make mrproper
        run_cmd "make distclean" make distclean
    else
        log_info "增量模式，跳过 clean（-c 可全量重编）"
    fi

    log_step "[1/3] 首次编译，生成 spl/u-boot-spl.bin ..."
    run_cmd "./make.sh V-gatron（第 1 次）" ./make.sh V-gatron

    log_step "[2/3] 替换 rkbin 预编译 SPL ..."
    if [[ ! -f "spl/u-boot-spl.bin" ]]; then
        log_error "spl/u-boot-spl.bin 不存在，第 1 步编译可能失败"
        exit 1
    fi
    if [[ ! -d "$SCRIPT_DIR/rkbin" ]]; then
        log_error "未找到 rkbin 目录: $SCRIPT_DIR/rkbin"
        log_error "请先通过 apply-patches.sh 将 rkbin 复制到 Android 工程根目录"
        exit 1
    fi
    run_cmd "复制 SPL → rkbin" \
        cp spl/u-boot-spl.bin "$SCRIPT_DIR/rkbin/bin/rk35/rk3588_spl_v1.13.bin"

    log_step "[3/3] 重新编译打包，嵌入自编 SPL ..."
    if [[ $BUILD_CLEAN -eq 1 ]]; then
        run_cmd "make clean"     make clean
        run_cmd "make mrproper"  make mrproper
        run_cmd "make distclean" make distclean
    fi
    run_cmd "./make.sh V-gatron（第 2 次）" ./make.sh V-gatron

    cd "$SCRIPT_DIR"
    log_banner "U-Boot 编译完成 ✓"
fi

# ---------- 编译内核 ----------
if [[ $BUILD_KERNEL -eq 1 ]]; then
    # ---- 内核编译参数 ----
    # TODO: 以下参数硬编码为 ATK_DLRK3588 目标值，待 device 目录移植完成后
    #       通过 get_build_var 从 BoardConfig.mk 动态读取。

    # device/rockchip/rk3588/BoardConfig.mk:50  PRODUCT_KERNEL_VERSION := 5.10
    KERNEL_VERSION="5.10"

    # device/rockchip/rk3588/BoardConfig.mk:22  PRODUCT_KERNEL_ARCH ?= arm64
    KERNEL_ARCH="arm64"

    # device/rockchip/rk3588/ATK_DLRK3588/BoardConfig.mk:37
    # PRODUCT_KERNEL_CONFIG := V-gatron_defconfig
    KERNEL_DEFCONFIG="V-gatron_defconfig"

    # device/rockchip/rk3588/ATK_DLRK3588/BoardConfig.mk:32
    # PRODUCT_KERNEL_DTS := rk3588-v-gatron
    KERNEL_DTS="rk3588-v-gatron"

    KERNEL_SRC="$SCRIPT_DIR/kernel-${KERNEL_VERSION}"
    LOCAL_KERNEL_PATH="$KERNEL_SRC"

    # clang 版本（与 kernel-5.10/build.config.constants: CLANG_VERSION=r450784d 一致）
    KERNEL_CLANG_VER="r450784d"
    KERNEL_CLANG_BIN="$ANDROID_ROOT/prebuilts/clang/host/linux-x86/clang-${KERNEL_CLANG_VER}/bin"

    # LLVM=1 LLVM_IAS=1：使用 clang/lld 替代 gcc/binutils（依赖 [1/4] 设置的 PATH）
    ADDON_ARGS="CROSS_COMPILE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1"

    # 并行编译 job 数（复用环境检查阶段已探测的 CPU_CORES）
    BUILD_JOBS="${CPU_CORES}"

    log_banner "编译内核 (kernel-${KERNEL_VERSION})"

    if [[ ! -d "$KERNEL_SRC" ]]; then
        log_error "未找到 kernel-${KERNEL_VERSION} 目录: $KERNEL_SRC"
        log_error "请先通过 apply-patches.sh 将 kernel-${KERNEL_VERSION} 复制到 Android 工程根目录"
        exit 1
    fi
    if [[ ! -d "$KERNEL_CLANG_BIN" ]]; then
        log_error "未找到 clang-${KERNEL_CLANG_VER}: $KERNEL_CLANG_BIN"
        exit 1
    fi
    log_ok "kernel 源码目录: $KERNEL_SRC"

    log_info "KERNEL_VERSION   = $KERNEL_VERSION"
    log_info "KERNEL_ARCH      = $KERNEL_ARCH"
    log_info "KERNEL_DEFCONFIG = $KERNEL_DEFCONFIG"
    log_info "KERNEL_DTS       = $KERNEL_DTS"
    log_info "LOCAL_KERNEL_PATH= $LOCAL_KERNEL_PATH"
    log_info "KERNEL_CLANG_VER = $KERNEL_CLANG_VER"
    log_info "ADDON_ARGS       = $ADDON_ARGS"
    log_info "BUILD_JOBS       = $BUILD_JOBS"

    cd "$KERNEL_SRC"

    # .scmversion 由 apply-patches.sh 写入（含 git short hash），作为内核版本后缀
    if [[ -f .scmversion ]]; then
        log_info "内核版本后缀 (.scmversion): \"$(cat .scmversion)\""
    else
        log_warn ".scmversion 不存在，make 阶段可能出现 git 警告，建议重新运行 apply-patches.sh"
    fi

    # ---- [1/4] 将 clang 加入 PATH（LLVM=1 前提）----
    export PATH="${KERNEL_CLANG_BIN}:${PATH}"
    if ! clang --version &>/dev/null; then
        log_error "clang 不可用，PATH 设置可能失败: $KERNEL_CLANG_BIN"
        exit 1
    fi
    log_ok "clang PATH 已设置: $(clang --version | head -1)"

    # ---- [0/4] 全量清理（仅 -c 模式）----
    if [[ $BUILD_CLEAN -eq 1 ]]; then
        log_step "[0/4] 全量清理内核旧产物..."
        run_cmd "make clean" make $ADDON_ARGS ARCH="${KERNEL_ARCH}" clean
    fi

    # ---- [2/3] 内核编译（defconfig → Image + 主 DTB + resource.img）----

    log_step "[2/3] 内核编译（defconfig → Image）..."
    run_cmd "make defconfig (${KERNEL_DEFCONFIG})" \
        make $ADDON_ARGS ARCH="${KERNEL_ARCH}" ${KERNEL_DEFCONFIG}
    run_cmd "make ${KERNEL_DTS}.img" \
        make $ADDON_ARGS ARCH="${KERNEL_ARCH}" "${KERNEL_DTS}.img" -j"${BUILD_JOBS}"

    # TODO [B]: 外部 wifi/BT driver（.ko），整编时由 Android 构建系统处理，待 external/wifi_driver/ 就绪后启用
    log_warn "TODO [B] 外部 wifi driver：external/wifi_driver/ 不存在，跳过"

    # ---- [3/3] 复制 kernel Image → $OUT/kernel ----
    # make bootimage 从 $OUT/kernel 取镜像，整编不会重编内核源码，须手动放置
    log_step "[3/3] 复制 kernel Image → \$OUT/kernel..."
    if [[ -z "${OUT:-}" ]]; then
        log_warn "[3/3] \$OUT 未设置，跳过（lunch 环境变量丢失，请重新 source build/envsetup.sh && lunch）"
    else
        mkdir -p "$OUT"
        run_cmd "cp Image → \$OUT/kernel" \
            cp -f "${KERNEL_SRC}/arch/arm64/boot/Image" "${OUT}/kernel"
        log_info "已放置: ${OUT}/kernel（make bootimage 从此路径取 Image）"
    fi

    # ---- [临时] 合成可刷写 boot.img（factory-ramdisk + 新内核 + resource.img）----
    # 整编 Android 完成前的临时刷机验证方案，替代 TODO [E] make bootimage。
    # factory-ramdisk 提取自工厂 boot.img（header v2），随仓库提交。
    # mkbootimg 参数由 unpack_bootimg.py 解包工厂镜像获得：
    #   pagesize=2048  kernel_offset=0x10008000  ramdisk_offset=0x11000000
    #   second_offset=0x10f00000  tags_offset=0x10000100  dtb_offset=0x11f00000
    FACTORY_RAMDISK="${KERNEL_SRC}/factory-ramdisk"
    MKBOOTIMG_PY="${ANDROID_ROOT}/system/tools/mkbootimg/mkbootimg.py"
    BOOT_IMG_OUT="${KERNEL_SRC}/boot.img"

    if [[ ! -f "${FACTORY_RAMDISK}" ]]; then
        log_warn "[临时] 未找到预提取的工厂 ramdisk: ${FACTORY_RAMDISK}，跳过 boot.img 合成"
        log_warn "       请从工厂 boot.img 提取: unpack_bootimg.py --boot_img boot(hdmi0_8k).img --out <dir>"
        log_warn "       然后将解包目录中的 ramdisk 复制到 rk-kernel-5.10/factory-ramdisk"
    elif [[ ! -f "${MKBOOTIMG_PY}" ]]; then
        log_warn "[临时] 未找到 mkbootimg.py: ${MKBOOTIMG_PY}，跳过 boot.img 合成"
    else
        log_step "[临时] 合成 boot.img（factory-ramdisk + 新内核）..."

        run_cmd "mkbootimg 合成 boot.img" \
            python3 "${MKBOOTIMG_PY}" \
                --header_version 2 \
                --os_version     "13.0.0" \
                --os_patch_level "2023-08" \
                --kernel  "${KERNEL_SRC}/arch/arm64/boot/Image" \
                --ramdisk "${FACTORY_RAMDISK}" \
                --second  "${KERNEL_SRC}/resource.img" \
                --dtb     "${KERNEL_SRC}/arch/arm64/boot/dts/rockchip/${KERNEL_DTS}.dtb" \
                --pagesize 2048 \
                --base            0x00000000 \
                --kernel_offset   0x10008000 \
                --ramdisk_offset  0x11000000 \
                --second_offset   0x10f00000 \
                --tags_offset     0x10000100 \
                --dtb_offset      0x0000000011f00000 \
                --cmdline 'console=ttyFIQ0 firmware_class.path=/vendor/etc/firmware init=/init rootwait ro loop.max_part=7 androidboot.console=ttyFIQ0 androidboot.wificountrycode=CN androidboot.hardware=rk30board androidboot.boot_devices=fe2e0000.mmc androidboot.selinux=permissive buildvariant=userdebug' \
                --output "${BOOT_IMG_OUT}"

        log_ok "boot.img 合成完成: ${BOOT_IMG_OUT}"
        log_info "刷入命令: fastboot flash boot ${BOOT_IMG_OUT}"
    fi

    # TODO [E]: make bootimage / recoveryimage，依赖整编 Android，待 device 目录移植完成后实现
    log_warn "TODO [E] make bootimage/recoveryimage：待 device 目录移植完成后实现"

    cd "$SCRIPT_DIR"
    log_banner "内核编译完成 ✓"
fi

# ---------- 收集产物到 Image 目录 ----------
log_banner "收集编译产物"

IMAGE_DIR="$SCRIPT_DIR/Image"
COLLECTED=0

if [[ -d "$IMAGE_DIR" ]]; then
    log_info "清空已有目录: $IMAGE_DIR"
    rm -rf "${IMAGE_DIR:?}"/*
else
    log_info "创建目录: $IMAGE_DIR"
    mkdir -p "$IMAGE_DIR" || { log_error "创建 $IMAGE_DIR 失败"; exit 1; }
fi

# 复制 U-Boot 产物（仅 -U 编译时检查）
if [[ $BUILD_UBOOT -eq 1 ]]; then
    SPL_LOADER="$SCRIPT_DIR/u-boot/rk3588_spl_loader_v1.19.113.bin"
    UBOOT_IMG="$SCRIPT_DIR/u-boot/uboot.img"
    if [[ ! -f "$SPL_LOADER" ]]; then
        log_error "未找到 SPL Loader: $SPL_LOADER"
        log_error "请先使用 -U 编译 U-Boot"
        exit 1
    fi
    if [[ ! -f "$UBOOT_IMG" ]]; then
        log_error "未找到 uboot.img: $UBOOT_IMG"
        log_error "请先使用 -U 编译 U-Boot"
        exit 1
    fi
    run_cmd "复制 rk3588_spl_loader_v1.19.113.bin" cp "$SPL_LOADER" "$IMAGE_DIR/"
    run_cmd "复制 uboot.img"                       cp "$UBOOT_IMG"  "$IMAGE_DIR/"
    COLLECTED=$((COLLECTED + 1))
fi

# 复制内核产物（仅 -K 编译时）
if [[ $BUILD_KERNEL -eq 1 ]]; then
    # boot.img（[临时]步骤合成，可 fastboot flash boot 刷入验证）
    KERNEL_BOOT_IMG="${KERNEL_SRC}/boot.img"
    if [[ -f "$KERNEL_BOOT_IMG" ]]; then
        run_cmd "复制 boot.img" cp "$KERNEL_BOOT_IMG" "$IMAGE_DIR/"
        COLLECTED=$((COLLECTED + 1))
    else
        log_warn "boot.img 未生成（[临时]步骤已跳过），Image/ 中无 boot.img"
    fi

    # resource.img 已通过 mkbootimg --second 内嵌在 boot.img 中，无需单独收集。

    # parameter.txt：eMMC 分区表（RKDevTool 整包烧录需要），来自工厂镜像
    # 待整编完成后由 device/rockchip/rk3588/ATK_DLRK3588/parameter.txt 替代
    FACTORY_PARAM="${HOME}/Factory-Image/parameter.txt"
    if [[ -f "$FACTORY_PARAM" ]]; then
        run_cmd "复制 parameter.txt（ATK_DLRK3588 分区表）" cp "$FACTORY_PARAM" "$IMAGE_DIR/"
    else
        log_warn "未找到 parameter.txt: $FACTORY_PARAM（RKDevTool 整包烧录时需要）"
    fi
fi

if [[ $COLLECTED -eq 0 ]]; then
    log_warn "无核心产物被收集（U-Boot / boot.img 均未生成）"
fi
log_ok "产物目录: $IMAGE_DIR"
log_info "$(ls -lh "$IMAGE_DIR" 2>/dev/null || echo '（空）')"
log_banner "全部完成 ✓"
