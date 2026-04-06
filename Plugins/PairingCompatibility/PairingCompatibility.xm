#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dispatch/dispatch.h>
#include <substrate.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "utils.h"

static long long minCompatibilityVersion = 4;
static long long maxCompatibilityVersion = 24;

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
    return minCompatibilityVersion;
}

- (long long)minPairingCompatibilityVersionForChipID:(id)chipID name:(NSString *)name defaultVersion:(long long)defaultVersion {
    Log("Original VersionInfo minPairingCompatibilityVersionForChipID:name:defaultVersion: called with chipID: %u, name: %s, defaultVersion: %lld", chipID, CStringOrPlaceholder(name), defaultVersion);
    return minCompatibilityVersion;
}

%end

%end

%group IdServicePairingFix

%hook IDSHello

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
    [(NSObject *)self setValue:modifiedVersion forKey:@"_serviceMinCompatibilityVersion"];
    Log("Finished setServiceMinCompatibilityVersion");
}

%end

%end

void InitFrameworkCompatibilityHooks(void) {
    Class versionInfoClass = objc_lookUpClass("NRPairingCompatibilityVersionInfo");
    if (!versionInfoClass) {
        Log("NRPairingCompatibilityVersionInfo class not found, skipping VersionInfo hooks");
        return;
    }
    
    Log("Initializing VersionInfo hooks...");
    %init(PairingFrameworkFix, VersionInfo=versionInfoClass);
}

void InitNanoRegisterPairingCompatibilityHooks(void) {
    Log("Initializing PairingCompatibility hooks...");
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Log("Initializing PairingDaemon hooks...");
        %init(PairingDaemoFix);
    });
}

void InitIdServicePairingCompatibilityHooks(void) {
    Log("Initializing IdServicePairingFix hooks...");
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class IDSHelloClass = objc_lookUpClass("IDSUTunControlMessage_Hello");
        if (IDSHelloClass) {
            Log("Found IDSUTunControlMessage_Hello class, initializing IdServicePairingFix hooks...");
            %init(IdServicePairingFix, IDSHello=IDSHelloClass);
        } else {
            Log("IDSUTunControlMessage_Hello class not found, skipping IdServicePairingFix hooks");
        }
    });
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
    if (is_equal(progname, "nanoregistryd")) {
        Log("Initializing PairingCompatibility...");
        InitNanoRegisterPairingCompatibilityHooks();
    }
    else if (is_equal(progname, "identityservicesd")) {
        Log("Initializing IdServicePairingCompatibility...");
        InitIdServicePairingCompatibilityHooks();
    }
    
    InitFrameworkCompatibilityHooks();
}
