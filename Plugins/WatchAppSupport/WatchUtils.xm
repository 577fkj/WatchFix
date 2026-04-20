#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "WatchUtils_internal.h"
#import "WatchDeviceDatabase.h"
#import "utils.h"

// ---------------------------------------------------------------------------
// Shared re-entrancy guard
// ---------------------------------------------------------------------------
BOOL watchFixProgressAndControllerSizeGuard = YES;

// ---------------------------------------------------------------------------
// WatchFixProductVersion (model object — implementation lives here)
// ---------------------------------------------------------------------------
@implementation WatchFixProductVersion
@end

// ---------------------------------------------------------------------------
// Product-type parsing
// ---------------------------------------------------------------------------
WatchFixProductVersion *WatchFixParseProductVersion(NSString *productType) {
    if (productType.length == 0) {
        return NULL;
    }

    static NSRegularExpression *regex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"^([A-Za-z]+)(\\d+),(\\d+)$"
                                                          options:0
                                                            error:nil];
    });

    NSTextCheckingResult *match = [regex firstMatchInString:productType
                                                    options:0
                                                      range:NSMakeRange(0, productType.length)];
    if (!match || match.numberOfRanges != 4) {
        return NULL;
    }

    WatchFixProductVersion *version = [[WatchFixProductVersion alloc] init];
    version.familyName = [productType substringWithRange:[match rangeAtIndex:1]];
    version.major = [[productType substringWithRange:[match rangeAtIndex:2]] integerValue];
    version.minor = [[productType substringWithRange:[match rangeAtIndex:3]] integerValue];
    return version;
}

// ---------------------------------------------------------------------------
// NanoRegistry size lookup
// ---------------------------------------------------------------------------
WatchFixNRDeviceSize WatchFixLookupNanoRegistrySizeForParsedWatchVersion(WatchFixProductVersion *version) {
    if (!version || version.familyName.length == 0 || ![version.familyName isEqualToString:@"Watch"]) {
        return 0;
    }
    return (WatchFixNRDeviceSize)WatchDeviceNRSizeForWatchMajorMinor(version.major, version.minor);
}

WatchFixNRDeviceSize WatchFixNanoRegistryDeviceSizeForProductType(NSString *productType) {
    WatchFixProductVersion *version = WatchFixParseProductVersion(productType);
    if (!version) {
        return 0;
    }
    return WatchFixLookupNanoRegistrySizeForParsedWatchVersion(version);
}

// ---------------------------------------------------------------------------
// PBBridge size mapping
// ---------------------------------------------------------------------------
WatchFixPBBDeviceSize WatchFixPBBSizeForNRDeviceSize(WatchFixNRDeviceSize size) {
    return (WatchFixPBBDeviceSize)WatchDeviceBridgeSizeForNRSize(size);
}

WatchFixPBBDeviceSize WatchFixPBBridgeVariantSizeForProductType(NSString *productType) {
    WatchFixNRDeviceSize size = WatchFixNanoRegistryDeviceSizeForProductType(productType);
    return WatchFixPBBSizeForNRDeviceSize(size);
}

// ---------------------------------------------------------------------------
// Size alias normalization
// ---------------------------------------------------------------------------
uint64_t WatchFixNormalizeSizeAlias(uint64_t size) {
    return (uint64_t)WatchDeviceNormalizeBridgeSize((NSInteger)size);
}

NSString *WatchFixDisplayNameForSize(uint64_t size) {
    return WatchDeviceDisplayNameForBridgeSize(WatchDeviceNormalizeBridgeSize((NSInteger)size));
}

// ---------------------------------------------------------------------------
// Material helpers
// ---------------------------------------------------------------------------
NSInteger WatchFixPatchedMaterialForCLHSValue(NSInteger clhs) {
    return WatchDevicePatchedMaterialForCLHSValue(clhs);
}

