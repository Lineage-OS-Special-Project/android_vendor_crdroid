#
# Copyright (C) 2018-2019 The Google Pixel3ROM Project
# Copyright (C) 2024 The hentaiOS Project and its Proprietors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Current GMSCore is delivered as the prodvic APEX plus split modules.
DISABLE_DEXPREOPT_CHECK := true

PRODUCT_PACKAGES += \
    com.google.android.gmssystem.prodvic

# Quick Tap
TARGET_SUPPORTS_QUICK_TAP ?= true
ifeq ($(TARGET_SUPPORTS_QUICK_TAP),true)
PRODUCT_PACKAGES += \
    quick_tap
endif

# ARCore
TARGET_INCLUDE_STOCK_ARCORE ?= true
ifeq ($(TARGET_INCLUDE_STOCK_ARCORE),true)
PRODUCT_PACKAGES += \
    arcore
endif

# Pixel Launcher
TARGET_INCLUDE_PIXEL_LAUNCHER ?= false
ifeq ($(TARGET_INCLUDE_PIXEL_LAUNCHER),true)
PRODUCT_PACKAGES += \
    NexusLauncherRelease
endif

# Live wallpapers (Google devices only)
TARGET_INCLUDE_LIVE_WALLPAPERS ?= false
ifneq ($(filter sailfish marlin walleye taimen blueline crosshatch sargo bonito flame coral sunfish bramble redfin barbet oriole raven bluejay panther cheetah lynx tangorpro felix shiba husky akita tokay caiman komodo comet tegu frankel blazer mustang rango stallion,$(LINEAGE_BUILD)),)
ifeq ($(TARGET_INCLUDE_LIVE_WALLPAPERS),true)
PRODUCT_PACKAGES += \
    MagicPortraitWallpapers \
    PixelWallpapers2026 \
    PixelLiveWallpaperPrebuilt-27000055
endif
endif

ifneq ($(filter Google google,$(PRODUCT_MANUFACTURER)),)
PRODUCT_PACKAGES += \
    SCONE-v77459 \
    Tycho
endif

ifneq ($(filter flame coral redfin oriole raven panther cheetah lynx felix shiba husky akita tokay caiman komodo tegu frankel blazer mustang rango stallion,$(LINEAGE_BUILD)),)
PRODUCT_PACKAGES += \
    DreamlinerDreamsPrebuilt_100894 \
    DreamlinerPrebuilt_22000020 \
    DreamlinerUpdater
endif

# TensorFlow support retained from the LOSP package set.
PRODUCT_PACKAGES += \
    libtensorflowlite_jni \
    MagicPortraitSymLink

# libtensorflowlite_jni installs to /system and must be explicitly allowed
# through the generic system artifact path requirement.
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/app/GoogleExtShared/GoogleExtShared.apk \
    system/app/GooglePrintRecommendationService/GooglePrintRecommendationService.apk \
    system/priv-app/DocumentsUIGoogle/DocumentsUIGoogle.apk \
    system/priv-app/GooglePackageInstaller/GooglePackageInstaller.apk \
    system/lib64/libtensorflowlite_jni.so

PRODUCT_PACKAGES += \
    CarrierLocation \
    CarrierMetrics \
    CbrsNetworkMonitor \
    GoogleExtShared \
    GooglePrintRecommendationService \
    LocationHistoryPrebuilt \
    NgaResources

PRODUCT_PACKAGES += \
    ConfigUpdater \
    PixelThemesStub2026

# Chrome/WebView components retained from the LOSP package set.
PRODUCT_PACKAGES += \
    Chrome-Stub \
    TrichromeLibrary \
    TrichromeLibrary-Stub \
    WebViewGoogle \
    WebViewGoogle-Stub

# Setup and provisioning
PRODUCT_PACKAGES += \
    GoogleRestorePrebuilt-v1054408 \
    PartnerSetupPrebuilt \
    PersistentBackgroundServices \
    PrebuiltPixelCoreServices \
    SearchSelectorPrebuilt \
    SetupWizardPrebuilt_cd1a \
    SetupWizardPixelPrebuilt_cd1a

# Android 17 GMSCore split and supporting modules retained from LOSP A16.
PRODUCT_PACKAGES += \
    PrebuiltGmsCoreVic_AdsDynamite \
    PrebuiltGmsCoreVic_CronetDynamite \
    PrebuiltGmsCoreVic_DynamiteLoader \
    PrebuiltGmsCoreVic_DynamiteModulesA \
    PrebuiltGmsCoreVic_DynamiteModulesC \
    PrebuiltGmsCoreVic_GoogleCertificates \
    PrebuiltGmsCoreVic_MapsDynamite \
    PrebuiltGmsCoreVic_MeasurementDynamite \
    AndroidPlatformServices \
    MlkitBarcodeUIPrebuilt \
    TfliteDynamitePrebuilt \
    VisionBarcodePrebuilt

# Play Store and GSF
PRODUCT_PACKAGES += \
    GoogleServicesFramework \
    Phonesky

# User-facing packages intentionally retained from the LOSP A16 set.
PRODUCT_PACKAGES += \
    GoogleDialer \
    DocumentsUIGoogle \
    EmergencyInfoGoogleNoUi \
    Flipendo \
    GoogleContacts \
    GooglePackageInstaller \
    GoogleTTS \
    LatinIMEGooglePrebuilt \
    MarkupGoogle_v2 \
    PrebuiltBugle \
    PrebuiltDeskClockGoogle_76060331 \
    StorageManagerGoogle \
    SoundPickerPrebuilt_3.4

# Device connectivity
PRODUCT_PACKAGES += \
    DeviceConnectivityServicePrebuilt_26.01.00

# Default sounds
PRODUCT_PRODUCT_PROPERTIES += \
    ro.config.ringtone=The_next_adventure.ogg \
    ro.config.notification_sound=Kernel.ogg \
    ro.config.alarm_alert=Fresh_morning.ogg

# Optional Mosey package retained behind the LOSP toggle.
TARGET_INCLUDE_MOSEY ?= false
ifeq ($(TARGET_INCLUDE_MOSEY),true)
PRODUCT_PACKAGES += \
    MoseyApp
endif

$(call inherit-product, vendor/gms/product/blobs/product_blobs.mk)
$(call inherit-product, vendor/gms/system/blobs/system_blobs.mk)
$(call inherit-product, vendor/gms/system_ext/blobs/system-ext_blobs.mk)
