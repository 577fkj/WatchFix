#import "PingMyWatchControlCenter.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#include <errno.h>
#include <spawn.h>
#include <sys/wait.h>

#include "utils.h"

typedef BOOL (^WFPMWDeviceSelectorBlock)(id device);

@interface NRDevice : NSObject
- (id)valueForProperty:(id)property;
- (BOOL)supportsCapability:(NSUUID *)capability;
@end

@interface NRPairedDeviceRegistry : NSObject
+ (instancetype)sharedInstance;
+ (WFPMWDeviceSelectorBlock)activePairedDeviceSelectorBlock;
- (NSArray<NRDevice *> *)getAllDevicesWithArchivedAltAccountDevicesMatching:(BOOL (^)(NRDevice *device))predicate;
@end

@interface NSSymbolVariableColorEffect : NSObject
+ (instancetype)effect;
- (instancetype)effectWithCumulative;
@end

@interface NSSymbolEffectOptions : NSObject
+ (instancetype)optionsWithRepeatCount:(NSInteger)count;
@end

typedef void (^WFPMWSymbolEffectCompletion)(id context);

@interface CCUIToggleModule (WatchFixPingMyWatchControlCenterUI)
- (void)refreshState;
- (void)refreshStateAnimated:(BOOL)animated;
- (UIImageView *)glyphImageView;
@end

@interface UIImageView (WatchFixPingMyWatchControlCenterUIEffects)
- (void)addSymbolEffect:(id)symbolEffect
                options:(id)options
               animated:(BOOL)animated
             completion:(WFPMWSymbolEffectCompletion)completion;
@end

static NSString *const kWFPMWCapabilityUUIDString = @"C5BAD2E8-BB79-4E9E-8A0D-757C60D31053";
static NSString *const kWFPMWPrimarySymbolName = @"applewatch.radiowaves.left.and.right";
static NSString *const kWFPMWFallbackSymbolName = @"dot.radiowaves.left.and.right";
static NSString *const kWFPMWLastFallbackSymbolName = @"applewatch";
static NSString *const kWFPMWHelperExecutableName = @"WatchFixPingMyWatchHelper";

extern "C" NSString *NRDevicePropertyIsArchived;
extern "C" NSString *NRDevicePropertyIsPaired;

static NSUUID *WFPMWCapabilityUUID(void) {
    static NSUUID *uuid = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uuid = [[NSUUID alloc] initWithUUIDString:kWFPMWCapabilityUUIDString];
    });
    return uuid;
}

static void WFPMWRefreshModuleState(CCUIToggleModule *module, BOOL animated) {
    if (!module) {
        return;
    }

    if ([module respondsToSelector:@selector(refreshStateAnimated:)]) {
        [module refreshStateAnimated:animated];
        return;
    }

    if ([module respondsToSelector:@selector(refreshState)]) {
        [module refreshState];
    }
}

static BOOL WFPMWDefaultSelectionMatchesDevice(NRDevice *device) {
    if (!device) {
        return NO;
    }

    id isPaired = [device valueForProperty:NRDevicePropertyIsPaired];
    if (![isPaired isKindOfClass:NSNumber.class] || ![isPaired boolValue]) {
        return NO;
    }

    id isArchived = [device valueForProperty:NRDevicePropertyIsArchived];
    if ([isArchived isKindOfClass:NSNumber.class] && [isArchived boolValue]) {
        return NO;
    }

    return YES;
}

static NRDevice *WFPMWActivePairedWatch(void) {
    NRPairedDeviceRegistry *registry = [NRPairedDeviceRegistry sharedInstance];
    if (!registry) {
        Log("NRPairedDeviceRegistry sharedInstance is unavailable");
        return nil;
    }

    WFPMWDeviceSelectorBlock selectorBlock = [NRPairedDeviceRegistry activePairedDeviceSelectorBlock];
    NSArray<NRDevice *> *devices = [registry getAllDevicesWithArchivedAltAccountDevicesMatching:^BOOL(NRDevice *device) {
        if (!WFPMWDefaultSelectionMatchesDevice(device)) {
            return NO;
        }

        if (!selectorBlock) {
            return YES;
        }

        return selectorBlock(device);
    }];
    return devices.firstObject;
}

