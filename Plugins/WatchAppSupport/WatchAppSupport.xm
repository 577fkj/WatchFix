#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>
#include <substrate.h>
#include "WatchAppSupport.h"
#include "utils.h"

static BOOL watchFixProgressAndControllerSizeGuard = YES;

static BOOL WatchFixParseProductVersion(NSString *productType, WatchFixProductVersion *version) {
    if (!productType || !version) {
        return NO;
    }

    const char *s = [productType UTF8String];
    if (!s) {
        return NO;
    }

    NSUInteger familyEnd = 0;
    while (s[familyEnd] &&
           ((s[familyEnd] >= 'A' && s[familyEnd] <= 'Z') ||
            (s[familyEnd] >= 'a' && s[familyEnd] <= 'z'))) {
        familyEnd++;
    }
    if (familyEnd == 0) {
        return NO;
    }

    if (s[familyEnd] < '0' || s[familyEnd] > '9') {
        return NO;
    }
    NSInteger major = 0;
    NSUInteger pos = familyEnd;
    while (s[pos] >= '0' && s[pos] <= '9') {
        major = major * 10 + (s[pos] - '0');
        pos++;
    }
    if (s[pos] != ',') {
        return NO;
    }
    pos++;

    if (s[pos] < '0' || s[pos] > '9') {
        return NO;
    }
    NSInteger minor = 0;
    while (s[pos] >= '0' && s[pos] <= '9') {
        minor = minor * 10 + (s[pos] - '0');
        pos++;
    }
    if (s[pos] != '\0') {
        return NO;
    }

    if (familyEnd >= sizeof(version->familyName)) {
        return NO;
    }
    strncpy(version->familyName, s, familyEnd);
    version->familyName[familyEnd] = '\0';
    version->major = major;
    version->minor = minor;
    return YES;
}

static WatchFixNRDeviceSize WatchFixLookupNanoRegistrySizeForParsedWatchVersion(const WatchFixProductVersion *version) {
    if (!version || is_empty(version->familyName) || !is_equal(version->familyName, "Watch")) {
        return 0;
    }

    switch (version->major) {
        case 7:
            switch (version->minor) {
                case 1:
                case 3:
                    return 5;
                case 2:
                case 4:
                    return 6;
                case 5:
                    return 7;
                case 8:
                case 10:
                    return 8;
                case 9:
                case 11:
                    return 9;
                default:
                    return 0;
            }
        case 6:
            switch (version->minor) {
                case 1:
                case 3:
                case 10:
                case 12:
                    return 4;
                case 2:
                case 4:
                case 11:
                case 13:
                    return 3;
                case 6:
                case 8:
                case 14:
                case 16:
                    return 5;
                case 7:
                case 9:
                case 15:
                case 17:
                    return 6;
                case 18:
                    return 7;
                default:
                    return 0;
            }
        case 5:
            switch (version->minor) {
                case 9:
                case 11:
                    return 4;
                case 10:
                case 12:
                    return 3;
                default:
                    return 0;
            }
        default:
            return 0;
    }
}

static WatchFixNRDeviceSize WatchFixNanoRegistryDeviceSizeForProductType(NSString *productType) {
    WatchFixProductVersion version;
    memset(&version, 0, sizeof(version));
    if (!WatchFixParseProductVersion(productType, &version)) {
        return 0;
    }
    return WatchFixLookupNanoRegistrySizeForParsedWatchVersion(&version);
}

static WatchFixPBBDeviceSize WatchFixPBBSizeForNRDeviceSize(WatchFixNRDeviceSize size) {
    switch (size) {
        case 1:
            return 1;
        case 2:
            return 2;
        case 3:
            return 7;
        case 4:
            return 8;
        case 5:
            return 14;
        case 6:
            return 13;
        case 7:
            return 19;
        case 8:
            return 20;
        case 9:
            return 21;
        default:
            return 0;
    }
}

static WatchFixPBBDeviceSize WatchFixPBBridgeVariantSizeForProductType(NSString *productType) {
    WatchFixNRDeviceSize size = WatchFixNanoRegistryDeviceSizeForProductType(productType);
    return WatchFixPBBSizeForNRDeviceSize(size);
}

static uint64_t WatchFixNormalizeSizeAlias(uint64_t size) {
    switch (size) {
        case 1:
        case 3:
        case 5:
            return 1;
        case 2:
        case 4:
        case 6:
            return 2;
        case 7:
        case 9:
        case 11:
            return 7;
        case 8:
        case 10:
        case 12:
            return 8;
        case 13:
        case 15:
        case 17:
            return 13;
        case 14:
        case 16:
        case 18:
            return 14;
        case 19:
        case 24:
            return 19;
        case 20:
        case 22:
            return 20;
        case 21:
        case 23:
            return 21;
        default:
            return 0;
    }
}

static NSString *WatchFixDisplayNameForSize(uint64_t size) {
    uint64_t normalizedSize = WatchFixNormalizeSizeAlias(size);
    switch (normalizedSize) {
        case 1:
            return NSSTR("Regular");
        case 2:
            return NSSTR("Compact");
        case 7:
            return NSSTR("448h");
        case 8:
            return NSSTR("394h");
        case 13:
            return NSSTR("484h");
        case 14:
            return NSSTR("430h");
        case 19:
            return NSSTR("502h");
        case 20:
            return NSSTR("446h");
        case 21:
            return NSSTR("496h");
        default:
            return NSSTR("Generic");
    }
}

