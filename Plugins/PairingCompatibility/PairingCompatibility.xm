#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dispatch/dispatch.h>
#include <substrate.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include "PluginConfig.h"
#include "utils.h"
#include "PairingCompatibility.h"

static NSString *const kPairingMinKey = @"PairingCompatibilityMinVersion";
static NSString *const kPairingMaxKey = @"PairingCompatibilityMaxVersion";
static NSString *const kHelloThresholdKey = @"PairingCompatibilityHelloThreshold";
static NSString *const kFrameworkHooksEnabledKey = @"PairingCompatibilityFrameworkCompatibilityHooksEnabled";
static NSString *const kNanoRegistryHooksEnabledKey = @"PairingCompatibilityNanoRegistryHooksEnabled";
static NSString *const kIDSHooksEnabledKey = @"PairingCompatibilityIDSHooksEnabled";
static NSString *const kMockIOSVersionHooksEnabledKey = @"PairingCompatibilityMockIOSVersionHooksEnabled";
static NSString *const kPassKitHooksEnabledKey = @"PairingCompatibilityPassKitHooksEnabled";
static NSString *const kBLEHooksEnabledKey = @"PairingCompatibilityBLEHooksEnabled";
static NSString *const kMockIOSMajorKey = @"PairingCompatibilityMockIOSMajorVersion";
static NSString *const kMockIOSMinorKey = @"PairingCompatibilityMockIOSMinorVersion";
static NSString *const kMockIOSBuildKey = @"PairingCompatibilityMockIOSBuild";

static long long kMinCompatibilityVersion = MIN_COMP;
static long long kMaxCompatibilityVersion = MAX_COMP;
static long long KHelloThresholdVersion = HELLO_COMP;
static BOOL kFrameworkHooksEnabled = YES;
static BOOL kNanoRegistryHooksEnabled = YES;
static BOOL kIDSHooksEnabled = YES;
static BOOL kMockIOSVersionHooksEnabled = YES;
static BOOL kPassKitHooksEnabled = YES;
static BOOL kBLEHooksEnabled = YES;

// Mock ios version
static NSOperatingSystemVersion kMockedOSVersion = { .majorVersion = OS_MAJOR, .minorVersion = OS_MINOR, .patchVersion = OS_PATCH };
static NSString *kMockOSVersionString = OS_VERSION;
static NSString *kMockOSVersionBuildString = OS_BUILD;

static void LoadPairingCompatibilityConfiguration(void) {
    NSInteger minValue = MAX(0, MIN(64, WFCurrentPluginIntegerConfigurationValue(kPairingMinKey, MIN_COMP)));
    NSInteger maxValue = MAX(minValue, MIN(64, WFCurrentPluginIntegerConfigurationValue(kPairingMaxKey, MAX_COMP)));
    NSInteger thresholdValue = MAX(0, MIN(64, WFCurrentPluginIntegerConfigurationValue(kHelloThresholdKey, HELLO_COMP)));

    kMinCompatibilityVersion = minValue;
    kMaxCompatibilityVersion = maxValue;
    KHelloThresholdVersion = thresholdValue;
    kFrameworkHooksEnabled = WFCurrentPluginBooleanConfigurationValue(kFrameworkHooksEnabledKey, YES);
    kNanoRegistryHooksEnabled = WFCurrentPluginBooleanConfigurationValue(kNanoRegistryHooksEnabledKey, YES);
    kIDSHooksEnabled = WFCurrentPluginBooleanConfigurationValue(kIDSHooksEnabledKey, YES);
    kMockIOSVersionHooksEnabled = WFCurrentPluginBooleanConfigurationValue(kMockIOSVersionHooksEnabledKey, YES);
    kPassKitHooksEnabled = WFCurrentPluginBooleanConfigurationValue(kPassKitHooksEnabledKey, YES);
    kBLEHooksEnabled = WFCurrentPluginBooleanConfigurationValue(kBLEHooksEnabledKey, YES);

    NSInteger mockMajor = MAX(14, MIN(30, WFCurrentPluginIntegerConfigurationValue(kMockIOSMajorKey, OS_MAJOR)));
    NSInteger mockMinor = MAX(0, MIN(20, WFCurrentPluginIntegerConfigurationValue(kMockIOSMinorKey, OS_MINOR)));
    kMockedOSVersion.majorVersion = mockMajor;
    kMockedOSVersion.minorVersion = mockMinor;
    kMockedOSVersion.patchVersion = 0;
    kMockOSVersionString = [NSString stringWithFormat:@"%ld.%ld.0", (long)mockMajor, (long)mockMinor];
    NSString *mockBuild = WFCurrentPluginStringConfigurationValue(kMockIOSBuildKey, nil);
    if (mockBuild.length > 0) {
        kMockOSVersionBuildString = mockBuild;
    } else {
        kMockOSVersionBuildString = OS_BUILD;
    }

    Log(@"Loaded PairingCompatibility configuration: min=%lld max=%lld hello=%lld framework=%@ nanoregistry=%@ ids=%@ mockIOS=%@ passkit=%@ ble=%@",
        kMinCompatibilityVersion,
        kMaxCompatibilityVersion,
        KHelloThresholdVersion,
        BoolString(kFrameworkHooksEnabled),
        BoolString(kNanoRegistryHooksEnabled),
        BoolString(kIDSHooksEnabled),
        BoolString(kMockIOSVersionHooksEnabled),
        BoolString(kPassKitHooksEnabled),
        BoolString(kBLEHooksEnabled));
}

