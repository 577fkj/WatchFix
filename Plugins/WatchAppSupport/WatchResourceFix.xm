#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "WatchUtils_internal.h"

// ---------------------------------------------------------------------------
// RemoteImage fallback fix
// ---------------------------------------------------------------------------

%group WatchAppSupportRemoteImageHooks

%hook WFBPSRemoteImageViewClass

- (void)setFallbackImageName:(NSString *)name {
    Log(@"WatchAppSupport setFallbackImageName called: %@", name);
    if ([name length] == 0) {
        Log(@"WatchAppSupport setFallbackImageName: empty name, passing through");
        %orig(name);
        return;
    }

    if ([name rangeOfString:@"/"].location != NSNotFound) {
        Log(@"WatchAppSupport setFallbackImageName: path-like name, passing through: %@", name);
        %orig(name);
        return;
    }

    Class remoteImageViewClass = objc_lookUpClass("BPSRemoteImageView");
    NSBundle *bundle = remoteImageViewClass ? [NSBundle bundleForClass:remoteImageViewClass] : nil;
    Log(@"WatchAppSupport setFallbackImageName: bundle=%@", bundle.bundlePath);
    if ([name length] > 0 && bundle &&
        [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil]) {
        Log(@"WatchAppSupport setFallbackImageName: found in bundle, using: %@", name);
        %orig(name);
        return;
    }

    NSString *replacementName = BPSDeviceRemoteAssetString();
    Log(@"WatchAppSupport setFallbackImageName: replacementName=%@", replacementName);
    if ([replacementName length] > 0 && [UIImage imageNamed:replacementName]) {
        Log(@"WatchAppSupport setFallbackImageName: using replacement: %@", replacementName);
        %orig(replacementName);
        return;
    }

    Log(@"WatchAppSupport fallback image missing: %@", name);
    %orig(name);
}

%end

%end

// ---------------------------------------------------------------------------
// AttributeController hooks — resource string building & size/device mapping
// ---------------------------------------------------------------------------

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

    WatchFixProductVersion *version = WatchFixParseProductVersion(productType);
    if (!version) {
        return %orig(device);
    }
    if (WatchFixProductVersionIsNativelySupportedOnCurrentOS(version)) {
        return %orig(device);
    }

    WatchFixNRDeviceSize nrSize = WatchFixLookupNanoRegistrySizeForParsedWatchVersion(version);
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

    WatchFixProductVersion *version = WatchFixParseProductVersion(productType);
    if (!version) {
        return;
    }

    WatchFixNRDeviceSize nrSize = WatchFixLookupNanoRegistrySizeForParsedWatchVersion(version);
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

// ---------------------------------------------------------------------------
// AttributeController fallback material (iOS 16+)
// ---------------------------------------------------------------------------

%group WatchAppSupportAttributeControllerFallbackHooks

%hook WFPBBridgeWatchAttributeControllerFallbackClass

- (NSInteger)fallbackMaterialForSize:(NSInteger)size {
    if (!IOSVersionAtLeast(16, 0, 0)) {
        return %orig(size);
    }

    if (watchFixProgressAndControllerSizeGuard) {
        return WatchFixDefaultMaterialForSpecialSize(size);
    }

    return %orig(size);
}

%end

%end

// ---------------------------------------------------------------------------
// Module init — called from InitWatchAppSupportHooks() in WatchAppSupport.xm
// ---------------------------------------------------------------------------
void InitWatchResourceFixHooks(void) {
    Class remoteImageViewClass = objc_lookUpClass("BPSRemoteImageView");
    if (remoteImageViewClass) {
        %init(WatchAppSupportRemoteImageHooks, WFBPSRemoteImageViewClass=remoteImageViewClass);
    }

    Class attributeControllerClass = objc_lookUpClass("PBBridgeWatchAttributeController");
    if (attributeControllerClass) {
        %init(WatchAppSupportAttributeControllerHooks,
            WFPBBridgeWatchAttributeControllerClass=attributeControllerClass);

        if (IOSVersionAtLeast(16, 0, 0)) {
            %init(WatchAppSupportAttributeControllerFallbackHooks,
                WFPBBridgeWatchAttributeControllerFallbackClass=attributeControllerClass);
        }
    }
}
