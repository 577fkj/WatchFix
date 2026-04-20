#pragma once

#import "WatchAppSupport.h"
#import "utils.h"

__BEGIN_DECLS

// ---------------------------------------------------------------------------
// Shared re-entrancy guard — defined in WatchUtils.m,
// used by WatchScreenPatches.xm (ProgressView) and WatchResourceFix.xm
// (AttributeController) to prevent infinite recursion.
// ---------------------------------------------------------------------------
extern BOOL watchFixProgressAndControllerSizeGuard;

// ---------------------------------------------------------------------------
// Product-type parsing
// ---------------------------------------------------------------------------
WatchFixProductVersion *WatchFixParseProductVersion(NSString *productType);

// ---------------------------------------------------------------------------
// NanoRegistry / PBBridge size tables
// ---------------------------------------------------------------------------
WatchFixNRDeviceSize WatchFixLookupNanoRegistrySizeForParsedWatchVersion(WatchFixProductVersion *version);
WatchFixNRDeviceSize WatchFixNanoRegistryDeviceSizeForProductType(NSString *productType);
WatchFixPBBDeviceSize WatchFixPBBSizeForNRDeviceSize(WatchFixNRDeviceSize size);
WatchFixPBBDeviceSize WatchFixPBBridgeVariantSizeForProductType(NSString *productType);

// ---------------------------------------------------------------------------
// Size alias / display name
// ---------------------------------------------------------------------------
uint64_t WatchFixNormalizeSizeAlias(uint64_t size);
NSString *WatchFixDisplayNameForSize(uint64_t size);

// ---------------------------------------------------------------------------
// Material helpers (CLHS mapping, M/E overrides, fallback)
// ---------------------------------------------------------------------------
NSInteger WatchFixPatchedMaterialForCLHSValue(NSInteger clhs);
NSInteger WatchFixMMaterialOverrideValue(NSInteger material);
NSInteger WatchFixEMaterialOverrideValue(NSInteger material);
NSInteger WatchFixDefaultMaterialForSpecialSize(NSInteger size);

// ---------------------------------------------------------------------------
// OS compatibility check
// ---------------------------------------------------------------------------
BOOL WatchFixProductVersionIsNativelySupportedOnCurrentOS(WatchFixProductVersion *version);

// ---------------------------------------------------------------------------
// Localized variant size strings
// ---------------------------------------------------------------------------
NSString *WatchFixLocalizedVariantSizeForProductType(NSString *productType);
NSString *WatchFixShortLocalizedVariantSizeForProductType(NSString *productType);

// ---------------------------------------------------------------------------
// Resource string builder
// ---------------------------------------------------------------------------
NSString *WatchFixBuildResourceString(NSString *prefix, NSInteger material, NSInteger size, NSUInteger attrs);

// ---------------------------------------------------------------------------
// Internal size
// ---------------------------------------------------------------------------
NSInteger WatchFixInternalSizeForNRSizeAndBehavior(NSInteger nrSize, NSInteger behavior);

// ---------------------------------------------------------------------------
// Special-size lists and guards
// ---------------------------------------------------------------------------
NSArray *WatchFixSpecialSizesForCurrentOS(void);
BOOL WatchFixNeedsSpecialHandlingForSize(NSInteger size);
BOOL WatchFixMaterialOverrideAllowed(NSUInteger style, NSInteger size);

// ---------------------------------------------------------------------------
// Screen layout patches
// ---------------------------------------------------------------------------
CGSize WatchFixComputePatchedWatchScreenSize(NSInteger size);
CGFloat WatchFixComputePatchedWatchScreenOriginInset(NSInteger size, NSUInteger style);
CGRect WatchFixComputePatchedWatchScreenFrame(CGSize currentScreenImageSize, NSInteger size, NSUInteger style);

// ---------------------------------------------------------------------------
// Asset pull helpers
// ---------------------------------------------------------------------------
BOOL WatchFixResolveNormalizedSpecialSizeForAdvertisingName(NSString *advertisingName,
                                                            NSInteger *normalizedSize,
                                                            BOOL *didResolve);
void WatchFixPullDefaultMaterialAssetsForOneSpecialSize(NSInteger size,
                                                        void (^completion)(NSInteger result));
void WatchFixPullDefaultMaterialAssetsForAdvertisingName(NSString *advertisingName,
                                                         void (^completion)(void));
void WatchFixPullDefaultMaterialAssetsForAllSpecialSizes(void);

// ---------------------------------------------------------------------------
// Alert messages
// ---------------------------------------------------------------------------
NSString *WatchFixUnsupportedUpdateMessage(void);
NSString *WatchFixPairingNotPossibleMessage(void);

// ---------------------------------------------------------------------------
// Per-module hook initializers (called from InitWatchAppSupportHooks)
// ---------------------------------------------------------------------------
void InitWatchResourceFixHooks(void);
void InitWatchScreenPatchHooks(void);
void InitWatchAssetsPullHooks(void);
void InitWatchAlertPatchHooks(void);

__END_DECLS
