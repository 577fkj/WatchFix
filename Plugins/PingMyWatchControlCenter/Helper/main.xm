#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

#include "utils.h"

@interface NFMWhereIsMyCompanionConnection : NSObject
+ (instancetype)sharedDeviceConnection;
- (void)playSoundAndLightsOnCompanionWithCompletion:(void (^)(BOOL success))completion;
- (void)playSoundOnCompanionWithCompletion:(void (^)(BOOL success))completion;
@end

static const NSTimeInterval kWFPMWHelperPrimaryTimeoutSeconds = 4.0;
static const NSTimeInterval kWFPMWHelperFallbackTimeoutSeconds = 4.0;
static const NSTimeInterval kWFPMWHelperRunLoopSliceSeconds = 0.05;

static BOOL WFPMWHelperWaitForCompletion(BOOL *completed,
                                         const char *selectorName,
                                         NSTimeInterval timeoutSeconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSeconds];

    while (!*completed && [deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:kWFPMWHelperRunLoopSliceSeconds]];
        }
    }

    if (!*completed) {
        Log(@"helper timed out waiting for %@", StringFromCString(selectorName));
        return NO;
    }

    return YES;
}

static BOOL WFPMWHelperInvokePingSelector(NFMWhereIsMyCompanionConnection *connection,
                                          SEL selector,
                                          NSTimeInterval timeoutSeconds) {
    if (!connection || !selector || ![connection respondsToSelector:selector]) {
        return NO;
    }

    __block BOOL completed = NO;
    __block BOOL reportedSuccess = NO;
    const char *selectorName = sel_getName(selector);

    Log(@"helper using selector %@", StringFromCString(selectorName));
    void (^completion)(BOOL) = ^(BOOL played) {
        completed = YES;
        reportedSuccess = played;
        Log(@"helper completion for %@: %@",
              StringFromCString(selectorName),
              BoolString(played));
    };

    if (selector == @selector(playSoundAndLightsOnCompanionWithCompletion:)) {
        [connection playSoundAndLightsOnCompanionWithCompletion:completion];
    } else if (selector == @selector(playSoundOnCompanionWithCompletion:)) {
        [connection playSoundOnCompanionWithCompletion:completion];
    } else {
        Log(@"helper received unsupported selector %@", StringFromCString(selectorName));
        return NO;
    }

    if (!WFPMWHelperWaitForCompletion(&completed, selectorName, timeoutSeconds)) {
        return NO;
    }

    if (!reportedSuccess) {
        Log(@"helper received completion for %@ with reported result NO", StringFromCString(selectorName));
    }

    return YES;
}

int main(__unused int argc, __unused char *argv[]) {
    @autoreleasepool {
        NFMWhereIsMyCompanionConnection *connection = [NFMWhereIsMyCompanionConnection sharedDeviceConnection];
        if (!connection) {
            Log(@"helper could not access sharedDeviceConnection");
            return 1;
        }

        BOOL didPlay = NO;
        if ([connection respondsToSelector:@selector(playSoundOnCompanionWithCompletion:)]) {
            didPlay = WFPMWHelperInvokePingSelector(connection,
                                                    @selector(playSoundOnCompanionWithCompletion:),
                                                    kWFPMWHelperFallbackTimeoutSeconds);
        }

        if (!didPlay && [connection respondsToSelector:@selector(playSoundAndLightsOnCompanionWithCompletion:)]) {
            didPlay = WFPMWHelperInvokePingSelector(connection,
                                                    @selector(playSoundAndLightsOnCompanionWithCompletion:),
                                                    kWFPMWHelperPrimaryTimeoutSeconds);
        }

        Log(@"helper finished ping request with result: %@", BoolString(didPlay));
        return didPlay ? 0 : 1;
    }
}