static NSInteger WatchFixPatchedMaterialForCLHSValue(NSInteger clhs) {
    switch (clhs) {
        case 18:
            return 16;
        case 22:
            return 17;
        case 23:
            return 23;
        case 26:
            return 18;
        case 27:
            return 19;
        case 31:
            return 21;
        case 32:
            return 22;
        case 34:
            return 24;
        case 36:
            return 25;
        case 38:
            return 38;
        case 39:
            return 29;
        default:
            return 0;
    }
}

static NSInteger WatchFixMMaterialOverrideValue(NSInteger material) {
    switch (material) {
        case 38:
            return 26;
        case 29:
            return 27;
        default:
            return 0;
    }
}

static NSInteger WatchFixEMaterialOverrideValue(NSInteger material) {
    switch (material) {
        case 5:
        case 7:
        case 13:
        case 17:
            return 1;
        case 10:
        case 11:
        case 14:
        case 15:
        case 23:
        case 25:
        case 29:
        case 38:
            return 3;
        default:
            return 0;
    }
}

static NSInteger WatchFixDefaultMaterialForSpecialSize(NSInteger size) {
    switch (WatchFixNormalizeSizeAlias((uint64_t)size)) {
        case 19:
            return 14;
        case 20:
        case 21:
            return 22;
        default:
            return 3;
    }
}

static BOOL WatchFixProductVersionIsNativelySupportedOnCurrentOS(const WatchFixProductVersion *version) {
    if (!version || is_empty(version->familyName) || !is_equal(version->familyName, "Watch")) {
        return NO;
    }

    NSInteger ceilingMajor = 0;
    NSInteger ceilingMinor = 0;
    switch ([[NSProcessInfo processInfo] operatingSystemVersion].majorVersion) {
        case 18:
            ceilingMajor = 7;
            ceilingMinor = 11;
            break;
        case 17:
            ceilingMajor = 7;
            ceilingMinor = 5;
            break;
        case 16:
            ceilingMajor = 6;
            ceilingMinor = 18;
            break;
        case 15:
            ceilingMajor = 6;
            ceilingMinor = 9;
            break;
        case 14:
            ceilingMajor = 6;
            ceilingMinor = 4;
            break;
        case 13:
            ceilingMajor = 5;
            ceilingMinor = 4;
            break;
        default:
            return YES;
    }

    if (version->major != ceilingMajor) {
        return version->major < ceilingMajor;
    }

    return version->minor <= ceilingMinor;
}

static NSString *WatchFixLocalizedVariantSizeForProductType(NSString *productType) {
    WatchFixProductVersion version;
    memset(&version, 0, sizeof(version));
    if (!WatchFixParseProductVersion(productType, &version)) {
        return nil;
    }

    WatchFixNRDeviceSize nrSize = WatchFixLookupNanoRegistrySizeForParsedWatchVersion(&version);
    WatchFixPBBDeviceSize pbbSize = WatchFixPBBSizeForNRDeviceSize(nrSize);
    if (!pbbSize) {
        return nil;
    }

    NSString *displayName = WatchFixDisplayNameForSize(pbbSize);
    NSString *key = [[displayName uppercaseString] stringByAppendingString:NSSTR("_VARIANT")];
    Class watchViewClass = objc_lookUpClass("BPSWatchView");
    NSBundle *bundle = watchViewClass ? [NSBundle bundleForClass:watchViewClass] : [NSBundle mainBundle];
    return [bundle localizedStringForKey:key value:nil table:nil];
}

static NSString *WatchFixShortLocalizedVariantSizeForProductType(NSString *productType) {
    WatchFixProductVersion version;
    memset(&version, 0, sizeof(version));
    if (!WatchFixParseProductVersion(productType, &version)) {
        return nil;
    }

    WatchFixNRDeviceSize nrSize = WatchFixLookupNanoRegistrySizeForParsedWatchVersion(&version);
    WatchFixPBBDeviceSize pbbSize = WatchFixPBBSizeForNRDeviceSize(nrSize);
    if (!pbbSize) {
        return nil;
    }

    NSString *displayName = WatchFixDisplayNameForSize(pbbSize);
    NSString *key = [[displayName uppercaseString] stringByAppendingString:NSSTR("_VARIANT_SHORT")];
    Class watchViewClass = objc_lookUpClass("BPSWatchView");
    NSBundle *bundle = watchViewClass ? [NSBundle bundleForClass:watchViewClass] : [NSBundle mainBundle];
    return [bundle localizedStringForKey:key value:nil table:nil];
}

static NSString *WatchFixBuildResourceString(NSString *prefix, NSInteger material, NSInteger size, NSUInteger attrs) {
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
        [parts addObject:[NSString stringWithFormat:NSSTR("%ld"), (long)mappedMaterial]];
        [parts addObject:NSSTR("M")];
    } else if ((attrs & 0x1) != 0) {
        NSInteger mappedMaterial = WatchFixEMaterialOverrideValue(material);
        if (!mappedMaterial) {
            return nil;
        }
        material = mappedMaterial;
        [parts addObject:[NSString stringWithFormat:NSSTR("%ld"), (long)mappedMaterial]];
        [parts addObject:NSSTR("E")];
    }

    if ((attrs & 0x4) != 0) {
        NSInteger normalizedSize = size;
        if (normalizedSize == 0 || normalizedSize > 21) {
            normalizedSize = 7;
        }
        [parts addObject:[[WatchFixDisplayNameForSize((uint64_t)normalizedSize) lowercaseString] copy]];
    }

    return [parts componentsJoinedByString:NSSTR("-")];
}