NSInteger WatchFixMMaterialOverrideValue(NSInteger material) {
    return WatchDeviceMMaterialOverrideValue(material);
}

NSInteger WatchFixEMaterialOverrideValue(NSInteger material) {
    return WatchDeviceEMaterialOverrideValue(material);
}

NSInteger WatchFixDefaultMaterialForSpecialSize(NSInteger size) {
    NSInteger normalizedSize = WatchDeviceNormalizeBridgeSize(size);
    NSInteger lookupSize = normalizedSize > 0 ? normalizedSize : size;
    NSInteger material = WatchDeviceFallbackMaterialForBridgeSize(lookupSize);
    return material > 0 ? material : 3;
}

// ---------------------------------------------------------------------------
// OS compatibility
// ---------------------------------------------------------------------------
BOOL WatchFixProductVersionIsNativelySupportedOnCurrentOS(WatchFixProductVersion *version) {
    if (!version || version.familyName.length == 0 || ![version.familyName isEqualToString:@"Watch"]) {
        return NO;
    }

    NSInteger ceilingMajor = 0;
    NSInteger ceilingMinor = 0;
    switch (IOSMajorVersion()) {
        case 18: ceilingMajor = 7; ceilingMinor = 11; break;
        case 17: ceilingMajor = 7; ceilingMinor = 5;  break;
        case 16: ceilingMajor = 6; ceilingMinor = 18; break;
        case 15: ceilingMajor = 6; ceilingMinor = 9;  break;
        case 14: ceilingMajor = 6; ceilingMinor = 4;  break;
        case 13: ceilingMajor = 5; ceilingMinor = 4;  break;
        default: return YES;
    }

    if (version.major != ceilingMajor) {
        return version.major < ceilingMajor;
    }
    return version.minor <= ceilingMinor;
}

// ---------------------------------------------------------------------------
// Localized variant size strings
// ---------------------------------------------------------------------------
NSString *WatchFixLocalizedVariantSizeForProductType(NSString *productType) {
    WatchFixProductVersion *version = WatchFixParseProductVersion(productType);
    if (!version) {
        return nil;
    }

    WatchFixNRDeviceSize nrSize = WatchFixLookupNanoRegistrySizeForParsedWatchVersion(version);
    WatchFixPBBDeviceSize pbbSize = WatchFixPBBSizeForNRDeviceSize(nrSize);
    if (!pbbSize) {
        return nil;
    }

    NSString *displayName = WatchFixDisplayNameForSize(pbbSize);
    NSString *key = [[displayName uppercaseString] stringByAppendingString:@"_VARIANT"];
    Class watchViewClass = objc_lookUpClass("BPSWatchView");
    NSBundle *bundle = watchViewClass ? [NSBundle bundleForClass:watchViewClass] : [NSBundle mainBundle];
    return [bundle localizedStringForKey:key value:nil table:nil];
}

NSString *WatchFixShortLocalizedVariantSizeForProductType(NSString *productType) {
    WatchFixProductVersion *version = WatchFixParseProductVersion(productType);
    if (!version) {
        return nil;
    }

    WatchFixNRDeviceSize nrSize = WatchFixLookupNanoRegistrySizeForParsedWatchVersion(version);
    WatchFixPBBDeviceSize pbbSize = WatchFixPBBSizeForNRDeviceSize(nrSize);
    if (!pbbSize) {
        return nil;
    }

    NSString *displayName = WatchFixDisplayNameForSize(pbbSize);
    NSString *key = [[displayName uppercaseString] stringByAppendingString:@"_VARIANT_SHORT"];
    Class watchViewClass = objc_lookUpClass("BPSWatchView");
    NSBundle *bundle = watchViewClass ? [NSBundle bundleForClass:watchViewClass] : [NSBundle mainBundle];
    return [bundle localizedStringForKey:key value:nil table:nil];
}

