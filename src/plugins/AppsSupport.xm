#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include "../utils/utils.h"

@interface WatchBundle : NSObject
- (BOOL)isApplicableToOSVersion:(id)version error:(id *)error;
@end

%group MessageFixes

%hook ApplicationManager

- (NSDictionary *)_supplementalSystemAppBundleIDMappingForWatchOSSixAndLater {
    Log("Original _supplementalSystemAppBundleIDMappingForWatchOSSixAndLater called");
    NSDictionary *result = %orig;
    NSMutableDictionary *mapping = [result mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *sms = NSSTR("com.apple.MobileSMS");
    [mapping setObject:sms forKey:sms];
    Log("Add Success");
    Log("Final mapping dictionary count: %lu", (unsigned long)[mapping count]);
    for (NSString *key in mapping) {
        NSString *value = [mapping objectForKey:key];
        Log("  %s => %s", [key UTF8String], [value UTF8String]);
    }
    return mapping;
}

// - (NSArray *)_bundleIDsOfLocallyAvailableSystemApps {
//     Log("Original _bundleIDsOfLocallyAvailableSystemApps called");
//     NSArray *result = %orig;
//     Log("Original bundle IDs count: %lu", (unsigned long)[result count]);
//     for (NSString *bundleID in result) {
//         Log("  %s", [bundleID UTF8String]);
//     }
//     return result;
// }

%end

%end

%group AppsSupport

%hook WatchBundle

- (BOOL)isApplicableToKnownWatchOSVersion {
    return [self isApplicableToOSVersion:NSSTR("11.9999") error:nil];
}

- (NSString *)currentOSVersionForValidationWithError:(id *)error {
    return NSSTR("11.9999");
}

%end

%end

void InstallAppConduitHook(void) {
    Class managerClass = objc_lookUpClass("ACXAvailableApplicationManager");
    if (!managerClass) {
        Log("ACXAvailableApplicationManager class not found, skipping app conduit hook");
        return;
    }
    %init(MessageFixes, ApplicationManager=managerClass);

    Log("Installed app conduit hook");
}

void InstallAppsSupportHooks(void) {
    Class watchBundleClass = objc_lookUpClass("MIEmbeddedWatchBundle");
    if (!watchBundleClass) {
        Log("MIEmbeddedWatchBundle class not found, skipping AppsSupport hooks");
        return;
    }

    %init(AppsSupport, WatchBundle=watchBundleClass);

    Log("Installed AppsSupport hooks");
}
