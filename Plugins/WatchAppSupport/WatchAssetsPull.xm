#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "WatchUtils_internal.h"

// ---------------------------------------------------------------------------
// PBBridgeAssetsManager — intercept advertising-name pull (pre-iOS 18)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// WatchSetupViewControllerProxy — pull default assets during pairing setup
// ---------------------------------------------------------------------------

%group WatchAppSupportSetupProxyHooks

%hook WFSetupProxyClass

- (void)configureWithContext:(id)context completion:(void (^)(void))completion {
    void (^wrappedCompletion)(void) = ^{
        NSString *advertisingName = nil;
        id userInfo = [(WatchFixSetupContext *)context userInfo];
        if ([userInfo isKindOfClass:[NSDictionary class]]) {
            id candidate = [(NSDictionary *)userInfo objectForKey:@"advertisingName"];
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

// ---------------------------------------------------------------------------
// Module init — called from InitWatchAppSupportHooks() in WatchAppSupport.xm
// ---------------------------------------------------------------------------
void InitWatchAssetsPullHooks(void) {
    Class assetsManagerClass = objc_lookUpClass("PBBridgeAssetsManager");
    if (assetsManagerClass) {
        if (!IOSVersionAtLeast(18, 0, 0)) {
            %init(WatchAppSupportAssetsManagerHooks, WFPBBridgeAssetsManagerClass=assetsManagerClass);
        }
    }

    Class setupProxyClass = objc_lookUpClass("WatchSetupViewControllerProxy");
    if (setupProxyClass) {
        %init(WatchAppSupportSetupProxyHooks, WFSetupProxyClass=setupProxyClass);
    }
}
