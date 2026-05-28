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
    echo -e "${_B}════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${_N}"
    echo -e "${_W}  $*${_N}"
    echo -e "${_B}════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${_N}"
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
用法: $(basename "$0") <--all | -U | -K | -A> [-c] [-h]

选项:
  --all 全流程编译（U-Boot → 内核 → Android）并自动整理分区镜像
  -U    编译 U-Boot（含 SPL 三步打包流程）
  -K    编译内核 (kernel-5.10)
  -A    整编 Android（make installclean + make -j）
  -c    全量编译（编译前先 make clean，清除全部中间产物）
        仅可与 --all 或各子目标单独使用
  -h    显示此帮助信息

示例:
  $(basename "$0") --all       # 全流程：U-Boot + 内核 + Android + mkimage
  $(basename "$0") --all -c    # 全流程全量重编
  $(basename "$0") -U          # 仅编译 U-Boot（增量）
  $(basename "$0") -K          # 仅编译内核（增量）
  $(basename "$0") -A          # 仅整编 Android
  $(basename "$0") -K -c       # 全量重编内核
  $(basename "$0") -U -c       # 全量重编 U-Boot
EOF
}

BUILD_UBOOT=0
BUILD_KERNEL=0
BUILD_ANDROID=0
BUILD_CLEAN=0
BUILD_ALL=0

if [[ $# -eq 0 ]]; then
    log_error "需要至少一个选项"
    usage
    exit 1
fi

# --all 是长选项，getopts 不支持，先单独扫描
_extra_args=()
for _a in "$@"; do
    if [[ "$_a" == "--all" ]]; then
        BUILD_ALL=1
    else
        _extra_args+=("$_a")
    fi
done

if [[ $BUILD_ALL -eq 1 ]]; then
    # --all 模式：等价于 -U -K -A；只允许额外附加 -c
    BUILD_UBOOT=1
    BUILD_KERNEL=1
    BUILD_ANDROID=1
    for _a in "${_extra_args[@]}"; do
        case "$_a" in
            -c) BUILD_CLEAN=1 ;;
            -h) usage; exit 0 ;;
            *)  log_error "--all 模式下只允许附加 -c，不支持: $_a"
                usage; exit 1 ;;
        esac
    done
else
    # 普通短选项解析
    while getopts ":UKAch" opt; do
        case $opt in
            U) BUILD_UBOOT=1 ;;
            K) BUILD_KERNEL=1 ;;
            A) BUILD_ANDROID=1 ;;
            c) BUILD_CLEAN=1 ;;
            h) usage; exit 0 ;;
            \?) log_error "未知选项 -${OPTARG}"; usage; exit 1 ;;
        esac
    done

    if [[ $BUILD_UBOOT -eq 0 && $BUILD_KERNEL -eq 0 && $BUILD_ANDROID -eq 0 ]]; then
        log_error "请指定 --all、-U、-K 或 -A 编译目标"
        usage
        exit 1
    fi
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
    log_error "未找到 curl（部分步骤可能需要）: sudo apt install curl"
    exit 1
fi

# -- clang（内核编译依赖 AOSP 预编译 clang-r450784d）--
# Android 13 内核强制使用 clang 编译器，版本由 AOSP 13 源码树预置于 prebuilts/clang/
CLANG_VERSION="clang-r450784d"
CLANG_BIN="$ANDROID_ROOT/prebuilts/clang/host/linux-x86/${CLANG_VERSION}/bin"
if [[ -d "$CLANG_BIN" ]]; then
    log_info "clang: $("$CLANG_BIN/clang" --version | head -1)"
else
    log_error "未找到 AOSP 预编译 clang (${CLANG_VERSION})，内核编译将不可用"
    log_error "期望路径: $CLANG_BIN"
    exit 1
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

