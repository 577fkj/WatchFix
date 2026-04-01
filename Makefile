TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
# INSTALL_TARGET_PROCESSES = apsd installd appconduitd com.apple.MobileInstallationHelperService
THEOS_PACKAGE_SCHEME=roothide

THEOS_DEVICE_IP = 192.168.1.109
THEOS_DEVICE_PORT = 22

TWEAK_NAME = WatchFix
$(TWEAK_NAME)_FILES = $(shell find src \( -name '*.m' -o -name '*.xm' -o -name '*.x' -o -name '*.xi' \))
$(TWEAK_NAME)_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