static NSInteger WatchFixInternalSizeForNRSizeAndBehavior(NSInteger nrSize, NSInteger behavior) {
    switch (behavior) {
        case 1:
            switch (nrSize) {
                case 1:
                    return 3;
                case 2:
                    return 4;
                case 3:
                    return 9;
                case 4:
                    return 10;
                case 5:
                    return 16;
                case 6:
                    return 15;
                case 7:
                    return 24;
                case 8:
                    return 22;
                case 9:
                    return 23;
                default:
                    return 0;
            }
        case 2:
            switch (nrSize) {
                case 1:
                    return 5;
                case 2:
                    return 6;
                case 3:
                    return 11;
                case 4:
                    return 12;
                case 5:
                    return 18;
                case 6:
                    return 17;
                case 7:
                    return 19;
                case 8:
                    return 20;
                case 9:
                    return 21;
                default:
                    return 0;
            }
        default:
            switch (nrSize) {
                case 1:
                    return 1;
                case 2:
                    return 2;
                case 3:
                    return 7;
                case 4:
                    return 8;
                case 5:
                    return 14;
                case 6:
                    return 13;
                case 7:
                    return 19;
                case 8:
                    return 20;
                case 9:
                    return 21;
                default:
                    return 0;
            }
    }
}

static NSArray *WatchFixSpecialSizesForCurrentOS(void) {
    NSMutableArray *sizes = [NSMutableArray array];
    NSInteger osMajor = [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;
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

static BOOL WatchFixNeedsSpecialHandlingForSize(NSInteger size) {
    NSInteger normalizedSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)size);
    NSInteger targetSize = normalizedSize > 0 ? normalizedSize : size;
    for (NSNumber *candidate in WatchFixSpecialSizesForCurrentOS()) {
        if ([candidate integerValue] == targetSize) {
            return YES;
        }
    }
    return NO;
}

static BOOL WatchFixMaterialOverrideAllowed(NSUInteger style, NSInteger size) {
    NSInteger normalizedSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)size);
    NSInteger targetSize = normalizedSize > 0 ? normalizedSize : size;
    if (!WatchFixNeedsSpecialHandlingForSize(targetSize)) {
        return YES;
    }

    switch (style) {
        case 2:
        case 4:
        case 8:
            return NO;
        default:
            return YES;
    }
}

static CGSize WatchFixComputePatchedWatchScreenSize(NSInteger size) {
    NSInteger normalizedSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)size);
    if (!WatchFixNeedsSpecialHandlingForSize(normalizedSize)) {
        return CGSizeZero;
    }

    BOOL is3x = ([[UIScreen mainScreen] scale] > 2.0);
    switch (normalizedSize) {
        case 14:
            return is3x ? CGSizeMake(78.0, 96.0) : CGSizeMake(71.0, 87.0);
        case 13:
            return is3x ? CGSizeMake(85.0, 105.0) : CGSizeMake(77.0, 95.0);
        case 19:
            return is3x ? CGSizeMake(81.0, 100.0) : CGSizeMake(73.0, 90.0);
        case 20:
            return is3x ? CGSizeMake(78.0, 96.0) : CGSizeMake(71.0, 86.0);
        case 21:
            return is3x ? CGSizeMake(89.0, 106.0) : CGSizeMake(80.0, 94.5);
        default:
            return CGSizeZero;
    }
}

static CGFloat WatchFixComputePatchedWatchScreenOriginInset(NSInteger size, NSUInteger style) {
    NSInteger normalizedSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)size);
    if (!WatchFixNeedsSpecialHandlingForSize(normalizedSize)) {
        return 0.0;
    }

    BOOL is3x = ([[UIScreen mainScreen] scale] > 2.0);
    switch (style) {
        case 2:
            switch (normalizedSize) {
                case 13:
                case 19:
                    return is3x ? 20.5 : 19.5;
                case 14:
                case 20:
                case 21:
                    return is3x ? 21.0 : 20.5;
                default:
                    return 0.0;
            }
        case 3:
            switch (normalizedSize) {
                case 13:
                    return is3x ? 12.5 : 11.0;
                case 14:
                case 20:
                case 21:
                    return is3x ? 11.0 : 10.0;
                case 19:
                    return is3x ? 14.0 : 12.0;
                default:
                    return 0.0;
            }
        case 4:
            switch (normalizedSize) {
                case 13:
                case 19:
                    return is3x ? 37.5 : 30.0;
                case 14:
                case 20:
                case 21:
                    return is3x ? 42.0 : 40.0;
                default:
                    return 0.0;
            }
        case 5:
            return 0.0;
        case 6:
            switch (normalizedSize) {
                case 13:
                case 19:
                    return 7.25;
                case 14:
                    return 7.5;
                case 20:
                case 21:
                    return 40.0;
                default:
                    return 0.0;
            }
        case 7:
            switch (normalizedSize) {
                case 13:
                    return is3x ? 12.5 : 11.0;
                case 14:
                    return is3x ? 11.0 : 10.0;
                case 19:
                    return is3x ? 14.0 : 12.0;
                case 20:
                    return is3x ? 11.0 : 9.0;
                case 21:
                    return is3x ? 10.0 : 9.0;
                default:
                    return 0.0;
            }
        default:
            return 0.0;
    }
}

