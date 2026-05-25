TARGET_BOARD_PLATFORM_PRODUCT := car

# First lunching is T, api_level is 33
PRODUCT_SHIPPING_API_LEVEL := 33
PRODUCT_DTBO_TEMPLATE := $(LOCAL_PATH)/dt-overlay.in

include device/rockchip/common/build/rockchip/DynamicPartitions.mk
include device/rockchip/rk3588/V_gatron_car/BoardConfig.mk
include device/rockchip/common/BoardConfig.mk
$(call inherit-product, device/rockchip/rk3588/device.mk)
$(call inherit-product, device/rockchip/common/device.mk)
$(call inherit-product, frameworks/native/build/tablet-10in-xhdpi-2048-dalvik-heap.mk)

DEVICE_MANIFEST_FILE += device/rockchip/rk3588/V_gatron_car/manifest.xml
DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/../overlay
PRODUCT_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay

PRODUCT_CHARACTERISTICS := car

PRODUCT_NAME := V_gatron_car
PRODUCT_DEVICE := V_gatron_car
PRODUCT_BRAND := Alientek
PRODUCT_MODEL := V-Gatron-RK3588
PRODUCT_MANUFACTURER := Alientek
PRODUCT_AAPT_PREF_CONFIG := xhdpi

PRODUCT_PROPERTY_OVERRIDES += ro.sf.lcd_density=340
PRODUCT_PROPERTY_OVERRIDES += ro.wifi.sleep.power.down=true
PRODUCT_PROPERTY_OVERRIDES += persist.wifi.sleep.delay.ms=0
PRODUCT_PROPERTY_OVERRIDES += persist.bt.power.down=true
PRODUCT_PROPERTY_OVERRIDES += vendor.hwc.device.primary=DP

PRODUCT_PACKAGES += \
     modetest