%group PairingDaemoFix

%hook NRPairingDaemon

- (long long)maxPairingCompatibilityVersion {
    Log(@"Original maxPairingCompatibilityVersion called");
    long long originalVersion = %orig;
    Log(@"Original max compatibility version: %lld", originalVersion);
    return kMaxCompatibilityVersion;
}

- (long long)minPairingCompatibilityVersion {
    Log(@"Original minPairingCompatibilityVersion called");
    long long originalVersion = %orig;
    Log(@"Original min compatibility version: %lld", originalVersion);
    return kMinCompatibilityVersion;
}

%end

%end

%group PairingFrameworkFix

%hook NRPairingCompatibilityVersionInfo

- (long long)maxPairingCompatibilityVersion {
    Log(@"Original NRPairingCompatibilityVersionInfo maxPairingCompatibilityVersion called");
    long long originalVersion = %orig;
    Log(@"Original NRPairingCompatibilityVersionInfo max compatibility version: %lld", originalVersion);
    return kMaxCompatibilityVersion;
}

- (long long)minPairingCompatibilityVersion {
    Log(@"Original NRPairingCompatibilityVersionInfo minPairingCompatibilityVersion called");
    long long originalVersion = %orig;
    Log(@"Original NRPairingCompatibilityVersionInfo min compatibility version: %lld", originalVersion);
    return kMinCompatibilityVersion;
}

- (long long)minPairingCompatibilityVersionWithChipID {
    Log(@"Original NRPairingCompatibilityVersionInfo minPairingCompatibilityVersionWithChipID called");
    long long originalVersion = %orig;
    Log(@"Original NRPairingCompatibilityVersionInfo min compatibility version with chip ID: %lld", originalVersion);
    return kMinCompatibilityVersion;
}

- (long long)minQuickSwitchCompatibilityVersion {
    Log(@"Original NRPairingCompatibilityVersionInfo minQuickSwitchCompatibilityVersion called");
    long long originalVersion = %orig;
    Log(@"Original NRPairingCompatibilityVersionInfo min quick switch compatibility version: %lld", originalVersion);
    return kMinCompatibilityVersion;
}

- (long long)pairingCompatibilityVersion {
    Log(@"Original NRPairingCompatibilityVersionInfo pairingCompatibilityVersion called");
    long long originalVersion = %orig;
    Log(@"Original NRPairingCompatibilityVersionInfo pairing compatibility version: %lld", originalVersion);
    return kMaxCompatibilityVersion;
}

- (long long)minPairingCompatibilityVersionForChipID:(id)chipID name:(NSString *)name defaultVersion:(long long)defaultVersion {
    Log(@"Original NRPairingCompatibilityVersionInfo minPairingCompatibilityVersionForChipID:name:defaultVersion: called with chipID: %@, name: %@, defaultVersion: %lld",
          chipID,
          name,
          defaultVersion);
    return kMinCompatibilityVersion;
}

