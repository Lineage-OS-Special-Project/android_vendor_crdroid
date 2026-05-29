# -----------------------------------------------------------------------------
# Pixel / Google configuration
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Pixel / Google core components
# -----------------------------------------------------------------------------

# APEX
DISABLE_DEXPREOPT_CHECK := true

# Pixel audio
$(call inherit-product-if-exists, vendor/pixel-style/config/audio.mk)

# PixelParts (Google devices only)
ifneq ($(filter Google google,$(PRODUCT_MANUFACTURER)),)
$(call inherit-product-if-exists, packages/apps/PixelParts/device.mk)
endif

# -----------------------------------------------------------------------------
# Pixel-targeted overlay packages
# -----------------------------------------------------------------------------

PRODUCT_PACKAGES += \
    AvatarPickerPixelOverlay \
    CellBroadcastReceiverOverlay \
    CellBroadcastServiceOverlay \
    GoogleConfigOverlay \
    GoogleDeviceLockControllerOverlay \
    GoogleHealthConnectOverlay \
    GooglePermissionControllerOverlay \
    GooglePermissionControllerSafetyCenterOverlay \
    GoogleSettingsOverlay \
    GoogleSystemUIOverlay \
    GoogleWebViewOverlay \
    ManagedProvisioningPixelOverlay \
    PixelAccessibilityMenu \
    PixelBuiltInPrintService \
    PixelContactsProvider \
    PixelDeviceDiagnostics \
    PixelDocumentsUIGoogleOverlay \
    PixelSettingsGoogle \
    PixelSettingsProvider \
    PixelSetupWizardOverlayExpressive \
    PixelSystemUIGoogle \
    PixelTelecom \
    PixelTeleService \
    Pixelframework-res \
    SystemUIGXOverlay \
    UdfpsOverlay \
    VerifierResOverlay \
    WallpaperPicker2Overlay \
    WallpaperPicker2PixelOverlay \
    WildlifeSettingsVpnOverlay2022

# -----------------------------------------------------------------------------
# Default sounds (non-GMS)
# -----------------------------------------------------------------------------

ifeq ($(WITH_GMS),false)
PRODUCT_PRODUCT_PROPERTIES += \
    ro.config.ringtone=Orion.ogg \
    ro.config.notification_sound=Argon.ogg \
    ro.config.alarm_alert=Hassium.ogg
endif

# -----------------------------------------------------------------------------
# Google client IDs
# -----------------------------------------------------------------------------

ifeq ($(PRODUCT_GMS_CLIENTID_BASE),)
PRODUCT_PRODUCT_PROPERTIES += \
    ro.com.google.clientidbase=android-google
else
PRODUCT_PRODUCT_PROPERTIES += \
    ro.com.google.clientidbase=$(PRODUCT_GMS_CLIENTID_BASE)
endif

ifeq ($(PRODUCT_IS_ATV),true)
ifeq ($(PRODUCT_ATV_CLIENTID_BASE),)
PRODUCT_PRODUCT_PROPERTIES += \
    ro.oem.key1=ATV00100020
else
PRODUCT_PRODUCT_PROPERTIES += \
    ro.oem.key1=$(PRODUCT_ATV_CLIENTID_BASE)
endif
endif

# -----------------------------------------------------------------------------
# SetupWizard
# -----------------------------------------------------------------------------

