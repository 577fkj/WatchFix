TARGET ?= iphone:clang:16.5:15.0
ARCHS ?= arm64 arm64e
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = WatchFixPrefs
$(BUNDLE_NAME)_FILES = WatchFixPrefs.xm
$(BUNDLE_NAME)_FRAMEWORKS = UIKit
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = Preferences
$(BUNDLE_NAME)_INSTALL_PATH = /Library/PreferenceBundles
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