static NSString *WFPMWHelperExecutablePath(void) {
    NSBundle *bundle = [NSBundle bundleForClass:[WFPingMyWatchControlCenterModule class]];
    NSString *bundlePath = bundle.bundlePath;
    if (bundlePath.length == 0) {
        Log("bundle path is unavailable");
        return nil;
    }

    return [bundlePath stringByAppendingPathComponent:kWFPMWHelperExecutableName];
}

static pid_t WFPMWLaunchPingHelper(void) {
    NSString *helperPath = WFPMWHelperExecutablePath();
    const char *path = helperPath.fileSystemRepresentation;
    if (!path) {
        Log("helper executable path is unavailable");
        return -1;
    }

    extern char **environ;
    char *const argv[] = {
        (char *)path,
        NULL,
    };
    pid_t pid = 0;
    int spawnStatus = posix_spawn(&pid, path, NULL, NULL, argv, environ);
    if (spawnStatus != 0) {
        Log("failed to launch helper at %s, status=%d", path, spawnStatus);
        return -1;
    }

    Log("launched helper at %s with pid %d", path, pid);
    return pid;
}

@implementation WFPingMyWatchControlCenterModule

@synthesize pingInProgress = _pingInProgress;

+ (BOOL)isSupported {
    NRDevice *activePairedDevice = WFPMWActivePairedWatch();
    if (!activePairedDevice) {
        return NO;
    }

    return [activePairedDevice supportsCapability:WFPMWCapabilityUUID()];
}

- (BOOL)isSelected {
    return self.pingInProgress;
}

- (void)setSelected:(BOOL)selected {
    if (!selected || self.pingInProgress) {
        return;
    }

    self.pingInProgress = YES;
    WFPMWRefreshModuleState(self, NO);
    [self _pingDevice];

    [self _playGliphAnimationWithCompletion:^{
        Log("glyph animation completed");
    }];
}

- (UIImage *)iconGlyph {
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                        weight:UIImageSymbolWeightRegular
                                                         scale:UIImageSymbolScaleLarge];

    UIImage *image = [UIImage systemImageNamed:kWFPMWPrimarySymbolName
                             withConfiguration:configuration];
    if (!image) {
        image = [UIImage systemImageNamed:kWFPMWFallbackSymbolName
                        withConfiguration:configuration];
    }
    if (!image) {
        image = [UIImage systemImageNamed:kWFPMWLastFallbackSymbolName
                        withConfiguration:configuration];
    }
    return image;
}

- (UIColor *)selectedColor {
    if ([UIColor respondsToSelector:@selector(systemOrangeColor)]) {
        return [UIColor systemOrangeColor];
    }
    return [UIColor orangeColor];
}

- (void)_pingDevice {
    Log("sending ping to device");

    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        @autoreleasepool {
            NRDevice *selectedWatch = WFPMWActivePairedWatch();
            if (!selectedWatch) {
                Log("no active paired watch matched the current selection criteria");
            } else if (![selectedWatch supportsCapability:WFPMWCapabilityUUID()]) {
                Log("ping my watch is not supported for the active device");
            } else {
                pid_t helperPID = WFPMWLaunchPingHelper();
                if (helperPID > 0) {
                    int waitStatus = 0;
                    int waitResult = waitpid(helperPID, &waitStatus, 0);
                    if (waitResult == helperPID) {
                        Log("helper pid %d finished with wait status %d", helperPID, waitStatus);
                    } else {
                        Log("waitpid failed for helper pid %d, result=%d errno=%d", helperPID, waitResult, errno);
                    }
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong __typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                strongSelf.pingInProgress = NO;
                WFPMWRefreshModuleState(strongSelf, YES);
            });
        }
    });
}

- (void)_playGliphAnimationWithCompletion:(void (^)(void))completion {
    UIImageView *glyphImageView = nil;
    if ([self respondsToSelector:@selector(glyphImageView)]) {
        glyphImageView = [self glyphImageView];
    }

    if (!glyphImageView) {
        if (completion) {
            completion();
        }
        return;
    }

    [UIView animateWithDuration:0.18
                     animations:^{
        glyphImageView.transform = CGAffineTransformMakeScale(1.12, 1.12);
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.18
                         animations:^{
            glyphImageView.transform = CGAffineTransformIdentity;
        } completion:^(__unused BOOL finishedInner) {
            if (completion) {
                completion();
            }
        }];
    }];
}

@end