static CGRect WatchFixComputePatchedWatchScreenFrame(CGSize currentScreenImageSize, NSInteger size, NSUInteger style) {
    CGFloat inset = WatchFixComputePatchedWatchScreenOriginInset(size, style);
    if (inset == 0.0) {
        return CGRectZero;
    }

    return CGRectMake(inset,
                      inset,
                      currentScreenImageSize.width,
                      currentScreenImageSize.height);
}

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

static BOOL WatchFixResolveNormalizedSpecialSizeForAdvertisingName(NSString *advertisingName,
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

static void WatchFixPullDefaultMaterialAssetsForOneSpecialSize(NSInteger size,
                                                               void (^completion)(NSInteger result)) {
    NSInteger normalizedSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)size);
    NSInteger targetSize = normalizedSize > 0 ? normalizedSize : size;
    Log("WatchAppSupport PullAssetsForOneSpecialSize: size=%ld normalizedSize=%ld targetSize=%ld needsSpecial=%d",
        (long)size, (long)normalizedSize, (long)targetSize, WatchFixNeedsSpecialHandlingForSize(targetSize));
    if (!WatchFixNeedsSpecialHandlingForSize(targetSize)) {
        if (completion) {
            completion(1);
        }
        return;
    }

    Class managerClass = objc_lookUpClass("PBBridgeAssetsManager");
    WatchFixPBBridgeAssetsManager *manager =
        (WatchFixPBBridgeAssetsManager *)[[managerClass alloc] init];
    if (!manager) {
        if (completion) {
            completion(0);
        }
        return;
    }

    NSInteger material = WatchFixDefaultMaterialForSpecialSize(targetSize);
    Log("WatchAppSupport PullAssetsForOneSpecialSize: pulling material=%ld size=%ld",
        (long)material, (long)targetSize);
    void (^forwardResult)(NSInteger result) = ^(NSInteger result) {
        Log("WatchAppSupport PullAssetsForOneSpecialSize: completion result=%ld for size=%ld",
            (long)result, (long)targetSize);
        if (completion) {
            completion(result);
        }
    };

    SEL modernSelector = sel_registerName("beginPullingAssetsForDeviceMaterial:size:completion:");
    SEL legacySelector = sel_registerName("beginPullingAssetsForDeviceMaterial:size:branding:completion:");
    if (isOSVersionAtLeast(18, 4, 0) && [manager respondsToSelector:modernSelector]) {
        Log("WatchAppSupport PullAssetsForOneSpecialSize: using modern selector");
        [manager beginPullingAssetsForDeviceMaterial:material
                                                size:targetSize
                                          completion:forwardResult];
        return;
    }

    if ([manager respondsToSelector:legacySelector]) {
        Log("WatchAppSupport PullAssetsForOneSpecialSize: using legacy selector");
        [manager beginPullingAssetsForDeviceMaterial:material
                                                size:targetSize
                                            branding:nil
                                          completion:forwardResult];
        return;
    }

    Log("WatchAppSupport PullAssetsForOneSpecialSize: no selector available for size=%ld", (long)targetSize);
    if (completion) {
        completion(0);
    }
}

static void WatchFixPullDefaultMaterialAssetsForAdvertisingName(NSString *advertisingName,
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

static void WatchFixPullDefaultMaterialAssetsForAllSpecialSizes() {
    NSArray *specialSizes = WatchFixSpecialSizesForCurrentOS();
    if ([specialSizes count] == 0) {
        return;
    }

    for (NSNumber *size in specialSizes) {
        WatchFixPullDefaultMaterialAssetsForOneSpecialSize([size integerValue], nil);
    }
}

static NSString *WatchFixUnsupportedUpdateMessage(void) {
    return NSSTR("A software update is available for your Apple Watch, but it is not compatible with the installed version of WatchFix Pairing Support\n\nCheck for an updated version of WatchFix (or update iOS instead), then try installing this update again");
}

static NSString *WatchFixPairingNotPossibleMessage(void) {
    return NSSTR("The currently installed version of WatchFix Pairing Support does not support the version of watchOS on this Apple Watch.\n\nUpdate iOS or WatchFix to pair this Apple Watch");
}

static void WatchFixPresentUnsupportedWatchUpdateAlert(UIViewController *controller) {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:NSSTR("Update Unsupported")
                                            message:WatchFixUnsupportedUpdateMessage()
                                     preferredStyle:UIAlertControllerStyleAlert];

    NSString *cancelTitle =
        [[NSBundle mainBundle] localizedStringForKey:NSSTR("CANCEL")
                                               value:NSSTR("")
                                               table:nil];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:cancelTitle
                                 style:UIAlertActionStyleCancel
                               handler:^(__unused UIAlertAction *action) {
        [controller dismissViewControllerAnimated:YES completion:nil];
        [[controller navigationController] popViewControllerAnimated:YES];
    }];

    [alert addAction:cancelAction];
    [controller presentViewController:alert animated:YES completion:nil];
}

