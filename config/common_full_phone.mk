# Inherit mobile full common Lineage stuff
$(call inherit-product, vendor/lineage/config/common_mobile_full.mk)

# Enable support of one-handed mode
PRODUCT_PRODUCT_PROPERTIES += \
    ro.support_one_handed_mode?=true

$(call inherit-product, vendor/lineage/config/telephony.mk)

# -----------------------------------------------------------------------------
# Mobile services provider
# -----------------------------------------------------------------------------

# Load the provider selected by the LOSP device setup wizard.
-include $(TOPDIR).losp_build_config.mk

# Default to full GMS when no local selection has been generated.
LOSP_GMS_TYPE ?= gms

ifeq ($(LOSP_GMS_TYPE),gms)

WITH_GMS := true

ifeq ($(TARGET_USES_MINI_GAPPS),true)
$(call inherit-product, vendor/gms/gms_mini.mk)
else ifeq ($(TARGET_USES_PICO_GAPPS),true)
$(call inherit-product, vendor/gms/gms_pico.mk)
else
$(call inherit-product, vendor/lineage/config/gms_full.mk)
endif

else ifeq ($(LOSP_GMS_TYPE),microg)

WITH_GMS := false

PRODUCT_PACKAGES += \
    GmsCore \
    GsfProxy \
    FakeStore

else ifeq ($(LOSP_GMS_TYPE),vanilla)

WITH_GMS := false

else

$(error Invalid LOSP_GMS_TYPE "$(LOSP_GMS_TYPE)"; expected gms, microg, or vanilla)

endif