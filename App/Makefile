include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = WatchFix
WATCHFIX_PLUGIN_CONFIGURATION_FILES = \
	$(foreach source,$(wildcard $(CURDIR)/../Plugins/*/*PluginConfiguration.xm),$(realpath $(source))) \
	$(foreach source,$(wildcard $(CURDIR)/../Plugins/*/*PluginConfiguration.m),$(realpath $(source)))

$(APPLICATION_NAME)_FILES = \
    $(wildcard ./App/*.swift) \
    $(wildcard ./Views/*.swift) \
    $(wildcard ./Store/*.swift) \
    $(wildcard ./Models/*.swift) \
    $(wildcard ./Bridge/*/*.xm) \
    $(wildcard ./Bridge/*/*.m) \
    $(WATCHFIX_PLUGIN_CONFIGURATION_FILES) \
    $(WATCHFIX_UTILS_FILES)
$(APPLICATION_NAME)_SWIFT_BRIDGING_HEADER = App-Bridging-Header.h
$(APPLICATION_NAME)_FRAMEWORKS = UIKit AVFoundation Combine
$(APPLICATION_NAME)_PRIVATE_FRAMEWORKS = NanoRegistry NanoSystemSettings SoftwareUpdateBridge VisualPairing PBBridgeSupport AppSupport RunningBoardServices Symbolication BridgePreferences
$(APPLICATION_NAME)_CFLAGS = -fobjc-arc -I$(CURDIR)/../Utils -I$(CURDIR)/Bridge -I$(CURDIR)/Bridge/Internal -I$(CURDIR)/Bridge/Plugin -I$(CURDIR)/Bridge/Scanner -I$(CURDIR)/Bridge/Watch
$(APPLICATION_NAME)_LDFLAGS = -lroothide
$(APPLICATION_NAME)_RESOURCE_DIRS = Resources
$(APPLICATION_NAME)_CODESIGN_FLAGS = -S$(CURDIR)/Entitlements.xml

include $(THEOS_MAKE_PATH)/application.mk