# Fix #2: genrule 依赖 .git/HEAD 生成版本号头文件，但这三个目录从 tar 包解压，
#   没有 .git/，Soong 解析 Android.bp 时报"module source path does not exist"。
#   注意：~/Android-13 是 repo 工作区，git init 在未注册的子目录里会被 repo 的
#   git 配置拦截。改用直接写 .git/HEAD 文件（fake），满足 Soong 文件存在检查。
#   version.sh 里的 git log 命令在没有 git 历史时会返回空，脚本均有容错处理。
_ensure_git_head() {
    local dir="$1"
    local label="$2"
    if [[ ! -d "$dir" ]]; then
        log_info "跳过 ${label}（目录不存在）"
        return
    fi
    # repo sync 留下的 .git symlink 指向 .repo/projects/... 但该路径不存在 → 悬空 symlink
    # mkdir -p 遇到 symlink 会报 "File exists"，需先删掉再建真正的目录
    if [[ -L "$dir/.git" && ! -e "$dir/.git" ]]; then
        log_info "${label}: 检测到悬空 .git symlink，移除..."
        rm "$dir/.git"
    fi
    if [[ -f "$dir/.git/HEAD" ]]; then
        log_info "${label}: .git/HEAD 已存在，跳过"
        return
    fi
    log_step "${label}: 创建 fake .git/HEAD（满足 genrule 文件依赖）..."
    mkdir -p "$dir/.git/refs/heads"
    echo "ref: refs/heads/main" > "$dir/.git/HEAD"
    log_ok "${label}: .git/HEAD 创建完成（版本字段将显示 build-time，无功能影响）"
}

_ensure_git_head "$ANDROID_ROOT/hardware/rockchip/libmpimmz"                    "libmpimmz"
_ensure_git_head "$ANDROID_ROOT/vendor/rockchip/hardware/interfaces/codec2"      "codec2"
_ensure_git_head "$ANDROID_ROOT/hardware/rockchip/libhwjpeg"                    "libhwjpeg"

# Fix #3: hardware/rockchip/wifi/wifi_hal/vendor/qcom/Android.mk 在
#   TARGET_BOARD_PLATFORM_PRODUCT=car 时把 LOCAL_PATH 指向
#   hardware/qcom/wlan/qcwcn/wifi_hal（AOSP 13 该路径已移至 legacy/ 子目录），
#   导致 libwifi-hal-ctrl 的源文件 wifi_hal_ctrl/wifi_hal_ctrl.c 找不到。
#   用 sed 原地将路径修正为 hardware/qcom/wlan/legacy/qcwcn/wifi_hal。
_QCOM_WIFI_MK="$ANDROID_ROOT/hardware/rockchip/wifi/wifi_hal/vendor/qcom/Android.mk"
if [[ -f "$_QCOM_WIFI_MK" ]]; then
    if grep -q "hardware/qcom/wlan/qcwcn/wifi_hal" "$_QCOM_WIFI_MK"; then
        sed -i 's|LOCAL_PATH := hardware/qcom/wlan/qcwcn/wifi_hal|LOCAL_PATH := hardware/qcom/wlan/legacy/qcwcn/wifi_hal|g' \
            "$_QCOM_WIFI_MK"
        log_ok "已修复 $_QCOM_WIFI_MK（qcwcn → legacy/qcwcn）"
    else
        log_info "跳过 $_QCOM_WIFI_MK（路径已正确或文件内容已变更）"
    fi
else
    log_info "跳过 $_QCOM_WIFI_MK（文件不存在）"
fi

# Fix #4: device/rockchip/common/device.mk 的 launcher 选择分支缺少 car 产品分支，
#   导致 TARGET_BOARD_PLATFORM_PRODUCT=car 时落入 else（普通平板）分支，
#   将 Launcher3QuickStep（手机版 launcher）打包进去。
#   Launcher3QuickStep 在无 GMS 的 AAOS 环境下启动时，因 search_container_workspace
#   布局中的 SearchFragment 找不到搜索服务而崩溃，导致桌面反复重启。
#   修复：在 else 前插入 car 分支，继承 full_base.mk 但跳过 Launcher3QuickStep。
#   CarLauncher 由 V_gatron_car.mk 中 include car.mk 引入。
_DEVICE_MK="$ANDROID_ROOT/device/rockchip/common/device.mk"
if [[ -f "$_DEVICE_MK" ]]; then
    if grep -q "TARGET_BOARD_PLATFORM_PRODUCT.*car" "$_DEVICE_MK"; then
        log_info "跳过 $_DEVICE_MK（car 分支已存在）"
    elif grep -q "Normal tablet, add QuickStep" "$_DEVICE_MK"; then
        python3 - <<'PYEOF'