// ---------------------------------------------------------------------------
// Resource string builder
// ---------------------------------------------------------------------------
NSString *WatchFixBuildResourceString(NSString *prefix, NSInteger material, NSInteger size, NSUInteger attrs) {
    if ([prefix length] == 0) {
        return nil;
    }

    NSMutableArray *parts = [NSMutableArray array];
    [parts addObject:prefix];

    if (material == 0 || material > 38) {
        material = 3;
    }

    if ((attrs & 0x2) != 0) {
        NSInteger mappedMaterial = WatchFixMMaterialOverrideValue(material);
        if (!mappedMaterial) {
            return nil;
        }
        material = mappedMaterial;
        [parts addObject:[NSString stringWithFormat:@"%ld", (long)mappedMaterial]];
        [parts addObject:@"M"];
    } else if ((attrs & 0x1) != 0) {
        NSInteger mappedMaterial = WatchFixEMaterialOverrideValue(material);
        if (!mappedMaterial) {
            return nil;
        }
        material = mappedMaterial;
        [parts addObject:[NSString stringWithFormat:@"%ld", (long)mappedMaterial]];
        [parts addObject:@"E"];
    }

    if ((attrs & 0x4) != 0) {
        NSInteger normalizedSize = size;
        if (normalizedSize == 0 || normalizedSize > 21) {
            normalizedSize = 7;
        }
        [parts addObject:[[WatchFixDisplayNameForSize((uint64_t)normalizedSize) lowercaseString] copy]];
    }

    return [parts componentsJoinedByString:@"-"];
}

// ---------------------------------------------------------------------------
// Internal size (behavior-dependent)
// ---------------------------------------------------------------------------
NSInteger WatchFixInternalSizeForNRSizeAndBehavior(NSInteger nrSize, NSInteger behavior) {
    return WatchDeviceInternalSizeForNRSizeAndBehavior(nrSize, behavior);
}

// ---------------------------------------------------------------------------
// Special-size lists and guards
// ---------------------------------------------------------------------------
NSArray *WatchFixSpecialSizesForCurrentOS(void) {
    NSMutableArray *sizes = [NSMutableArray array];
    NSInteger osMajor = IOSMajorVersion();
    switch (osMajor) {
        case 17:
        case 16:
            [sizes addObject:[NSNumber numberWithInteger:20]];
            [sizes addObject:[NSNumber numberWithInteger:21]];
            break;
        case 15:
            [sizes addObject:[NSNumber numberWithInteger:19]];
            [sizes addObject:[NSNumber numberWithInteger:20]];
            [sizes addObject:[NSNumber numberWithInteger:21]];
            break;
        case 14:
        case 13:
            [sizes addObject:[NSNumber numberWithInteger:14]];
            [sizes addObject:[NSNumber numberWithInteger:13]];
            [sizes addObject:[NSNumber numberWithInteger:19]];
            [sizes addObject:[NSNumber numberWithInteger:20]];
            [sizes addObject:[NSNumber numberWithInteger:21]];
            break;
        default:
            break;
    }
    return [sizes copy];
}

BOOL WatchFixNeedsSpecialHandlingForSize(NSInteger size) {
    NSInteger normalizedSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)size);
    NSInteger targetSize = normalizedSize > 0 ? normalizedSize : size;
    for (NSNumber *candidate in WatchFixSpecialSizesForCurrentOS()) {
        if ([candidate integerValue] == targetSize) {
            return YES;
        }
    }
    return NO;
}

BOOL WatchFixMaterialOverrideAllowed(NSUInteger style, NSInteger size) {
    NSInteger normalizedSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)size);
    NSInteger targetSize = normalizedSize > 0 ? normalizedSize : size;
    if (!WatchFixNeedsSpecialHandlingForSize(targetSize)) {
        return YES;
    }
    switch (style) {
        case 2: case 4: case 8:
            return NO;
        default:
            return YES;
    }
}