static void WatchFixPresentPairingNotPossibleAlert(UIViewController *controller,
                                                   void (^dismissalHandler)(void)) {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:NSSTR("Pairing Not Possible")
                                            message:WatchFixPairingNotPossibleMessage()
                                     preferredStyle:UIAlertControllerStyleAlert];

    NSString *cancelTitle =
        [[NSBundle mainBundle] localizedStringForKey:NSSTR("CANCEL_PAIRING")
                                               value:NSSTR("")
                                               table:nil];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:cancelTitle
                                 style:UIAlertActionStyleCancel
                               handler:^(__unused UIAlertAction *action) {
        if (dismissalHandler) {
            dismissalHandler();
        }
    }];

    [alert addAction:cancelAction];

    UIViewController *presenter = [[controller navigationController] topViewController];
    if (!presenter) {
        presenter = controller;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

%group WatchAppSupportSoftwareUpdateControllerHooks

%hook WFSoftwareUpdateControllerClass

- (void)presentAlertForUpdatingCompanion {
    if (!isOSVersionAtLeast(16, 4, 0)) {
        %orig;
        return;
    }

    WatchFixPresentUnsupportedWatchUpdateAlert((UIViewController *)self);
}

%end

%end

%group WatchAppSupportSoftwareUpdateTableHooks

%hook WFSoftwareUpdateTableViewClass

- (void)informUserOfCompanionUpdate {
    %orig;

    if (isOSVersionAtLeast(16, 4, 0)) {
        return;
    }

    NSMutableAttributedString *message =
        [[NSMutableAttributedString alloc] initWithString:WatchFixUnsupportedUpdateMessage()];
    NSRange fullRange = NSMakeRange(0, [message length]);

    [message addAttribute:NSFontAttributeName
                    value:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]
                    range:fullRange];
    [message addAttribute:NSForegroundColorAttributeName
                    value:(BPSTextColor() ?: [UIColor blackColor])
                    range:fullRange];

    UITextView *textView = [(WatchFixSoftwareUpdateTableView *)self updateCompanionTextView];
    [textView setAttributedText:message];
}

%end

%end

%group WatchAppSupportSetupControllerHooks

%hook WFSetupControllerClass

- (void)displayCompanionTooOldPairingFailureAlertWithDismissalHandler:(void (^)(void))dismissalHandler {
    WatchFixPresentPairingNotPossibleAlert((UIViewController *)self, dismissalHandler);
}

%end

%end

%group WatchAppSupportSetupProxyHooks

%hook WFSetupProxyClass

- (void)configureWithContext:(id)context completion:(void (^)(void))completion {
    void (^wrappedCompletion)(void) = ^{
        NSString *advertisingName = nil;
        id userInfo = [(WatchFixSetupContext *)context userInfo];
        if ([userInfo isKindOfClass:[NSDictionary class]]) {
            id candidate = [(NSDictionary *)userInfo objectForKey:NSSTR("advertisingName")];
            if ([candidate isKindOfClass:[NSString class]]) {
                advertisingName = candidate;
            }
        }

        if ([advertisingName length] > 0) {
            WatchFixPullDefaultMaterialAssetsForAdvertisingName(advertisingName, ^{
                if (completion) {
                    completion();
                }
            });
            return;
        }

        if (completion) {
            completion();
        }
    };

    %orig(context, wrappedCompletion);
}

%end

%end

%group WatchAppSupportSetupDeviceSyncHooks

%hook WFSetupDeviceSyncViewClass

- (id)watchImageView {
    id candidate = %orig;
    Class imageViewClass = objc_lookUpClass("BPSRemoteImageView");
    if (candidate && imageViewClass && [candidate isKindOfClass:imageViewClass]) {
        return candidate;
    }

    id fallbackCandidate = [[(UIView *)self subviews] firstObject];
    if (fallbackCandidate && imageViewClass && [fallbackCandidate isKindOfClass:imageViewClass]) {
        return fallbackCandidate;
    }

    return nil;
}

%end

%end

%group WatchAppSupportRemoteImageHooks

%hook WFBPSRemoteImageViewClass

- (void)setFallbackImageName:(NSString *)name {
    Log("WatchAppSupport setFallbackImageName called: %s", CStringOrPlaceholder(name));
    if ([name length] == 0) {
        Log("WatchAppSupport setFallbackImageName: empty name, passing through");
        %orig(name);
        return;
    }

    if ([name rangeOfString:NSSTR("/")].location != NSNotFound) {
        Log("WatchAppSupport setFallbackImageName: path-like name, passing through: %s", CStringOrPlaceholder(name));
        %orig(name);
        return;
    }

    Class remoteImageViewClass = objc_lookUpClass("BPSRemoteImageView");
    NSBundle *bundle = remoteImageViewClass ? [NSBundle bundleForClass:remoteImageViewClass] : nil;
    Log("WatchAppSupport setFallbackImageName: bundle=%s", bundle ? [[bundle bundlePath] UTF8String] : "(nil)");
    if ([name length] > 0 && bundle &&
        [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil]) {
        Log("WatchAppSupport setFallbackImageName: found in bundle, using: %s", CStringOrPlaceholder(name));
        %orig(name);
        return;
    }

    NSString *replacementName = BPSDeviceRemoteAssetString();
    Log("WatchAppSupport setFallbackImageName: replacementName=%s", CStringOrPlaceholder(replacementName));
    if ([replacementName length] > 0 && [UIImage imageNamed:replacementName]) {
        Log("WatchAppSupport setFallbackImageName: using replacement: %s", CStringOrPlaceholder(replacementName));
        %orig(replacementName);
        return;
    }

    Log("WatchAppSupport fallback image missing: %s", CStringOrPlaceholder(name));
    %orig(name);
}