import sys
with open('device/rockchip/common/device.mk', 'r') as f:
    content = f.read()

old = '''else
# Normal tablet, add QuickStep for normal product only.
  $(call inherit-product, $(SRC_TARGET_DIR)/product/full_base.mk)
  PRODUCT_PACKAGES += Launcher3QuickStep'''

new = '''else ifeq ($(strip $(TARGET_BOARD_PLATFORM_PRODUCT)), car)
  # For AAOS car products - CarLauncher is included via car.mk in V_gatron_car.mk
  # Skip Launcher3QuickStep to avoid QuickstepLauncher crash on GMS-free AAOS builds
  $(call inherit-product, $(SRC_TARGET_DIR)/product/full_base.mk)
else
# Normal tablet, add QuickStep for normal product only.
  $(call inherit-product, $(SRC_TARGET_DIR)/product/full_base.mk)
  PRODUCT_PACKAGES += Launcher3QuickStep'''

if old in content:
    content = content.replace(old, new, 1)
    with open('device/rockchip/common/device.mk', 'w') as f:
        f.write(content)
    print('[FIXED] device/rockchip/common/device.mk: 已添加 car 产品分支（跳过 Launcher3QuickStep）')
else:
    print('[SKIP] device/rockchip/common/device.mk: 目标文本未匹配（已打过 patch 或文件内容已变更）')
    sys.exit(1)
PYEOF
        if [[ $? -eq 0 ]]; then
            log_ok "已修复 $_DEVICE_MK（car 分支已添加，跳过 Launcher3QuickStep）"
        else
            log_warn "修复 $_DEVICE_MK 失败，请手动检查文件"
        fi
    else
        log_info "跳过 $_DEVICE_MK（目标文本不存在，可能已变更）"
    fi
else
    log_info "跳过 $_DEVICE_MK（文件不存在）"
fi

# Fix #5: device/rockchip/common/modules/optimize.mk 对 rk3588 无条件设置
#   dalvik.vm.dex2oat-threads=8，而 car_base.mk（由 car.mk 引入）也设置了
#   dalvik.vm.dex2oat-threads=2。两者值不同，Android T 的 post_process_props
#   把同一 key 的不同值赋值视为错误（error: found duplicate sysprop assignments）。
#   修复：给 optimize.mk 中 dex2oat-threads 的赋值加 car 产品排除条件，
#   car 产品使用 car_base.mk 的值（=2），非 car 产品保持原有行为（=8）。
_OPTIMIZE_MK="$ANDROID_ROOT/device/rockchip/common/modules/optimize.mk"
if [[ -f "$_OPTIMIZE_MK" ]]; then
    if grep -q "TARGET_BOARD_PLATFORM_PRODUCT.*car" "$_OPTIMIZE_MK"; then
        log_info "跳过 $_OPTIMIZE_MK（car 排除条件已存在）"
    elif grep -q "dalvik.vm.dex2oat-threads=8" "$_OPTIMIZE_MK"; then
        python3 - <<'PYEOF'
import sys
with open('device/rockchip/common/modules/optimize.mk', 'r') as f:
    content = f.read()

old = ('ifneq ($(filter rk3368 rk3588, $(strip $(TARGET_BOARD_PLATFORM))), )\n'
       'PRODUCT_PROPERTY_OVERRIDES += \\\n'
       '    dalvik.vm.boot-dex2oat-threads=8 \\\n'
       '    dalvik.vm.dex2oat-threads=8')

