#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include "utils.h"

@interface IDSDependencyProvider : NSObject
- (NSArray *)loadServiceDictionaries;
@end

static NSString *const kLockdownModeServiceIdentifier = @"com.apple.private.alloy.lockdownmode";
static NSString *const kServiceDictionaryIdentifierKey = @"Identifier";

static NSDictionary *WatchFixLockdownModeServiceDictionary(void) {
    static NSDictionary *serviceDictionary = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        serviceDictionary = @{
            @"AdHocServiceType": @2,
            @"AllowUrgentMessages": @YES,
            @"AllowWakingMessages": @YES,
            @"AutoConfigureVettedAddresses": @YES,
            @"DisplayName": @"Lockdown Mode",
            @"Identifier": kLockdownModeServiceIdentifier,
            @"MinCompatibilityVersion": @17,
            @"ServiceName": kLockdownModeServiceIdentifier,
            @"iCloudService": @YES,
        };
    });
    return serviceDictionary;
}

static BOOL WatchFixServiceDictionariesContainLockdownModeEntry(NSArray *serviceDictionaries) {
    if (![serviceDictionaries isKindOfClass:[NSArray class]]) {
        return NO;
    }

    for (id entry in serviceDictionaries) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSString *identifier = [(NSDictionary *)entry objectForKey:kServiceDictionaryIdentifierKey];
        if ([identifier isKindOfClass:[NSString class]] &&
            [identifier isEqualToString:kLockdownModeServiceIdentifier]) {
            return YES;
        }
    }

    return NO;
}

%group LockdownModeSupport

%hook IDSDependencyProvider

- (NSArray *)loadServiceDictionaries {
    NSArray *serviceDictionaries = %orig;
    if (serviceDictionaries && ![serviceDictionaries isKindOfClass:[NSArray class]]) {
        Log("loadServiceDictionaries returned unexpected class: %s",
            class_getName(object_getClass(serviceDictionaries)));
        return serviceDictionaries;
    }

    if (WatchFixServiceDictionariesContainLockdownModeEntry(serviceDictionaries)) {
        Log("lockdown mode service dictionary already present");
        return serviceDictionaries;
    }

    NSMutableArray *mutableServiceDictionaries =
        serviceDictionaries ? [serviceDictionaries mutableCopy] : [NSMutableArray array];
    if (!mutableServiceDictionaries) {
        Log("failed to create mutable service dictionary array");
        return serviceDictionaries;
    }

    [mutableServiceDictionaries addObject:WatchFixLockdownModeServiceDictionary()];
    Log("added lockdown mode service dictionary");
    return mutableServiceDictionaries;
}

%end

%end

static void InitLockdownModeSupportHooks(void) {
    if (isOSVersionAtLeast(17, 0, 0)) {
        Log("host OS is iOS 17 or newer, skipping LockdownModeSupport hooks");
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class providerClass = objc_lookUpClass("IDSDependencyProvider");
        if (!providerClass) {
            Log("IDSDependencyProvider class not found, skipping LockdownModeSupport hooks");
            return;
        }

        %init(LockdownModeSupport, IDSDependencyProvider=providerClass);
        Log("installed LockdownModeSupport hooks");
    });
}

%ctor {
    const char *progname = getprogname();
    if (!progname) {
        return;
    }

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    Log("Bundle ID   : %s", CStringOrPlaceholder(bundleID));
    Log("Program Name: %s", progname);

    if (is_equal(progname, "identityservicesd")) {
        InitLockdownModeSupportHooks();
    }
}
