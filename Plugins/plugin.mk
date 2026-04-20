WATCHFIX_PLUGIN_MANIFEST ?= $(CURDIR)/manifest.plist
WATCHFIX_PLUGIN_KIND ?= library
WATCHFIX_PLUGIN_CFLAGS ?= -fobjc-arc $(WATCHFIX_UTILS_CFLAGS)
WATCHFIX_PLUGIN_LOGOSFLAGS ?= -c generator=MobileSubstrate
WATCHFIX_PLUGIN_STAGE_PATH = /Applications/WatchFix.app/PlugIns/$(PLUGIN_NAME).wffix
WATCHFIX_PROJECT_ROOT := $(abspath $(CURDIR)/../..)
WATCHFIX_PLUGIN_SHARED_FILES ?= $(patsubst $(WATCHFIX_PROJECT_ROOT)/%,../../%,$(WATCHFIX_UTILS_FILES))
WATCHFIX_PLUGIN_CONFIG_SHARED_FILE ?= $(patsubst $(WATCHFIX_PROJECT_ROOT)/%,../../%,$(WATCHFIX_PLUGIN_CONFIG_FILE))
WATCHFIX_PLUGIN_NEEDS_CONFIG ?= 0
WATCHFIX_PLUGIN_RESOURCE_DIRS ?=
WATCHFIX_PLUGIN_OPTIONAL_FILES ?=
WATCHFIX_PLUGIN_SOURCE_FILES ?= $(filter-out ./%PluginConfiguration.xm ./%PluginConfiguration.m,$(wildcard ./*.xm) $(wildcard ./*.m))
ifeq ($(WATCHFIX_PLUGIN_NEEDS_CONFIG),1)
WATCHFIX_PLUGIN_OPTIONAL_FILES += $(WATCHFIX_PLUGIN_CONFIG_SHARED_FILE)
endif
WATCHFIX_PLUGIN_FILES ?= $(WATCHFIX_PLUGIN_SOURCE_FILES) $(WATCHFIX_PLUGIN_SHARED_FILES) $(WATCHFIX_PLUGIN_OPTIONAL_FILES)
WATCHFIX_PLUGIN_INFO_GENERATOR := $(WATCHFIX_PROJECT_ROOT)/scripts/generate_plugin_info.py
WATCHFIX_PLUGIN_MINIMUM_OS_VERSION ?= 15.0

ifndef PLUGIN_NAME
$(error "PLUGIN_NAME must be defined before including Plugins/plugin.mk")
endif

ifndef WATCHFIX_PLUGIN_SHORT_VERSION
$(error "WATCHFIX_PLUGIN_SHORT_VERSION must be defined before including Plugins/plugin.mk")
endif

ifndef WATCHFIX_PLUGIN_VERSION
$(error "WATCHFIX_PLUGIN_VERSION must be defined before including Plugins/plugin.mk")
endif

ifeq ($(WATCHFIX_PLUGIN_KIND),library)
_THEOS_MAKE_PARALLEL_BUILDING = no
KEEP_LOGOS_INTERMEDIATES = 1
LIBRARY_NAME = $(PLUGIN_NAME)
$(LIBRARY_NAME)_FILES = $(WATCHFIX_PLUGIN_FILES)
$(LIBRARY_NAME)_CFLAGS = $(WATCHFIX_PLUGIN_CFLAGS)
$(LIBRARY_NAME)_FRAMEWORKS = $(WATCHFIX_PLUGIN_FRAMEWORKS)
$(LIBRARY_NAME)_PRIVATE_FRAMEWORKS = $(WATCHFIX_PLUGIN_PRIVATE_FRAMEWORKS)
$(LIBRARY_NAME)_INSTALL_PATH = $(WATCHFIX_PLUGIN_STAGE_PATH)
$(LIBRARY_NAME)_LOGOSFLAGS = $(WATCHFIX_PLUGIN_LOGOSFLAGS)

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/library.mk

internal-library-stage_::
	@test -f "$(WATCHFIX_PLUGIN_MANIFEST)" || (echo "Missing plugin manifest: $(WATCHFIX_PLUGIN_MANIFEST)" >&2; exit 1)
	@mkdir -p "$(THEOS_STAGING_DIR)$(WATCHFIX_PLUGIN_STAGE_PATH)"
	@echo "Generating Info.plist for plugin $(PLUGIN_NAME)..."
	@python3 "$(WATCHFIX_PLUGIN_INFO_GENERATOR)" --manifest "$(WATCHFIX_PLUGIN_MANIFEST)" --output "$(THEOS_STAGING_DIR)$(WATCHFIX_PLUGIN_STAGE_PATH)/Info.plist" --plugin-name "$(PLUGIN_NAME)" --plugin-kind "tweak" --package-scheme "$(THEOS_PACKAGE_SCHEME)" --executable "$(PLUGIN_NAME).dylib" --minimum-os-version "$(WATCHFIX_PLUGIN_MINIMUM_OS_VERSION)" --plugin-short-version "$(WATCHFIX_PLUGIN_SHORT_VERSION)" --plugin-version "$(WATCHFIX_PLUGIN_VERSION)"
	@set -e; \
		for resource_dir in $(WATCHFIX_PLUGIN_RESOURCE_DIRS); do \
			test -d "$$resource_dir" || (echo "Missing plugin resource dir: $$resource_dir" >&2; exit 1); \
			cp -R "$$resource_dir"/. "$(THEOS_STAGING_DIR)$(WATCHFIX_PLUGIN_STAGE_PATH)"/; \
		done
endif

ifeq ($(WATCHFIX_PLUGIN_KIND),bundle_with_tool)
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = $(PLUGIN_NAME)
TOOL_NAME = $(WATCHFIX_PLUGIN_TOOL_NAME)

$(BUNDLE_NAME)_FILES = $(WATCHFIX_PLUGIN_BUNDLE_FILES)
$(BUNDLE_NAME)_CFLAGS = $(WATCHFIX_PLUGIN_CFLAGS)
$(BUNDLE_NAME)_BUNDLE_EXTENSION = $(WATCHFIX_PLUGIN_BUNDLE_EXTENSION)
$(BUNDLE_NAME)_INSTALL_PATH = $(WATCHFIX_PLUGIN_STAGE_PATH)/Payload
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = $(WATCHFIX_PLUGIN_BUNDLE_PRIVATE_FRAMEWORKS)
$(BUNDLE_NAME)_RESOURCE_DIRS = $(WATCHFIX_PLUGIN_RESOURCE_DIRS)

$(TOOL_NAME)_FILES = $(WATCHFIX_PLUGIN_TOOL_FILES)
$(TOOL_NAME)_CFLAGS = $(WATCHFIX_PLUGIN_CFLAGS)
$(TOOL_NAME)_PRIVATE_FRAMEWORKS = $(WATCHFIX_PLUGIN_TOOL_PRIVATE_FRAMEWORKS)
$(TOOL_NAME)_INSTALL_PATH = $(WATCHFIX_PLUGIN_STAGE_PATH)/Payload/$(BUNDLE_NAME).bundle
$(TOOL_NAME)_CODESIGN_FLAGS = $(WATCHFIX_PLUGIN_TOOL_CODESIGN_FLAGS)

include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/tool.mk

internal-bundle-stage_:: internal-watchfix-plugin-metadata-stage
internal-tool-stage_:: internal-watchfix-plugin-metadata-stage

internal-watchfix-plugin-metadata-stage::
	@test -f "$(WATCHFIX_PLUGIN_MANIFEST)" || (echo "Missing plugin manifest: $(WATCHFIX_PLUGIN_MANIFEST)" >&2; exit 1)
	@mkdir -p "$(THEOS_STAGING_DIR)$(WATCHFIX_PLUGIN_STAGE_PATH)"
	@echo "Generating Info.plist for plugin $(PLUGIN_NAME)..."
	@python3 "$(WATCHFIX_PLUGIN_INFO_GENERATOR)" --manifest "$(WATCHFIX_PLUGIN_MANIFEST)" --output "$(THEOS_STAGING_DIR)$(WATCHFIX_PLUGIN_STAGE_PATH)/Info.plist" --plugin-name "$(PLUGIN_NAME)" --plugin-kind "bundle_with_tool" --package-scheme "$(THEOS_PACKAGE_SCHEME)" --executable "$(WATCHFIX_PLUGIN_TOOL_NAME)" --minimum-os-version "$(WATCHFIX_PLUGIN_MINIMUM_OS_VERSION)" --plugin-short-version "$(WATCHFIX_PLUGIN_SHORT_VERSION)" --plugin-version "$(WATCHFIX_PLUGIN_VERSION)"
	@set -e; \
		for resource_dir in $(WATCHFIX_PLUGIN_RESOURCE_DIRS); do \
			test -d "$$resource_dir" || continue; \
			for lproj in "$$resource_dir"/*.lproj; do \
				test -d "$$lproj" || continue; \
				cp -R "$$lproj" "$(THEOS_STAGING_DIR)$(WATCHFIX_PLUGIN_STAGE_PATH)"/; \
			done; \
		done
endif