- (long long)minPairingCompatibilityVersionForChipID:(id)chipID {
    Log(@"Original NRPairingCompatibilityVersionInfo minPairingCompatibilityVersionForChipID: called with chipID: %@",
          chipID);
    return kMinCompatibilityVersion;
}

- (long long)minQuickSwitchPairingCompatibilityVersionForChipID:(id)chipID {
    Log(@"Original NRPairingCompatibilityVersionInfo minQuickSwitchPairingCompatibilityVersionForChipID: called with chipID: %@",
          chipID);
    return kMinCompatibilityVersion;
}

- (BOOL)isOverrideActive {
    Log(@"Original NRPairingCompatibilityVersionInfo isOverrideActive called");
    return YES;
}

%end

%hook NRDevice

// - (long long)compatibilityState {
//     Log(@"Original NRDevice compatibilityState called");
//     long long originalState = %orig;
//     Log(@"Original device compatibility state: %lld", originalState);
//     return 0; // Return compatible state
// }

- (BOOL)isCompatible {
    Log(@"Original NRDevice isCompatible called");
    BOOL originalCompatible = %orig;
    Log(@"Original device isCompatible: %@", BoolString(originalCompatible));
    return YES; // Force compatible
}

- (BOOL)isPairingCompatible {
    Log(@"Original NRDevice isPairingCompatible called");
    BOOL originalPairingCompatible = %orig;
    Log(@"Original device isPairingCompatible: %@", BoolString(originalPairingCompatible));
    return YES; // Force pairing compatible
}

- (id)valueForProperty:(id)property {
    id originalValue = %orig;
    if (property && [property isKindOfClass:[NSString class]]) {
        NSString *prop = (NSString *)property;
        // Log(@"Original NRDevice valueForProperty: called with property: %@, original value: %@", prop, originalValue);
        // if ([prop containsString:@"ompatibilityState"] || [prop containsString:@"ompatibility"]) {
        //     return @(0); // Force compatible state for any compatibility-related property
        // }
        if ([prop containsString:@"SystemVersion"] || [prop containsString:@"MarketingVersion"]) {
            return kMockOSVersionString; // Return mocked iOS version string for any system version-related property
        }
        if ([prop containsString:@"MaxPairingCompatibilityVersion"]) {
            return @(kMaxCompatibilityVersion);
        }
    }
    return originalValue;
}

%end

%hook NRMutableDevice

// - (long long)compatibilityState {
//     Log(@"Original NRDevice compatibilityState called");
//     long long originalState = %orig;
//     Log(@"Original device compatibility state: %lld", originalState);
//     return 0; // Return compatible state
// }

- (BOOL)isCompatible {
    Log(@"Original NRDevice isCompatible called");
    BOOL originalCompatible = %orig;
    Log(@"Original device isCompatible: %@", BoolString(originalCompatible));
    return YES; // Force compatible
}

- (BOOL)isPairingCompatible {
    Log(@"Original NRDevice isPairingCompatible called");
    BOOL originalPairingCompatible = %orig;
    Log(@"Original device isPairingCompatible: %@", BoolString(originalPairingCompatible));
    return YES; // Force pairing compatible
}

%end

%hook NRPairedDeviceRegistry

- (BOOL)canCommunicateOnRegularServicesWithDevice:(NRDevice *)device {
    Log(@"Original NRPairedDeviceRegistry canCommunicateOnRegularServicesWithDevice: called with device: %@", device);
    BOOL originalCanCommunicate = %orig(device);
    Log(@"Original can communicate on regular services with device: %@", BoolString(originalCanCommunicate));
    return YES; // Force can communicate
}

- (BOOL)canCommunicateOnRegularServicesWithActiveWatch {
    Log(@"Original NRPairedDeviceRegistry canCommunicateOnRegularServicesWithActiveWatch called");
    BOOL originalCanCommunicate = %orig;
    Log(@"Original can communicate on regular services with active watch: %@", BoolString(originalCanCommunicate));
    return YES; // Force can communicate
}

%end

%end

%group IdServicePairingFix

%hook IDSUTunControlMessage_Hello