// ---------------------------------------------------------------------------
// Screen layout patch computations
// ---------------------------------------------------------------------------
CGSize WatchFixComputePatchedWatchScreenSize(NSInteger size) {
    NSInteger normalizedSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)size);
    if (!WatchFixNeedsSpecialHandlingForSize(normalizedSize)) {
        return CGSizeZero;
    }

    BOOL is3x = ([[UIScreen mainScreen] scale] > 2.0);
    switch (normalizedSize) {
        case 14: return is3x ? CGSizeMake(78.0, 96.0)  : CGSizeMake(71.0, 87.0);
        case 13: return is3x ? CGSizeMake(85.0, 105.0) : CGSizeMake(77.0, 95.0);
        case 19: return is3x ? CGSizeMake(81.0, 100.0) : CGSizeMake(73.0, 90.0);
        case 20: return is3x ? CGSizeMake(78.0, 96.0)  : CGSizeMake(71.0, 86.0);
        case 21: return is3x ? CGSizeMake(89.0, 106.0) : CGSizeMake(80.0, 94.5);
        default: return CGSizeZero;
    }
}

CGFloat WatchFixComputePatchedWatchScreenOriginInset(NSInteger size, NSUInteger style) {
    NSInteger normalizedSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)size);
    if (!WatchFixNeedsSpecialHandlingForSize(normalizedSize)) {
        return 0.0;
    }

    BOOL is3x = ([[UIScreen mainScreen] scale] > 2.0);
    switch (style) {
        case 2:
            switch (normalizedSize) {
                case 13: case 19:            return is3x ? 20.5 : 19.5;
                case 14: case 20: case 21:   return is3x ? 21.0 : 20.5;
                default:                     return 0.0;
            }
        case 3:
            switch (normalizedSize) {
                case 13:                     return is3x ? 12.5 : 11.0;
                case 14: case 20: case 21:   return is3x ? 11.0 : 10.0;
                case 19:                     return is3x ? 14.0 : 12.0;
                default:                     return 0.0;
            }
        case 4:
            switch (normalizedSize) {
                case 13: case 19:            return is3x ? 37.5 : 30.0;
                case 14: case 20: case 21:   return is3x ? 42.0 : 40.0;
                default:                     return 0.0;
            }
        case 5:
            return 0.0;
        case 6:
            switch (normalizedSize) {
                case 13: case 19:            return 7.25;
                case 14:                     return 7.5;
                case 20: case 21:            return 40.0;
                default:                     return 0.0;
            }
        case 7:
            switch (normalizedSize) {
                case 13:                     return is3x ? 12.5 : 11.0;
                case 14:                     return is3x ? 11.0 : 10.0;
                case 19:                     return is3x ? 14.0 : 12.0;
                case 20:                     return is3x ? 11.0 : 9.0;
                case 21:                     return is3x ? 10.0 : 9.0;
                default:                     return 0.0;
            }
        default:
            return 0.0;
    }
}

CGRect WatchFixComputePatchedWatchScreenFrame(CGSize currentScreenImageSize, NSInteger size, NSUInteger style) {
    CGFloat inset = WatchFixComputePatchedWatchScreenOriginInset(size, style);
    if (inset == 0.0) {
        return CGRectZero;
    }
    return CGRectMake(inset, inset, currentScreenImageSize.width, currentScreenImageSize.height);
}

// ---------------------------------------------------------------------------
// Asset pull helpers
// ---------------------------------------------------------------------------
BOOL WatchFixResolveNormalizedSpecialSizeForAdvertisingName(NSString *advertisingName,
                                                            NSInteger *normalizedSize,
                                                            BOOL *didResolve) {
    if (didResolve) {
        *didResolve = NO;
    }
    if (normalizedSize) {
        *normalizedSize = 0;
    }

    NSDictionary *info = PBAdvertisingInfoFromPayload(advertisingName);
    NSString *sizeKey = PBBridgeAdvertisingSizeKey;
    if (![info isKindOfClass:[NSDictionary class]] || [sizeKey length] == 0) {
        return NO;
    }

    id rawSizeObject = [info objectForKey:sizeKey];
    if (![rawSizeObject isKindOfClass:[NSNumber class]]) {
        if (didResolve) {
            *didResolve = YES;
        }
        return YES;
    }

    NSInteger candidateSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)[(NSNumber *)rawSizeObject integerValue]);
    if (normalizedSize) {
        *normalizedSize = candidateSize;
    }
    if (didResolve) {
        *didResolve = YES;
    }
    return YES;
}