%end

%end

%group WatchAppSupportWatchViewHooks

%hook WFBPSWatchViewClass

- (id)initWithStyle:(NSUInteger)style versionModifier:(id)versionModifier allowsMaterialFallback:(BOOL)allowsMaterialFallback {
    id object = %orig(style, versionModifier, allowsMaterialFallback);
    NSInteger size = [(WatchFixBPSWatchView *)object deviceSize];
    Log("WatchAppSupport BPSWatchView init: style=%lu deviceSize=%ld materialOverrideAllowed=%d",
        (unsigned long)style, (long)size, WatchFixMaterialOverrideAllowed(style, size));
    if (!WatchFixMaterialOverrideAllowed(style, size)) {
        Log("WatchAppSupport BPSWatchView init: forcing overrideMaterial(3, 7)");
        [(WatchFixBPSWatchView *)object overrideMaterial:3 size:7];
    }
    return object;
}

- (CGSize)screenImageSize {
    NSInteger size = [(WatchFixBPSWatchView *)self deviceSize];
    if (!WatchFixNeedsSpecialHandlingForSize(size)) {
        CGSize origSize = %orig;
        Log("WatchAppSupport screenImageSize: size=%ld not special, orig={%.1f,%.1f}",
            (long)size, origSize.width, origSize.height);
        return origSize;
    }

    NSUInteger style = [(WatchFixBPSWatchView *)self style];
    if (style != 3 && style != 7) {
        CGSize origSize = %orig;
        Log("WatchAppSupport screenImageSize: size=%ld special but style=%lu not 3/7, orig={%.1f,%.1f}",
            (long)size, (unsigned long)style, origSize.width, origSize.height);
        return origSize;
    }

    CGSize patchedSize = WatchFixComputePatchedWatchScreenSize(size);
    if (CGSizeEqualToSize(patchedSize, CGSizeZero)) {
        CGSize origSize = %orig;
        Log("WatchAppSupport screenImageSize: size=%ld special style=%lu patchedSize=zero, orig={%.1f,%.1f}",
            (long)size, (unsigned long)style, origSize.width, origSize.height);
        return origSize;
    }
    Log("WatchAppSupport screenImageSize: size=%ld style=%lu => patched={%.1f,%.1f}",
        (long)size, (unsigned long)style, patchedSize.width, patchedSize.height);
    return patchedSize;
}

- (void)layoutWatchScreenImageView {
    NSInteger size = [(WatchFixBPSWatchView *)self deviceSize];
    CGSize currentSize = [(WatchFixBPSWatchView *)self screenImageSize];
    NSUInteger style = [(WatchFixBPSWatchView *)self style];
    CGRect patchedFrame =
        WatchFixComputePatchedWatchScreenFrame(currentSize,
                                              size,
                                              style);

    if (!WatchFixNeedsSpecialHandlingForSize(size) || CGRectEqualToRect(patchedFrame, CGRectZero)) {
        Log("WatchAppSupport layoutWatchScreenImageView: size=%ld style=%lu no-patch (needsSpecial=%d patchedFrame=%.0fx%.0f+%.0f,%.0f)",
            (long)size, (unsigned long)style,
            WatchFixNeedsSpecialHandlingForSize(size),
            patchedFrame.size.width, patchedFrame.size.height,
            patchedFrame.origin.x, patchedFrame.origin.y);
        %orig;
        return;
    }

    Log("WatchAppSupport layoutWatchScreenImageView: size=%ld style=%lu screenImageSize={%.1f,%.1f} => patchedFrame={{%.1f,%.1f},{%.1f,%.1f}}",
        (long)size, (unsigned long)style,
        currentSize.width, currentSize.height,
        patchedFrame.origin.x, patchedFrame.origin.y,
        patchedFrame.size.width, patchedFrame.size.height);
    [[(WatchFixBPSWatchView *)self watchScreenImageView] setFrame:patchedFrame];
}

- (void)overrideMaterial:(NSInteger)material size:(NSInteger)size {
    if (WatchFixMaterialOverrideAllowed([(WatchFixBPSWatchView *)self style], size)) {
        Log("WatchAppSupport overrideMaterial: allowed, material=%ld size=%ld", (long)material, (long)size);
        %orig(material, size);
        return;
    }

    Log("WatchAppSupport overrideMaterial: blocked (style=%lu size=%ld), forcing material=3 size=7",
        (unsigned long)[(WatchFixBPSWatchView *)self style], (long)size);
    %orig(3, 7);
}

%end

%end

%group WatchAppSupportProgressViewHooks

%hook WFPBBridgeProgressViewClass