-(void)setServiceMinCompatibilityVersion:(NSNumber *)serviceMinCompatibilityVersion {
    Log(@"Called setServiceMinCompatibilityVersion");
    NSInteger version = [serviceMinCompatibilityVersion integerValue];
    Log(@"Original service min compatibility version: %ld", (long)version);
    if (version < KHelloThresholdVersion) {
        version = kMaxCompatibilityVersion;
        Log(@"Modified service min compatibility version to: %ld", (long)version);
    }
    Log(@"Setting serviceMinCompatibilityVersion to: %ld", (long)version);
    NSNumber *modifiedVersion = [NSNumber numberWithInteger:version];
    [(NSObject *)self setValue:modifiedVersion forKey:@"_serviceMinCompatibilityVersion"];
    Log(@"Finished setServiceMinCompatibilityVersion");
}

%end

%hook IDSService

- (IDSServiceProperties *)initWithServiceDictionary:(NSDictionary *)serviceDictionary {
    Log(@"Original IDSService initWithServiceDictionary: called with dictionary: %@", serviceDictionary);
    NSMutableDictionary *modifiedDictionary = [serviceDictionary mutableCopy] ?: [NSMutableDictionary dictionary];
    if (modifiedDictionary[@"MinCompatibilityVersion"]) {
        modifiedDictionary[@"MinCompatibilityVersion"] = @(kMinCompatibilityVersion);
    }
    Log(@"Modified service dictionary for compatibility: %@", modifiedDictionary);
    return %orig(modifiedDictionary);
}

%end

%hook IDSServiceProperties

- (long long)minCompatibilityVersion {
    Log(@"Original IDSServiceProperties minCompatibilityVersion called");
    long long originalVersion = %orig;
    Log(@"Original service min compatibility version: %lld", originalVersion);
    return kMinCompatibilityVersion;
}

%end

%hook IDSAccount

- (BOOL)isServiceAvailable {
    Log(@"Original IDSAccount isServiceAvailable called");
    BOOL originalAvailability = %orig;
    Log(@"Original service availability: %@", BoolString(originalAvailability));
    return YES;
}

- (BOOL)isActive {
    Log(@"Original IDSAccount isActive called");
    BOOL originalActive = %orig;
    Log(@"Original account active state: %@", BoolString(originalActive));
    return YES;
}

- (BOOL)isEnabled {
    Log(@"Original IDSAccount isEnabled called");
    BOOL originalEnabled = %orig;
    Log(@"Original account enabled state: %@", BoolString(originalEnabled));
    return YES;
}

%end

%end

%group MockIOSVersion

%hook NSProcessInfo

- (NSOperatingSystemVersion)operatingSystemVersion {
    NSOperatingSystemVersion originalVersion = %orig;
    Log(@"Original operating system version: %ld.%ld.%ld",
          (long)originalVersion.majorVersion,
          (long)originalVersion.minorVersion,
          (long)originalVersion.patchVersion);
    NSOperatingSystemVersion modifiedVersion = kMockedOSVersion;
    Log(@"Modified operating system version: %ld.%ld.%ld",
          (long)modifiedVersion.majorVersion,
          (long)modifiedVersion.minorVersion,
          (long)modifiedVersion.patchVersion);
    return modifiedVersion;
}

- (NSString *)operatingSystemVersionString {
    NSString *originalVersionString = %orig;
    Log(@"Original operating system version string: %@", originalVersionString);
    NSString *modifiedVersionString = [NSString stringWithFormat:@"%@ (Build %@)", kMockOSVersionString, kMockOSVersionBuildString];
    Log(@"Modified operating system version string: %@", modifiedVersionString);
    return modifiedVersionString;
}

%end

%hook NSDictionary

+ (NSDictionary *)dictionaryWithContentsOfFile:(NSString *)path {
    NSDictionary *originalDictionary = %orig;
    if (path && [path containsString:@"SystemVersion.plist"]) {
        Log(@"Original dictionaryWithContentsOfFile: called with path: %@, original dictionary: %@", path, originalDictionary);
        NSMutableDictionary *modifiedDictionary = [originalDictionary mutableCopy] ?: [NSMutableDictionary dictionary];
        modifiedDictionary[@"ProductVersion"] = kMockOSVersionString;
        modifiedDictionary[@"BuildVersion"] = kMockOSVersionBuildString;
        Log(@"Modified dictionary for SystemVersion.plist: %@", modifiedDictionary);
        return [modifiedDictionary copy];
    }
    return originalDictionary;
}