PRODUCT_PRODUCT_PROPERTIES += \
    ro.setupwizard.enterprise_mode=1 \
    ro.setupwizard.esim_cid_ignore=00000001 \
    setupwizard.feature.baseline_setupwizard_enabled=true \
    setupwizard.feature.day_night_mode_enabled=true \
    setupwizard.feature.portal_notification=true \
    setupwizard.feature.enable_quick_start_flow=true \
    setupwizard.feature.enable_restore_anytime=true \
    setupwizard.feature.enable_wifi_tracker=true \
    setupwizard.feature.lifecycle_refactoring=true \
    setupwizard.feature.notification_refactoring=true \
    setupwizard.feature.show_pai_screen_in_main_flow.carrier1839=false \
    setupwizard.feature.show_pixel_tos=true \
    setupwizard.feature.show_support_link_in_deferred_setup=false \
    setupwizard.feature.skip_button_use_mobile_data.carrier1839=true \
    setupwizard.personal_safety_suw_enabled=true \
    setupwizard.theme=glif_expressive \
    setupwizard.feature.default_locale_enhancement_enabled=true \
    setupwizard.feature.device_info_icon_enabled=true \
    setupwizard.feature.provisioning_profile_mode=true \
    setupwizard.feature.enable_gil= \
    setupwizard.feature.enable_gil_logging=true \
    setupwizard.feature.enable_minors_setup_flow=true \
    setupwizard.feature.enable_parental_notice_activity=true \
    setupwizard.feature.enable_parental_setup=true \
    setupwizard.feature.enable_quick_start_flow=true \
    setupwizard.feature.enable_restore_anytime=true \
    setupwizard.feature.enable_wifi_tracker=true \
    setupwizard.feature.enhanced_setup_design_metrics=true \
    setupwizard.feature.is_suw_onboarding_contract_enabled=true \
    setupwizard.feature.joined_up_loading=true \
    setupwizard.feature.locale_agnostic_enabled=true

ifeq ($(PRODUCT_CHARACTERISTICS),tablet)
PRODUCT_PRODUCT_PROPERTIES += \
    ro.setupwizard.rotation_locked=false
else
PRODUCT_PRODUCT_PROPERTIES += \
    ro.setupwizard.rotation_locked=true
endif

# -----------------------------------------------------------------------------
# StorageManager
# -----------------------------------------------------------------------------

PRODUCT_PRODUCT_PROPERTIES += \
    ro.storage_manager.enabled=false \
    ro.storage_manager.show_opt_in=false

# -----------------------------------------------------------------------------
# Google input / keyboard
# -----------------------------------------------------------------------------

PRODUCT_PRODUCT_PROPERTIES += \
    ro.com.google.ime.system_lm_dir=/product/usr/share/ime/google/d3_lms \
    ro.com.google.ime.theme_id=5

ifneq ($(TARGET_GBOARD_KEY_HEIGHT),)
PRODUCT_PRODUCT_PROPERTIES += \
    ro.com.google.ime.height_ratio=$(TARGET_GBOARD_KEY_HEIGHT)
endif

# -----------------------------------------------------------------------------
# Google legal / assistant / service integration
# -----------------------------------------------------------------------------

PRODUCT_PRODUCT_PROPERTIES += \
    ro.atrace.core.services=com.google.android.gms,com.google.android.gms.ui,com.google.android.gms.persistent \
    ro.error.receiver.system.apps=com.google.android.gms \
    ro.opa.eligible_device=true \
    ro.url.legal=http://www.google.com/intl/%s/mobile/android/basic/phone-legal.html \
    ro.url.legal.android_privacy=http://www.google.com/intl/%s/mobile/android/basic/privacy.html

# -----------------------------------------------------------------------------
# Pixel / Google feature properties
# -----------------------------------------------------------------------------

PRODUCT_PRODUCT_PROPERTIES += \
    charging_string.apply_lotx=true \
    charging_string.apply_v2=true \
    ro.carriersetup.vzw_consent_page=true \
    ro.gwfcactivation.disabled_carriers=1492

# -----------------------------------------------------------------------------
# SystemUI / navigation
# -----------------------------------------------------------------------------

# Use gesture navigation by default with the Google SystemUI GX overlay
PRODUCT_PROPERTY_OVERRIDES += \
    ro.boot.vendor.overlay.theme=com.android.internal.systemui.navbar.gestural;com.google.android.systemui.gxoverlay_gms

# -----------------------------------------------------------------------------
# Google Photos
# -----------------------------------------------------------------------------

PRODUCT_PRODUCT_PROPERTIES += \
    debug.photos.eraser_camo=1 \
    debug.photos.eraser_suggestion=1 \
    debug.photos.force_pixel_eol=1 \
    debug.photos.p_editr.eraser=1
