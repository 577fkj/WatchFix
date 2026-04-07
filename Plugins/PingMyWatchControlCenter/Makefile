include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = PingMyWatchControlCenter
TOOL_NAME = WatchFixPingMyWatchHelper

$(BUNDLE_NAME)_FILES = PingMyWatchControlCenter.xm $(WATCHFIX_UTILS_FILES)
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc $(WATCHFIX_UTILS_CFLAGS)
$(BUNDLE_NAME)_BUNDLE_EXTENSION = bundle
$(BUNDLE_NAME)_INSTALL_PATH = /Library/ControlCenter/Bundles/
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = ControlCenterUIKit NanoRegistry
$(BUNDLE_NAME)_RESOURCE_DIRS = Resources

$(TOOL_NAME)_FILES = Helper/main.xm $(WATCHFIX_UTILS_FILES)
$(TOOL_NAME)_CFLAGS = -fobjc-arc $(WATCHFIX_UTILS_CFLAGS)
$(TOOL_NAME)_PRIVATE_FRAMEWORKS = NanoLeash
$(TOOL_NAME)_INSTALL_PATH = /Library/ControlCenter/Bundles/$(BUNDLE_NAME).bundle
$(TOOL_NAME)_CODESIGN_FLAGS = -S$(CURDIR)/Helper/Entitlements.plist

include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/tool.mk
