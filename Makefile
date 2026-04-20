TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = WatchFix
THEOS_PACKAGE_SCHEME=roothide

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
THEOS_PACKAGE_DIR = packages/rootless
else ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
THEOS_PACKAGE_DIR = packages/roothide
else
$(error "Invalid THEOS_PACKAGE_SCHEME: $(THEOS_PACKAGE_SCHEME). Must be 'rootless' or 'roothide'.")
endif

THEOS_DEVICE_IP = 192.168.1.199
THEOS_DEVICE_PORT = 22

SUBPROJECTS = App Preferences $(patsubst %/Makefile,%,$(wildcard Plugins/*/Makefile))

export THEOS_PACKAGE_BASE_VERSION ?= $(shell sed -n 's/^Version:[[:space:]]*//p' $(CURDIR)/control | head -n 1)
export WATCHFIX_PLUGIN_PREFIX = WatchFix_
export WATCHFIX_PLUGIN_CONFIG_FILE = $(CURDIR)/Utils/PluginConfig.xm
export WATCHFIX_UTILS_FILES = $(filter-out $(WATCHFIX_PLUGIN_CONFIG_FILE),$(wildcard $(CURDIR)/Utils/*.xm))
export WATCHFIX_UTILS_CFLAGS = -I$(CURDIR)/Utils
WATCHFIX_LDID := $(firstword $(wildcard /usr/local/bin/ldid /opt/homebrew/bin/ldid))
ifneq ($(WATCHFIX_LDID),)
export TARGET_CODESIGN := $(WATCHFIX_LDID)
endif

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

WATCHFIX_BUILD_INFO_SCRIPT := $(CURDIR)/scripts/inject_build_info.py
WATCHFIX_BUILD_GIT_HASH = $(shell git -C "$(CURDIR)" rev-parse --short=12 HEAD 2>/dev/null)
WATCHFIX_BUILD_MACHINE_OS_BUILD = $(shell sw_vers -buildVersion 2>/dev/null)
WATCHFIX_THEOS_GIT_HASH = $(shell git -C "$(THEOS)" rev-parse --short=12 HEAD 2>/dev/null)
WATCHFIX_THEOS_BUILD_VERSION = $(shell plutil -extract version raw "$(THEOS)/package.json" 2>/dev/null)
WATCHFIX_PLATFORM_NAME = $(_THEOS_TARGET_PLATFORM_NAME)
WATCHFIX_PLATFORM_SDK_NAME = $(_THEOS_TARGET_PLATFORM_SDK_NAME)
WATCHFIX_SDK_VERSION = $(_THEOS_TARGET_SDK_VERSION)
WATCHFIX_MINIMUM_OS_VERSION = $(_THEOS_TARGET_OS_DEPLOYMENT_VERSION)
WATCHFIX_HAS_RELEASE_TAG = $(shell if git -C "$(CURDIR)" tag --points-at HEAD | grep -Fx "Release" >/dev/null 2>&1; then printf 1; else printf 0; fi)
WATCHFIX_BUILD_TYPE = $(if $(filter 1,$(FINALPACKAGE)),$(if $(filter 1,$(WATCHFIX_HAS_RELEASE_TAG)),Release,Test),Engineering)
WATCHFIX_BUILD_VISIBILITY = $(if $(filter 1,$(FINALPACKAGE)),Public,Private)
WATCHFIX_BUILD_VARIANT = $(THEOS_PACKAGE_SCHEME)
WATCHFIX_CONFIGURATION_PLATFORM = iphoneos

after-stage:: watchfix-inject-build-info

watchfix-inject-build-info:
	@python3 "$(WATCHFIX_BUILD_INFO_SCRIPT)" \
		--staging-dir "$(THEOS_STAGING_DIR)" \
		--short-version "$(THEOS_PACKAGE_BASE_VERSION)" \
		--git-hash "$(WATCHFIX_BUILD_GIT_HASH)" \
		--build-machine-os-build "$(WATCHFIX_BUILD_MACHINE_OS_BUILD)" \
		--theos-git-hash "$(WATCHFIX_THEOS_GIT_HASH)" \
		--theos-build-version "$(WATCHFIX_THEOS_BUILD_VERSION)" \
		--platform-name "$(WATCHFIX_PLATFORM_NAME)" \
		--sdk-version "$(WATCHFIX_SDK_VERSION)" \
		--supported-platform "$(WATCHFIX_PLATFORM_SDK_NAME)" \
		--minimum-os-version "$(WATCHFIX_MINIMUM_OS_VERSION)" \
		--device-family 1 \
		--required-device-capability arm64 \
		--build-type "$(WATCHFIX_BUILD_TYPE)" \
		--build-visibility "$(WATCHFIX_BUILD_VISIBILITY)" \
		--build-variant "$(WATCHFIX_BUILD_VARIANT)" \
		--configuration-platform "$(WATCHFIX_CONFIGURATION_PLATFORM)"

before-package::
	find $(THEOS_STAGING_DIR)/DEBIAN -type f \( -name 'preinst' -o -name 'postinst' -o -name 'extrainst_' -o -name 'prerm' -o -name 'postrm' \) -exec chmod 0755 {} \; 2>/dev/null || true
