include device/rockchip/rk3588/BoardConfig.mk
BUILD_WITH_GO_OPT := false

# AB image definition
BOARD_USES_AB_IMAGE := false
BOARD_ROCKCHIP_VIRTUAL_AB_ENABLE := false
ifeq ($(strip $(BOARD_USES_AB_IMAGE)), true)
    include device/rockchip/common/BoardConfig_AB.mk
    TARGET_RECOVERY_FSTAB := device/rockchip/rk3588/V_gatron_car/recovery.fstab_AB
endif
# sensor MXC6655XA
BOARD_GRAVITY_SENSOR_SUPPORT := true
BOARD_GYROSCOPE_SENSOR_SUPPORT := true
BOARD_GSENSOR_MXC6655XA_SUPPORT := true
# USB/CSI Camera
BOARD_CAMERA_SUPPORT_EXT := false
# ethernet
BOARD_HS_ETHERNET := false
#car flag
BOARD_ROCKCHIP_VEHICLE := true
#car boot.img need more large size
BOARD_BOOTIMAGE_PARTITION_SIZE := 47259648
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
# 4G/5G modem
BOARD_HAS_RK_4G_MODEM := true
BOARD_HAS_QUECTEL_5G_MODEM := true
BOARD_HAS_FIBOCOM_5G_MODEM := false
# HDMI IN
BOARD_HDMI_IN_SUPPORT := false
# Disable repo manifest snapshot (repo tool hits EROFS on WSL2)
BOARD_RECORD_COMMIT_ID := false

PRODUCT_UBOOT_CONFIG := rk3588
PRODUCT_KERNEL_DTS := rk3588-v-gatron
PRODUCT_KERNEL_CONFIG := V-gatron_defconfig