void WatchFixPullDefaultMaterialAssetsForOneSpecialSize(NSInteger size,
                                                        void (^completion)(NSInteger result)) {
    NSInteger normalizedSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)size);
    NSInteger targetSize = normalizedSize > 0 ? normalizedSize : size;
    Log(@"WatchAppSupport PullAssetsForOneSpecialSize: size=%ld normalizedSize=%ld targetSize=%ld needsSpecial=%d",
        (long)size, (long)normalizedSize, (long)targetSize, WatchFixNeedsSpecialHandlingForSize(targetSize));
    if (!WatchFixNeedsSpecialHandlingForSize(targetSize)) {
        if (completion) {
            completion(1);
        }
        return;
    }

    PBBridgeAssetsManager *manager = [[PBBridgeAssetsManager alloc] init];
    if (!manager) {
        if (completion) {
            completion(0);
        }
        return;
    }

    NSInteger material = WatchFixDefaultMaterialForSpecialSize(targetSize);
    Log(@"WatchAppSupport PullAssetsForOneSpecialSize: pulling material=%ld size=%ld",
        (long)material, (long)targetSize);

    Log(@"WatchAppSupport PullAssetsForOneSpecialSize: using legacy selector");
    [manager beginPullingAssetsForDeviceMaterial:material
                                            size:targetSize
                                        branding:nil
                                        completion:^(NSInteger result) {
        Log(@"WatchAppSupport PullAssetsForOneSpecialSize: completion result=%ld for size=%ld",
            (long)result, (long)targetSize);
        if (completion) {
            completion(result);
        }
    }];
    return;
}

void WatchFixPullDefaultMaterialAssetsForAdvertisingName(NSString *advertisingName,
                                                         void (^completion)(void)) {
    BOOL didResolve = NO;
    NSInteger normalizedSize = 0;
    WatchFixResolveNormalizedSpecialSizeForAdvertisingName(advertisingName, &normalizedSize, &didResolve);
    if (!didResolve || !normalizedSize || !WatchFixNeedsSpecialHandlingForSize(normalizedSize)) {
        if (completion) {
            completion();
        }
        return;
    }

    WatchFixPullDefaultMaterialAssetsForOneSpecialSize(normalizedSize, ^(__unused NSInteger result) {
        if (completion) {
            completion();
        }
    });
}

void WatchFixPullDefaultMaterialAssetsForAllSpecialSizes(void) {
    NSArray *specialSizes = WatchFixSpecialSizesForCurrentOS();
    if ([specialSizes count] == 0) {
        return;
    }

    for (NSNumber *size in specialSizes) {
        WatchFixPullDefaultMaterialAssetsForOneSpecialSize([size integerValue], nil);
    }
}

// ---------------------------------------------------------------------------
// Alert messages
// ---------------------------------------------------------------------------
NSString *WatchFixUnsupportedUpdateMessage(void) {
    return @"A software update is available for your Apple Watch, but it is not compatible with the installed version of WatchFix Pairing Support\n\nCheck for an updated version of WatchFix (or update iOS instead), then try installing this update again";
}

NSString *WatchFixPairingNotPossibleMessage(void) {
    return @"The currently installed version of WatchFix Pairing Support does not support the version of watchOS on this Apple Watch.\n\nUpdate iOS or WatchFix to pair this Apple Watch";
}
