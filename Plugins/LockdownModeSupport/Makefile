PLUGIN_NAME = LockdownModeSupport
TWEAK_NAME = $(WATCHFIX_PLUGIN_PREFIX)$(PLUGIN_NAME)
$(TWEAK_NAME)_FILES = $(wildcard ./*.xm) $(WATCHFIX_UTILS_FILES)
$(TWEAK_NAME)_CFLAGS = -fobjc-arc $(WATCHFIX_UTILS_CFLAGS)

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