- (id)initWithStyle:(NSInteger)style andVersion:(NSInteger)version overrideSize:(NSInteger)overrideSize {
    WatchFixPBBridgeWatchAttributeController *controller =
        [(id)objc_lookUpClass("PBBridgeWatchAttributeController") sharedDeviceController];
    NSInteger liveSize = controller ? [controller size] : 0;
    NSInteger patchedOverrideSize = overrideSize;
    if (WatchFixNeedsSpecialHandlingForSize(liveSize) && patchedOverrideSize == 0) {
        patchedOverrideSize = 7;
    }
    return %orig(style, version, patchedOverrideSize);
}

- (CGSize)_size {
    BOOL previousGuard = watchFixProgressAndControllerSizeGuard;
    watchFixProgressAndControllerSizeGuard = NO;
    CGSize value = %orig;
    watchFixProgressAndControllerSizeGuard = previousGuard;
    return value;
}

- (CGFloat)_tickLength {
    BOOL previousGuard = watchFixProgressAndControllerSizeGuard;
    watchFixProgressAndControllerSizeGuard = NO;
    CGFloat value = %orig;
    watchFixProgressAndControllerSizeGuard = previousGuard;
    return value;
}

- (void)layoutSubviews {
    BOOL previousGuard = watchFixProgressAndControllerSizeGuard;
    watchFixProgressAndControllerSizeGuard = NO;
    %orig;
    watchFixProgressAndControllerSizeGuard = previousGuard;
}

%end

%end

%group WatchAppSupportAttributeControllerHooks

%hook WFPBBridgeWatchAttributeControllerClass

+ (NSInteger)_materialForCLHSValue:(NSInteger)clhs {
    NSInteger patchedMaterial = WatchFixPatchedMaterialForCLHSValue(clhs);
    if (patchedMaterial) {
        return patchedMaterial;
    }
    return %orig(clhs);
}

+ (NSString *)resourceString:(NSString *)prefix material:(NSInteger)material size:(NSInteger)size forAttributes:(NSUInteger)attrs {
    NSString *patched = WatchFixBuildResourceString(prefix, material, size, attrs);
    if ([patched length] > 0) {
        return patched;
    }
    return %orig(prefix, material, size, attrs);
}

+ (NSInteger)sizeFromDevice:(id)device {
    NSString *productTypeProperty = NRDevicePropertyProductType;
    if ([productTypeProperty length] == 0) {
        return %orig(device);
    }

    NSString *productType = [device valueForProperty:productTypeProperty];
    if (![productType isKindOfClass:[NSString class]]) {
        return %orig(device);
    }

    WatchFixProductVersion version;
    memset(&version, 0, sizeof(version));
    if (!WatchFixParseProductVersion(productType, &version) ||
        WatchFixProductVersionIsNativelySupportedOnCurrentOS(&version)) {
        return %orig(device);
    }

    WatchFixNRDeviceSize nrSize = WatchFixLookupNanoRegistrySizeForParsedWatchVersion(&version);
    return (NSInteger)WatchFixPBBSizeForNRDeviceSize(nrSize);
}

- (NSString *)resourceString:(NSString *)prefix forAttributes:(NSUInteger)attrs {
    NSMutableDictionary *cache = [(WatchFixPBBridgeWatchAttributeController *)self stringCache];
    if ([cache isKindOfClass:[NSMutableDictionary class]]) {
        NSString *cachedString = [cache objectForKey:prefix];
        if (cachedString) {
            return cachedString;
        }
    }

    NSInteger material = [(WatchFixPBBridgeWatchAttributeController *)self material];
    NSInteger internalSize = [(WatchFixPBBridgeWatchAttributeController *)self internalSize];
    NSInteger normalizedSize = (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)internalSize);
    NSString *patched = WatchFixBuildResourceString(prefix, material, normalizedSize, attrs);
    if ([patched length] > 0 && [cache isKindOfClass:[NSMutableDictionary class]]) {
        [cache setObject:patched forKey:prefix];
        return patched;
    }

    return %orig(prefix, attrs);
}

- (void)setDevice:(id)device {
    %orig(device);

    if ([(WatchFixPBBridgeWatchAttributeController *)self internalSize] != 0) {
        return;
    }

    NSString *productTypeProperty = NRDevicePropertyProductType;
    if ([productTypeProperty length] == 0) {
        return;
    }

    NSString *productType = [device valueForProperty:productTypeProperty];
    if (![productType isKindOfClass:[NSString class]]) {
        return;
    }

    WatchFixProductVersion version;
    memset(&version, 0, sizeof(version));
    if (!WatchFixParseProductVersion(productType, &version)) {
        return;
    }

    WatchFixNRDeviceSize nrSize = WatchFixLookupNanoRegistrySizeForParsedWatchVersion(&version);
    NSInteger internalSize =
        WatchFixInternalSizeForNRSizeAndBehavior(nrSize,
                                                 [(WatchFixPBBridgeWatchAttributeController *)self hardwareBehavior]);
    if (internalSize > 0) {
        [(WatchFixPBBridgeWatchAttributeController *)self setInternalSize:internalSize];
    }
}

- (NSInteger)size {
    if (!watchFixProgressAndControllerSizeGuard) {
        return %orig;
    }

    NSInteger internalSize = [(WatchFixPBBridgeWatchAttributeController *)self internalSize];
    if (internalSize < 1 || internalSize > 24) {
        return 0;
    }

    return (NSInteger)WatchFixNormalizeSizeAlias((uint64_t)internalSize);
}

