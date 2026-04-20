#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "WatchUtils_internal.h"

// ---------------------------------------------------------------------------
// BPSWatchView — screen image size / layout / material override
// ---------------------------------------------------------------------------

%group WatchAppSupportWatchViewHooks

%hook BPSWatchView

- (BPSWatchView *)initWithStyle:(NSUInteger)style versionModifier:(NSString *)versionModifier allowsMaterialFallback:(BOOL)allowsMaterialFallback {
    Log(@"WatchAppSupport BPSWatchView init: style=%lu versionModifier=%@ allowsMaterialFallback=%d",
        (unsigned long)style, versionModifier, allowsMaterialFallback);
    BPSWatchView *watchView = %orig(style, versionModifier, allowsMaterialFallback);
    NSInteger size = [watchView deviceSize];
    Log(@"WatchAppSupport BPSWatchView init: style=%lu deviceSize=%ld materialOverrideAllowed=%d",
        (unsigned long)style, (long)size, WatchFixMaterialOverrideAllowed(style, size));
    if (!WatchFixMaterialOverrideAllowed(style, size)) {
        Log(@"WatchAppSupport BPSWatchView init: forcing overrideMaterial(3, 7)");
        [watchView overrideMaterial:3 size:7];
    }
    return watchView;
}

- (CGSize)screenImageSize {
    NSInteger size = [self deviceSize];
    if (!WatchFixNeedsSpecialHandlingForSize(size)) {
        CGSize origSize = %orig;
        Log(@"WatchAppSupport screenImageSize: size=%ld not special, orig={%.1f,%.1f}",
            (long)size, origSize.width, origSize.height);
        return origSize;
    }

    NSUInteger style = [self style];
    if (style != 3 && style != 7) {
        CGSize origSize = %orig;
        Log(@"WatchAppSupport screenImageSize: size=%ld special but style=%lu not 3/7, orig={%.1f,%.1f}",
            (long)size, (unsigned long)style, origSize.width, origSize.height);
        return origSize;
    }

    CGSize patchedSize = WatchFixComputePatchedWatchScreenSize(size);
    if (CGSizeEqualToSize(patchedSize, CGSizeZero)) {
        CGSize origSize = %orig;
        Log(@"WatchAppSupport screenImageSize: size=%ld special style=%lu patchedSize=zero, orig={%.1f,%.1f}",
            (long)size, (unsigned long)style, origSize.width, origSize.height);
        return origSize;
    }
    Log(@"WatchAppSupport screenImageSize: size=%ld style=%lu => patched={%.1f,%.1f}",
        (long)size, (unsigned long)style, patchedSize.width, patchedSize.height);
    return patchedSize;
}

- (void)layoutWatchScreenImageView {
    NSInteger size = [self deviceSize];
    CGSize currentSize = [self screenImageSize];
    NSUInteger style = [self style];
    CGRect patchedFrame =
        WatchFixComputePatchedWatchScreenFrame(currentSize, size, style);
    
    Log(@"WatchAppSupport layoutWatchScreenImageView: size=%ld style=%lu currentSize={%.1f,%.1f} patchedFrame={{%.1f,%.1f},{%.1f,%.1f}}",
        (long)size, (unsigned long)style,
        currentSize.width, currentSize.height,
        patchedFrame.origin.x, patchedFrame.origin.y,
        patchedFrame.size.width, patchedFrame.size.height);

    if (!WatchFixNeedsSpecialHandlingForSize(size) || CGRectEqualToRect(patchedFrame, CGRectZero)) {
        Log(@"WatchAppSupport layoutWatchScreenImageView: size=%ld style=%lu no-patch (needsSpecial=%d patchedFrame=%.0fx%.0f+%.0f,%.0f)",
            (long)size, (unsigned long)style,
            WatchFixNeedsSpecialHandlingForSize(size),
            patchedFrame.size.width, patchedFrame.size.height,
            patchedFrame.origin.x, patchedFrame.origin.y);
        %orig;
        return;
    }

    Log(@"WatchAppSupport layoutWatchScreenImageView: size=%ld style=%lu screenImageSize={%.1f,%.1f} => patchedFrame={{%.1f,%.1f},{%.1f,%.1f}}",
        (long)size, (unsigned long)style,
        currentSize.width, currentSize.height,
        patchedFrame.origin.x, patchedFrame.origin.y,
        patchedFrame.size.width, patchedFrame.size.height);
    [[self watchScreenImageView] setFrame:patchedFrame];
}

- (void)overrideMaterial:(NSInteger)material size:(NSInteger)size {
    Log(@"WatchAppSupport overrideMaterial called: style=%lu material=%ld size=%ld",
        (unsigned long)[self style], (long)material, (long)size);
    if (WatchFixMaterialOverrideAllowed([self style], size)) {
        Log(@"WatchAppSupport overrideMaterial: allowed, material=%ld size=%ld", (long)material, (long)size);
        %orig(material, size);
        return;
    }

    Log(@"WatchAppSupport overrideMaterial: blocked (style=%lu size=%ld), forcing material=3 size=7",
        (unsigned long)[self style], (long)size);
    %orig(3, 7);
}

%end

%end

// ---------------------------------------------------------------------------
// PBBridgeProgressView — re-entrancy guard for size/tick/layout calls
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// COSSetupDeviceSyncView — watchImageView fallback
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Module init — called from InitWatchAppSupportHooks() in WatchAppSupport.xm
// ---------------------------------------------------------------------------
void InitWatchScreenPatchHooks(void) {
    %init(WatchAppSupportWatchViewHooks);

    Class progressViewClass = objc_lookUpClass("PBBridgeProgressView");
    if (progressViewClass) {
        %init(WatchAppSupportProgressViewHooks, WFPBBridgeProgressViewClass=progressViewClass);
    }

    Class setupDeviceSyncViewClass = objc_lookUpClass("COSSetupDeviceSyncView");
    if (setupDeviceSyncViewClass) {
        %init(WatchAppSupportSetupDeviceSyncHooks, WFSetupDeviceSyncViewClass=setupDeviceSyncViewClass);
    }
}