%end

%end

%group PassKitPairingFix

%hook PKPassLibrary

- (BOOL)canAddPaymentPassForSecureElementIdentifier:(id)identifier {
    Log(@"PKPassLibrary.canAddPaymentPassForSecureElementIdentifier: -> YES (forced)");
    return YES;
}

- (BOOL)remoteSecureElementAvailable {
    Log(@"PKPassLibrary.remoteSecureElementAvailable -> YES (forced)");
    return YES;
}

- (BOOL)isPaymentPassActivationAvailable {
    Log(@"PKPassLibrary.isPaymentPassActivationAvailable -> YES (forced)");
    return YES;
}

%end

%end

%group BLEPairingFix

%hook CBDevice

- (void)setNearbyActionV2Type:(uint8_t)type {
    Log(@"[BLE] setNearbyActionV2Type=0x%02x", type);

    if (type == 0x00) {
        Log(@"[BLE] blocked NearbyActionV2Type=0x00");
        return;
    }

    %orig;
}

%end

%end

void InitFrameworkCompatibilityHooks(void) {
    Log(@"Initializing VersionInfo hooks...");
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(PairingFrameworkFix);
        Log(@"Initialized VersionInfo hooks");
    });
}

void InitNanoRegisterPairingCompatibilityHooks(void) {
    Log(@"Initializing PairingCompatibility hooks...");
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(PairingDaemoFix);
        Log(@"Initialized PairingCompatibility hooks");
    });
}

void InitIdServicePairingCompatibilityHooks(void) {
    Log(@"Initializing IdServicePairingFix hooks...");
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(IdServicePairingFix);
        Log(@"Initialized IdServicePairingFix hooks");
    });
}

void InitMockIOSVersionHooks(void) {
    Log(@"Initializing MockIOSVersion hooks...");
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(MockIOSVersion);
        Log(@"Initialized MockIOSVersion hooks");
    });
}

void InitPassKitPairingFixHooks(void) {
    Log(@"Initializing PassKitPairingFix hooks...");
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(PassKitPairingFix);
        Log(@"Initialized PassKitPairingFix hooks");
    });
}

void InitBLEPairingFixHooks(void) {
    Log(@"Initializing BLEPairingFix hooks...");
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(BLEPairingFix);
        Log(@"Initialized BLEPairingFix hooks");
    });
}

%ctor {
    @autoreleasepool {
        NSString *processName = [[NSProcessInfo processInfo] processName];
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        Log(@"Bundle ID   : %@", bundleID);
        Log(@"Program Name: %@", processName);

        LoadPairingCompatibilityConfiguration();

        if ([processName isEqualToString:@"nanoregistryd"] && kNanoRegistryHooksEnabled) {
            Log(@"Initializing PairingCompatibility...");
            InitNanoRegisterPairingCompatibilityHooks();
        }
        if (![processName isEqualToString:@"SpringBoard"] && kIDSHooksEnabled) {
            Log(@"Initializing IdServicePairingCompatibility...");
            InitIdServicePairingCompatibilityHooks();
        }
        if (([processName isEqualToString:@"passd"] || [processName isEqualToString:@"SpringBoard"]) && kPassKitHooksEnabled) {
            Log(@"Initializing PassKitPairingFix...");
            InitPassKitPairingFixHooks();
        }
        if ([processName isEqualToString:@"bluetoothd"] && kBLEHooksEnabled) {
            Log(@"Initializing BLEPairingFix...");
            InitBLEPairingFixHooks();
        }

        NSArray *watchOnlyDaemons = @[@"nanoregistryd", @"pairedsyncd", @"Bridge",
            @"companionproxyd", @"terminusd", @"nanoregistrylaunchd",
            @"appconduitd", @"nptocompaniond"];
        if ([watchOnlyDaemons containsObject:processName] && kMockIOSVersionHooksEnabled) {
            InitMockIOSVersionHooks();
        }

        if (kFrameworkHooksEnabled) {
            InitFrameworkCompatibilityHooks();
        }
    }
}