%end

%end

%group WatchAppSupportAttributeControllerFallbackHooks

%hook WFPBBridgeWatchAttributeControllerFallbackClass

- (NSInteger)fallbackMaterialForSize:(NSInteger)size {
    if (!isOSVersionAtLeast(16, 0, 0)) {
        return %orig(size);
    }

    if (watchFixProgressAndControllerSizeGuard) {
        return WatchFixDefaultMaterialForSpecialSize(size);
    }

    return %orig(size);
}

%end

%end

%group WatchAppSupportAssetsManagerHooks

%hook WFPBBridgeAssetsManagerClass

- (void)beginPullingAssetsForAdvertisingName:(NSString *)advertisingName completion:(void (^)(void))completion {
    BOOL didResolve = NO;
    NSInteger normalizedSize = 0;
    WatchFixResolveNormalizedSpecialSizeForAdvertisingName(advertisingName, &normalizedSize, &didResolve);
    if (!didResolve) {
        %orig(advertisingName, completion);
        return;
    }

    if (!normalizedSize || !WatchFixNeedsSpecialHandlingForSize(normalizedSize)) {
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

%end

%end

void InitWatchAppSupportHooks(void) {
    static BOOL initialized = NO;
    if (initialized) {
        Log("WatchAppSupport hooks already initialized");
        return;
    }
    initialized = YES;

    Log("Initializing WatchAppSupport hooks...");

    Class softwareUpdateControllerClass = objc_lookUpClass("COSSoftwareUpdateController");
    if (softwareUpdateControllerClass) {
        %init(WatchAppSupportSoftwareUpdateControllerHooks, WFSoftwareUpdateControllerClass=softwareUpdateControllerClass);
    }

    Class softwareUpdateTableViewClass = objc_lookUpClass("COSSoftwareUpdateTableView");
    if (softwareUpdateTableViewClass) {
        %init(WatchAppSupportSoftwareUpdateTableHooks, WFSoftwareUpdateTableViewClass=softwareUpdateTableViewClass);
    }

    Class setupControllerClass = objc_lookUpClass("COSSetupController");
    if (setupControllerClass) {
        %init(WatchAppSupportSetupControllerHooks, WFSetupControllerClass=setupControllerClass);
    }

    Class setupProxyClass = objc_lookUpClass("WatchSetupViewControllerProxy");
    if (setupProxyClass) {
        %init(WatchAppSupportSetupProxyHooks, WFSetupProxyClass=setupProxyClass);
    }

    Class setupDeviceSyncViewClass = objc_lookUpClass("COSSetupDeviceSyncView");
    if (setupDeviceSyncViewClass) {
        %init(WatchAppSupportSetupDeviceSyncHooks, WFSetupDeviceSyncViewClass=setupDeviceSyncViewClass);
    }

    Class remoteImageViewClass = objc_lookUpClass("BPSRemoteImageView");
    if (remoteImageViewClass) {
        %init(WatchAppSupportRemoteImageHooks, WFBPSRemoteImageViewClass=remoteImageViewClass);
    }

    Class watchViewClass = objc_lookUpClass("BPSWatchView");
    if (watchViewClass) {
        %init(WatchAppSupportWatchViewHooks, WFBPSWatchViewClass=watchViewClass);
    }

    Class progressViewClass = objc_lookUpClass("PBBridgeProgressView");
    if (progressViewClass) {
        %init(WatchAppSupportProgressViewHooks, WFPBBridgeProgressViewClass=progressViewClass);
    }

    Class attributeControllerClass = objc_lookUpClass("PBBridgeWatchAttributeController");
    if (attributeControllerClass) {
        %init(WatchAppSupportAttributeControllerHooks,
              WFPBBridgeWatchAttributeControllerClass=attributeControllerClass);
    }

    if (isOSVersionAtLeast(16, 0, 0) && attributeControllerClass) {
        %init(WatchAppSupportAttributeControllerFallbackHooks,
              WFPBBridgeWatchAttributeControllerFallbackClass=attributeControllerClass);
    }

    Class assetsManagerClass = objc_lookUpClass("PBBridgeAssetsManager");
    if (!isOSVersionAtLeast(18, 0, 0) && assetsManagerClass) {
        %init(WatchAppSupportAssetsManagerHooks, WFPBBridgeAssetsManagerClass=assetsManagerClass);
    }

    Log("WatchAppSupport hooks initialized");

    %init(WatchAppSupportFunctionHooks);

    Log("WatchAppSupport function hooks initialized");
    const char *programName = getprogname();
    if (!programName || !is_equal(programName, "SharingViewService")) {
        WatchFixPullDefaultMaterialAssetsForAllSpecialSizes();
    }
}

%ctor {
    const char *progname = getprogname();
    if (!progname) {
        return;
    }
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    const char *bundleIDCString = [bundleID UTF8String];
    Log("Bundle ID   : %s", bundleIDCString);
    Log("Program Name: %s", progname);
    if (is_equal(bundleIDCString, "com.apple.Bridge") ||
        is_equal(bundleIDCString, "com.apple.SharingViewService") ||
        is_equal(progname, "SharingViewService")) {
        Log("Initializing WatchAppSupport...");
        InitWatchAppSupportHooks();
    }
}