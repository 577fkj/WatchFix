// 各功能模块：
//   WatchUtils.m          — 纯工具函数（无 hook）
//   WatchResourceFix.xm   — 材质/资源字符串/RemoteImage/AttributeController
//   WatchScreenPatches.xm — 屏幕尺寸布局/WatchView/ProgressView/SetupDeviceSync
//   WatchAssetsPull.xm    — 资产拉取/AssetsManager/SetupProxy
//   WatchAlertPatches.xm  — 软件更新弹窗/配对失败提示

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "WatchUtils_internal.h"

// ---------------------------------------------------------------------------
// Function-level hooks
// ---------------------------------------------------------------------------

%group WatchAppSupportFunctionHooks

%hookf(WatchFixNRDeviceSize, NRDeviceSizeForProductType, id productType) {
    WatchFixNRDeviceSize value = WatchFixNanoRegistryDeviceSizeForProductType(productType);
    if (!value) {
        value = %orig;
    }
    return value;
}

%hookf(WatchFixPBBDeviceSize, BPSVariantSizeForProductType, id productType) {
    WatchFixPBBDeviceSize value = WatchFixPBBridgeVariantSizeForProductType(productType);
    if (!value) {
        value = %orig;
    }
    return value;
}

%hookf(NSString *, BPSLocalizedVariantSizeForProductType, id productType) {
    NSString *value = WatchFixLocalizedVariantSizeForProductType(productType);
    if (!value) {
        value = %orig;
    }
    return value;
}

%hookf(NSString *, BPSShortLocalizedVariantSizeForProductType, id productType) {
    NSString *value = WatchFixShortLocalizedVariantSizeForProductType(productType);
    if (!value) {
        value = %orig;
    }
    return value;
}

%hookf(WatchFixPBBDeviceSize, PBVariantSizeForProductType, id productType) {
    WatchFixPBBDeviceSize value = WatchFixPBBridgeVariantSizeForProductType(productType);
    if (!value) {
        value = %orig;
    }
    return value;
}

%end

// ---------------------------------------------------------------------------
// Unified hook initializer
// ---------------------------------------------------------------------------
void InitWatchAppSupportHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Log(@"Initializing WatchAppSupport hooks...");

        InitWatchAlertPatchHooks();
        InitWatchAssetsPullHooks();
        InitWatchScreenPatchHooks();
        InitWatchResourceFixHooks();

        %init(WatchAppSupportFunctionHooks);
        Log(@"WatchAppSupport function hooks initialized");

        const char *programName = getprogname();
        if (!programName || !is_equal(programName, "SharingViewService")) {
            WatchFixPullDefaultMaterialAssetsForAllSpecialSizes();
        }
    });
}

// ---------------------------------------------------------------------------
// Constructor
// ---------------------------------------------------------------------------
%ctor {
    const char *progname = getprogname();
    if (!progname) {
        return;
    }
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    const char *bundleIDCString = [bundleID UTF8String];
    Log(@"Bundle ID   : %@", bundleID);
    Log(@"Program Name: %@", StringFromCString(progname));
    if (is_equal(bundleIDCString, "com.apple.Bridge") ||
        is_equal(bundleIDCString, "com.apple.SharingViewService") ||
        is_equal(progname, "SharingViewService")) {
        Log(@"Initializing WatchAppSupport...");
        InitWatchAppSupportHooks();
    }
}
