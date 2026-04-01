#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dispatch/dispatch.h>
#include <substrate.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "../utils/utils.h"

static long long minPairingCompatibilityVersionWithChipID = 1;
static long long minCompatibilityVersion = 1;
static long long maxCompatibilityVersion = 40;

%group PairingDaemoFix

%hook NRPairingDaemon

- (long long)maxPairingCompatibilityVersion {
    Log("Original maxPairingCompatibilityVersion called");
    long long originalVersion = %orig;
    Log("Original max compatibility version: %lld", originalVersion);
    return maxCompatibilityVersion;
}

- (long long)minPairingCompatibilityVersion {
    Log("Original minPairingCompatibilityVersion called");
    long long originalVersion = %orig;
    Log("Original min compatibility version: %lld", originalVersion);
    return minCompatibilityVersion;
}

%end

%end

%group PairingFrameworkFix

%hook VersionInfo

- (long long)maxPairingCompatibilityVersion {
    Log("Original VersionInfo maxPairingCompatibilityVersion called");
    long long originalVersion = %orig;
    Log("Original VersionInfo max compatibility version: %lld", originalVersion);
    return maxCompatibilityVersion;
}

- (long long)minPairingCompatibilityVersion {
    Log("Original VersionInfo minPairingCompatibilityVersion called");
    long long originalVersion = %orig;
    Log("Original VersionInfo min compatibility version: %lld", originalVersion);
    return minCompatibilityVersion;
}

- (long long)minPairingCompatibilityVersionWithChipID {
    Log("Original VersionInfo minPairingCompatibilityVersionWithChipID called");
    long long originalVersion = %orig;
    Log("Original VersionInfo min compatibility version with chip ID: %lld", originalVersion);
    return minPairingCompatibilityVersionWithChipID;
}

- (long long)minPairingCompatibilityVersionForChipID:(id)chipID name:(NSString *)name defaultVersion:(long long)defaultVersion {
    Log("Original VersionInfo minPairingCompatibilityVersionForChipID:name:defaultVersion: called with chipID: %u, name: %s, defaultVersion: %lld", chipID, CStringOrPlaceholder(name), defaultVersion);
    return defaultVersion;
}

%end

%end

%group IdServicePairingFix

%hook IDSUTunControlMessage_Hello

-(void)setServiceMinCompatibilityVersion:(NSNumber *)serviceMinCompatibilityVersion {
    Log("Called setServiceMinCompatibilityVersion");
    NSInteger version = [serviceMinCompatibilityVersion integerValue];
    Log("Original service min compatibility version: %ld", (long)version);
    if (version < 18) {
        version = maxCompatibilityVersion;
        Log("Modified service min compatibility version to: %ld", (long)version);
    }
    Log("Setting serviceMinCompatibilityVersion to: %ld", (long)version);
    NSNumber *modifiedVersion = [NSNumber numberWithInteger:version];
    [(NSObject *)self setValue:modifiedVersion forKey:NSSTR("_serviceMinCompatibilityVersion")];
    Log("Finished setServiceMinCompatibilityVersion");
}

%end

%end

static bool isHookerInitialized = false;

void InitFrameworkCompatibilityHooks(void) {
    Class versionInfoClass = objc_lookUpClass("NRPairingCompatibilityVersionInfo");
    if (!versionInfoClass) {
        Log("NRPairingCompatibilityVersionInfo class not found, skipping VersionInfo hooks");
        return;
    }
    
    %init(PairingFrameworkFix, VersionInfo=versionInfoClass);
}

void InitNanoRegisterPairingCompatibilityHooks(void) {
    Log("Initializing PairingCompatibility hooks...");
    if (isHookerInitialized) {
        Log("PairingCompatibility hooks already initialized, skipping...");
        return;
    }
    isHookerInitialized = true;

    %init(PairingDaemoFix);

    InitFrameworkCompatibilityHooks();
}

void InitIdServicePairingCompatibilityHooks(void) {
    Log("Initializing IdServicePairingFix hooks...");
    if (isHookerInitialized) {
        Log("IdServicePairingFix hooks already initialized, skipping...");
        return;
    }
    isHookerInitialized = true;

    %init(IdServicePairingFix);

    InitFrameworkCompatibilityHooks();
}
