TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
# INSTALL_TARGET_PROCESSES = apsd installd appconduitd com.apple.MobileInstallationHelperService
THEOS_PACKAGE_SCHEME=roothide

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
THEOS_PACKAGE_DIR = packages/rootless
else ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
THEOS_PACKAGE_DIR = packages/roothide
else
$(error "Invalid THEOS_PACKAGE_SCHEME: $(THEOS_PACKAGE_SCHEME). Must be 'rootless' or 'roothide'.")
endif

THEOS_DEVICE_IP = 192.168.1.110
THEOS_DEVICE_PORT = 22

SUBPROJECTS = $(patsubst %/Makefile,%,$(wildcard Plugins/*/Makefile))

export WATCHFIX_PLUGIN_PREFIX = WatchFix_
export WATCHFIX_UTILS_FILES = $(wildcard $(CURDIR)/Utils/*.xm)
export WATCHFIX_UTILS_CFLAGS = -I$(CURDIR)/Utils

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

before-package::
	find $(THEOS_STAGING_DIR)/DEBIAN -type f \( -name 'preinst' -o -name 'postinst' -o -name 'extrainst_' -o -name 'prerm' -o -name 'postrm' \) -exec chmod 0755 {} \; 2>/dev/null || true
