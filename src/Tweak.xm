#import <Foundation/Foundation.h>
#import "utils/utils.h"

#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

#import "plugins/APSSupport.h"
#import "plugins/PairingCompatibility.h"
#import "plugins/AppsSupport.h"
#import "plugins/WatchAppSupport.h"

%ctor {
    const char *progname = getprogname();
    if (!progname) {
        return;
    }

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    const char *bundleIDCString = [bundleID UTF8String];
    Log("Bundle ID   : %s", bundleIDCString);
    Log("Program Name: %s", progname);

    if (is_equal(progname, "apsd")) {
        Log("Initializing APSSupport...");
        InitAPSSupportHooks();
    }
    else if (is_equal(progname, "appconduitd")) {
        Log("Initializing AppsSupport...");
        InstallAppConduitHook();
    }
    else if (is_equal(progname, "installd") ||
            is_equal(progname, "MobileInstallationHelperService") ||
            is_equal(progname, "com.apple.MobileInstallationHelperService")) {
        Log("Initializing AppsSupport...");
        InstallAppsSupportHooks();
    }
    else if (is_equal(progname, "nanoregistryd")) {
        Log("Initializing PairingCompatibility...");
        InitNanoRegisterPairingCompatibilityHooks();
    }
    else if (is_equal(progname, "identityservicesd")) {
        Log("Initializing IdServicePairingCompatibility...");
        InitIdServicePairingCompatibilityHooks();
    }
    else if (is_equal(bundleIDCString, "com.apple.Bridge") ||
             is_equal(bundleIDCString, "com.apple.SharingViewService") ||
             is_equal(progname, "SharingViewService")) {
        Log("Initializing WatchAppSupport...");
        InitWatchAppSupportHooks();
    }
}
