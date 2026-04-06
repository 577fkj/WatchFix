#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include "utils.h"

@interface WatchBundle : NSObject
- (BOOL)isApplicableToOSVersion:(id)version error:(id *)error;
@end

%group MessageFixes

%hook ApplicationManager

- (NSDictionary *)_supplementalSystemAppBundleIDMappingForWatchOSSixAndLater {
    Log("Original _supplementalSystemAppBundleIDMappingForWatchOSSixAndLater called");
    NSDictionary *result = %orig;
    NSMutableDictionary *mapping = [result mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *sms = @"com.apple.MobileSMS";
    [mapping setObject:sms forKey:sms];
    Log("Add Success");
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
    return [self isApplicableToOSVersion:@"11.9999" error:nil];
}

- (NSString *)currentOSVersionForValidationWithError:(id *)error {
    return @"11.9999";
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

%ctor {
    const char *progname = getprogname();
    if (!progname) {
        return;
    }
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    const char *bundleIDCString = [bundleID UTF8String];
    Log("Bundle ID   : %s", bundleIDCString);
    Log("Program Name: %s", progname);
    if (is_equal(progname, "appconduitd")) {
        Log("Initializing AppsSupport...");
        InstallAppConduitHook();
    } else if (is_equal(progname, "installd") ||
        is_equal(progname, "MobileInstallationHelperService") ||
        is_equal(progname, "com.apple.MobileInstallationHelperService")) {
        Log("Initializing AppsSupport...");
        InstallAppsSupportHooks();
    }
}