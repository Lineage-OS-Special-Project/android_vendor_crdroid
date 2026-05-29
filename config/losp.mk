# -----------------------------------------------------------------------------
# LOSP feature configuration
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# LOSP product properties
# -----------------------------------------------------------------------------

PRODUCT_PRODUCT_PROPERTIES += \
    dalvik.vm.debug.alloc=0 \
    ro.com.android.wifi-watchlist=GoogleGuest \
    drm.service.enabled=true \
    persist.sys.dun.override=0 \
    persist.sys.disable_rescue=true

# -----------------------------------------------------------------------------
# Input / graphics behaviour
# -----------------------------------------------------------------------------

# Disable touch video heatmap to reduce latency, motion jitter, and CPU usage
# on supported devices with Deep Press input classifier HALs and models
PRODUCT_PRODUCT_PROPERTIES += \
    ro.input.video_enabled=false

# Enable Material Design 3 Expressive
PRODUCT_PRODUCT_PROPERTIES += \
    is_expressive_design_enabled=true

# Background blur support
ifneq ($(TARGET_SUPPORTS_BLUR),false)
PRODUCT_PRODUCT_PROPERTIES += \
    ro.surface_flinger.supports_background_blur=1
endif

# -----------------------------------------------------------------------------
# Runtime / ART configuration
# -----------------------------------------------------------------------------

PRODUCT_SYSTEM_EXT_PROPERTIES += \
    dalvik.vm.dex2oat64.enabled=true

# -----------------------------------------------------------------------------
# LOSP permissions / sysconfig
# -----------------------------------------------------------------------------

PRODUCT_COPY_FILES += \
    vendor/lineage/prebuilt/common/etc/sysconfig/preinstalled-packages-platform-losp-product.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/sysconfig/preinstalled-packages-platform-losp-product.xml

# -----------------------------------------------------------------------------
# LOSP feature packages
# -----------------------------------------------------------------------------

PRODUCT_PACKAGES += \
    AxQuickLook \
    AxSandbox \
    AxThemeStore \
    BatteryStatsViewer \
    GameSpace \
    LMOFreeform \
    LMOFreeformSidebar \
    OmniJaws \
    OmniStyle

# -----------------------------------------------------------------------------
# Columbus / Quick Tap
# -----------------------------------------------------------------------------

ifneq ($(TARGET_SUPPORTS_QUICK_TAP),false)
PRODUCT_PACKAGES += \
    ColumbusService
endif

# -----------------------------------------------------------------------------
# MatLog
# -----------------------------------------------------------------------------

ifneq ($(TARGET_DISABLE_MATLOG),true)
PRODUCT_PACKAGES += \
    MatLog
endif

# -----------------------------------------------------------------------------
# Face Unlock
# -----------------------------------------------------------------------------

ifneq ($(TARGET_FACE_UNLOCK_SUPPORTED),false)
PRODUCT_PACKAGES += \
    FaceUnlock

PRODUCT_SYSTEM_EXT_PROPERTIES += \
    ro.face.sense_service=true

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.biometrics.face.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/android.hardware.biometrics.face.xml
endif

# -----------------------------------------------------------------------------
# Device as Webcam
# -----------------------------------------------------------------------------

ifeq ($(TARGET_BUILD_DEVICE_AS_WEBCAM),true)
PRODUCT_PACKAGES += \
    DeviceAsWebcam

PRODUCT_VENDOR_PROPERTIES += \
    ro.usb.uvc.enabled=true
endif