new = ('ifneq ($(filter rk3368 rk3588, $(strip $(TARGET_BOARD_PLATFORM))), )\n'
       'PRODUCT_PROPERTY_OVERRIDES += \\\n'
       '    dalvik.vm.boot-dex2oat-threads=8\n'
       '# car_base.mk sets dalvik.vm.dex2oat-threads=2; skip here to avoid duplicate assignment\n'
       'ifneq ($(strip $(TARGET_BOARD_PLATFORM_PRODUCT)), car)\n'
       'PRODUCT_PROPERTY_OVERRIDES += \\\n'
       '    dalvik.vm.dex2oat-threads=8\n'
       'endif')

if old in content:
    content = content.replace(old, new, 1)
    with open('device/rockchip/common/modules/optimize.mk', 'w') as f:
        f.write(content)
    print('[FIXED] optimize.mk: dex2oat-threads=8 已加 car 产品排除条件')
else:
    print('[SKIP] optimize.mk: 目标文本未匹配（已打过 patch 或文件内容已变更）')
    sys.exit(1)
PYEOF
        if [[ $? -eq 0 ]]; then
            log_ok "已修复 $_OPTIMIZE_MK（car 产品跳过 dex2oat-threads=8，由 car_base.mk 统一设置）"
        else
            log_warn "修复 $_OPTIMIZE_MK 失败，请手动检查文件"
        fi
    else
        log_info "跳过 $_OPTIMIZE_MK（目标文本不存在，可能已变更）"
    fi
else
    log_info "跳过 $_OPTIMIZE_MK（文件不存在）"
fi

# ---- 3. 加载编译工具链 ----
log_step "[3/3] 加载 Android 编译工具链（envsetup + lunch）..."

source build/envsetup.sh

# 选择编译目标：
#   V_gatron_car - RK3588 AAOS 车机目标（device/rockchip/rk3588/V_gatron_car）
#   userdebug    - 保留 root 权限和调试能力，移植开发阶段使用
# do_mkimage() 依赖 get_build_var（需板级上下文），所有模式均使用此目标。
lunch V_gatron_car-userdebug || { log_error "lunch 失败"; exit 1; }

log_ok "编译环境初始化完成"
cd "$SCRIPT_DIR"

# ============================================================
# do_mkimage：将各分区镜像整理到 $SCRIPT_DIR/Image/
#   移植自 RK 参考 mkimage.sh，适配 V_gatron_car / RK3588 差异：
#   - RK3588 ATF 已内嵌于 uboot.img，无独立 trust.img（正常跳过）
#   - BOARD_AVB_ENABLE=false → 使用 device/rockchip/common/vbmeta.img 占位
#   - rkst/Image/misc.img 由 apply-patches.sh 从 patches/misc.img 部署（未找到则警告）
#   - parameter.txt 优先 device 目录，回退 $OUT，再回退工厂镜像
#   - boot.img 优先 $OUT（整编产物），回退 kernel-5.10/（-K 临时合成版）
# ============================================================
do_mkimage() {
    log_banner "整理分区镜像（mkimage）"
    cd "$ANDROID_ROOT"

    local TARGET_DEVICE_DIR; TARGET_DEVICE_DIR=$(get_build_var TARGET_DEVICE_DIR)
    local BOARD_AVB_ENABLE; BOARD_AVB_ENABLE=$(get_build_var BOARD_AVB_ENABLE)
    local PRODUCT_USE_DYNAMIC_PARTITIONS; PRODUCT_USE_DYNAMIC_PARTITIONS=$(get_build_var PRODUCT_USE_DYNAMIC_PARTITIONS)
    local TARGET_BASE_PARAMETER_IMAGE; TARGET_BASE_PARAMETER_IMAGE=$(get_build_var TARGET_BASE_PARAMETER_IMAGE)
    local KERNEL_PATH; KERNEL_PATH=$(get_build_var PRODUCT_KERNEL_PATH)

    local IMAGE_DIR="$SCRIPT_DIR/Image"
    local UBOOT_PATH="$SCRIPT_DIR/u-boot"

    log_info "TARGET_DEVICE_DIR              = $TARGET_DEVICE_DIR"
    log_info "BOARD_AVB_ENABLE               = $BOARD_AVB_ENABLE"
    log_info "PRODUCT_USE_DYNAMIC_PARTITIONS = $PRODUCT_USE_DYNAMIC_PARTITIONS"
    log_info "KERNEL_PATH                    = $KERNEL_PATH"
    log_info "IMAGE_DIR                      = $IMAGE_DIR"

    if [[ -d "$IMAGE_DIR" ]]; then
        log_info "清空已有目录: $IMAGE_DIR"
        rm -rf "${IMAGE_DIR:?}"/*
    else
        log_info "创建目录: $IMAGE_DIR"
        mkdir -p "$IMAGE_DIR" || { log_error "创建 $IMAGE_DIR 失败"; exit 1; }
    fi

    # ---- uboot.img ----
    if [[ -f "$UBOOT_PATH/uboot.img" ]]; then
        cp -a "$UBOOT_PATH/uboot.img" "$IMAGE_DIR/uboot.img"
        log_ok "uboot.img"
    else
        log_warn "uboot.img 未找到: $UBOOT_PATH/uboot.img（请先编译 U-Boot）"
    fi

    # ---- MiniLoaderAll.bin ----
    local _loader_found=0
    local _loader_pat
    for _loader_pat in "$UBOOT_PATH"/*_loader_*.bin "$UBOOT_PATH"/*loader*.bin; do
        if [[ -f "$_loader_pat" ]]; then
            cp -a "$_loader_pat" "$IMAGE_DIR/MiniLoaderAll.bin"
            log_ok "MiniLoaderAll.bin（from $(basename "$_loader_pat")）"
            _loader_found=1
            break
        fi
    done
    [[ $_loader_found -eq 0 ]] && log_warn "未找到 loader bin（$UBOOT_PATH/*loader*.bin），请先编译 U-Boot"

    # ---- dtbo.img（优先 dtbo.img，回退 rebuild-dtbo.img）----
    if [[ -f "${OUT:-}/dtbo.img" ]]; then
        cp -a "$OUT/dtbo.img" "$IMAGE_DIR/dtbo.img"
        log_ok "dtbo.img"
    elif [[ -f "${OUT:-}/rebuild-dtbo.img" ]]; then
        cp -a "$OUT/rebuild-dtbo.img" "$IMAGE_DIR/dtbo.img"
        log_ok "dtbo.img（from rebuild-dtbo.img）"
    else
        log_warn "dtbo.img / rebuild-dtbo.img 均未找到，跳过"
    fi

    # ---- resource.img（来自内核源码目录，含 logo BMP）----
    if [[ -f "$ANDROID_ROOT/$KERNEL_PATH/resource.img" ]]; then
        cp -a "$ANDROID_ROOT/$KERNEL_PATH/resource.img" "$IMAGE_DIR/resource.img"
        log_ok "resource.img"
    else
        log_warn "resource.img 未找到: $ANDROID_ROOT/$KERNEL_PATH/resource.img"
    fi

    # ---- boot.img ----
    if [[ -f "${OUT:-}/boot.img" ]]; then
        cp -a "$OUT/boot.img" "$IMAGE_DIR/boot.img"
        log_ok "boot.img"
    else
        log_warn "boot.img 未找到: $OUT/boot.img（请先运行 ./build.sh -A 整编）"
    fi

    # ---- recovery.img ----
    if [[ -f "${OUT:-}/recovery.img" ]]; then
        cp -a "$OUT/recovery.img" "$IMAGE_DIR/recovery.img"
        log_ok "recovery.img"
    else
        log_warn "recovery.img 未找到"
    fi

    # ---- super.img（动态分区）----
    if [[ -f "${OUT:-}/super.img" ]]; then
        cp -a "$OUT/super.img" "$IMAGE_DIR/super.img"
        log_ok "super.img"
    else
        log_warn "super.img 未找到"
    fi

    # ---- data.img（来自 userdata.img；AB 模式不收集，但当前非 AB）----
    if [[ -f "${OUT:-}/userdata.img" ]]; then
        cp -a "$OUT/userdata.img" "$IMAGE_DIR/data.img"
        log_ok "data.img（from userdata.img）"
    else
        log_warn "userdata.img 未找到，跳过 data.img"
    fi

    # ---- vbmeta.img ----
    if [[ "$BOARD_AVB_ENABLE" == "true" ]]; then
        if [[ -f "${OUT:-}/vbmeta.img" ]]; then
            cp -a "$OUT/vbmeta.img" "$IMAGE_DIR/vbmeta.img"
            log_ok "vbmeta.img（AVB 签名版）"
        else
            log_warn "AVB 开启但 vbmeta.img 未找到: $OUT/vbmeta.img"
        fi
    else
        if [[ -f "device/rockchip/common/vbmeta.img" ]]; then
            cp -a "device/rockchip/common/vbmeta.img" "$IMAGE_DIR/vbmeta.img"
            log_warn "vbmeta.img（dummy，BOARD_AVB_ENABLE=false）"
        else
            log_warn "device/rockchip/common/vbmeta.img 未找到"
        fi
    fi

    # ---- misc.img（来自 rkst/Image/，由 apply-patches.sh 从 patches/misc.img 部署）----
    # misc 分区控制 U-Boot 启动流向（正常 / recovery / fastboot），RK 预编译 blob。
    if [[ -f "rkst/Image/misc.img" ]]; then
        cp -a "rkst/Image/misc.img" "$IMAGE_DIR/misc.img"
        log_ok "misc.img"
    else
        log_error "misc.img 未找到: rkst/Image/misc.img（请重新运行 apply-patches.sh）"
        exit 1
    fi

    # ---- config.cfg（RKDevTool 烧录配置）----
    local _flash_cfg="$TARGET_DEVICE_DIR/config.cfg"
    if [[ -f "$_flash_cfg" ]]; then
        cp -a "$_flash_cfg" "$IMAGE_DIR/config.cfg"
        log_ok "config.cfg"
    else
        log_warn "config.cfg 未找到: $_flash_cfg"
    fi

    # ---- parameter.txt（eMMC 分区表）----
    # 优先 device 目录，回退 $OUT（动态生成），再回退工厂镜像（-K 单独编译时）
    local _param_dev="$TARGET_DEVICE_DIR/parameter.txt"
    if [[ -f "$_param_dev" ]]; then
        cp -a "$_param_dev" "$IMAGE_DIR/parameter.txt"
        log_warn "parameter.txt（来自 device 目录）"
    elif [[ -f "${OUT:-}/parameter.txt" ]]; then
        cp -a "$OUT/parameter.txt" "$IMAGE_DIR/parameter.txt"
        log_ok "parameter.txt（来自 \$OUT，动态生成）"
    else
        log_warn "parameter.txt 未找到（device 目录、\$OUT均无）"
    fi

    # ---- baseparameter.img（可选，TARGET_BASE_PARAMETER_IMAGE 控制）----
    if [[ -n "$TARGET_BASE_PARAMETER_IMAGE" ]]; then
        if [[ -f "$TARGET_BASE_PARAMETER_IMAGE" ]]; then
            cp -a "$TARGET_BASE_PARAMETER_IMAGE" "$IMAGE_DIR/baseparameter.img"
            log_ok "baseparameter.img"
        else
            log_warn "baseparameter.img 未找到: $TARGET_BASE_PARAMETER_IMAGE"
        fi
    fi

    chmod a+r -R "$IMAGE_DIR/"
    cd "$SCRIPT_DIR"

    log_ok "产物目录: $IMAGE_DIR"
    log_info "$(ls -lh "$IMAGE_DIR" 2>/dev/null || echo '（空）')"
    log_banner "镜像整理完成 ✓"
}

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
    # ---- 内核编译参数（从 BoardConfig.mk 动态读取）----
    KERNEL_VERSION=$(get_build_var PRODUCT_KERNEL_VERSION)
    KERNEL_ARCH=$(get_build_var PRODUCT_KERNEL_ARCH)
    KERNEL_DEFCONFIG=$(get_build_var PRODUCT_KERNEL_CONFIG)
    KERNEL_DTS=$(get_build_var PRODUCT_KERNEL_DTS)

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
        log_error ".scmversion 不存在，make 阶段可能出现 git 警告，建议重新运行 apply-patches.sh"
        exit 1
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

    # ---- [wifi] 外部 wifi/BT driver 编译（out-of-tree 内核模块 .ko）----
    # external/wifi_driver 顶层是 Kbuild 风格（obj-$(CONFIG_...)），无 Android.mk/bp，
    # 必须用 make -C <kernel> M=<driver> 在内核源码树外单独编译，整编无法自动覆盖。
    EXT_WIFI_PATH="$ANDROID_ROOT/external/wifi_driver"
    if [[ -d "$EXT_WIFI_PATH" ]]; then
        log_step "[wifi] 编译外部 wifi/BT 驱动（out-of-tree 内核模块）..."
        # set_android_version.sh：根据 Android 版本号导出驱动编译宏（如 ANDROID_VERSION）
        if [[ -f "$EXT_WIFI_PATH/set_android_version.sh" ]]; then
            source "$EXT_WIFI_PATH/set_android_version.sh" "$EXT_WIFI_PATH"
            log_info "已加载 wifi driver set_android_version.sh"
        fi
        if [[ $BUILD_CLEAN -eq 1 ]]; then
            run_cmd "wifi driver: make clean" \
                make $ADDON_ARGS ARCH="${KERNEL_ARCH}" \
                    -C "$KERNEL_SRC" M="$EXT_WIFI_PATH" clean
        else
            log_info "增量模式，跳过 wifi driver clean（-c 可全量重编）"
        fi
        run_cmd "wifi driver: make -j${BUILD_JOBS}" \
            make $ADDON_ARGS ARCH="${KERNEL_ARCH}" \
                -C "$KERNEL_SRC" M="$EXT_WIFI_PATH" -j"${BUILD_JOBS}"
        log_ok "外部 wifi/BT 驱动编译完成"
    else
        log_error "external/wifi_driver/ 不存在，跳过外部 wifi 驱动编译"
        exit 1
    fi

    # ---- [3/3] 复制 kernel Image → $OUT/kernel ----
    # make bootimage 从 $OUT/kernel 取镜像，整编不会重编内核源码，须手动放置
    log_step "[3/3] 复制 kernel Image → \$OUT/kernel..."
    if [[ -z "${OUT:-}" ]]; then
        log_error "[3/3] \$OUT 未设置，跳过（lunch 环境变量丢失，请重新 source build/envsetup.sh && lunch）"
        exit 1
    else
        mkdir -p "$OUT"
        run_cmd "cp Image → \$OUT/kernel" \
            cp -f "${KERNEL_SRC}/arch/arm64/boot/Image" "${OUT}/kernel"
        log_info "已放置: ${OUT}/kernel（make bootimage 从此路径取 Image）"
    fi

    # ---- [boot] 合成 boot.img ----
    log_step "[boot] make bootimage..."
    cd "$ANDROID_ROOT"
    run_cmd "make bootimage"     make bootimage
    run_cmd "make recoveryimage" make recoveryimage
    log_ok "boot.img: ${OUT}/boot.img"
    log_info "刷入命令: fastboot flash boot ${OUT}/boot.img"

    cd "$SCRIPT_DIR"
    log_banner "内核编译完成 ✓"
fi

# ---------- 整编 Android ----------
if [[ $BUILD_ANDROID -eq 1 ]]; then
    log_banner "整编 Android"

    BUILD_JOBS="${CPU_CORES}"
    log_info "BUILD_JOBS = ${BUILD_JOBS}"

    cd "$ANDROID_ROOT"

    # installclean：清除上次编译的中间产物，避免残留文件导致镜像不一致
    # 比 make clean 轻量（不删除工具链产物），整编标准流程
    run_cmd "make installclean" make installclean

    run_cmd "make -j${BUILD_JOBS}" make -j"${BUILD_JOBS}"

    cd "$SCRIPT_DIR"
    log_banner "Android 整编完成 ✓"
fi

# ---------- 整理产物到 Image 目录 ----------
do_mkimage
log_banner "全部完成 ✓"
