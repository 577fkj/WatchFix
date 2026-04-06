#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include "APSSupport.h"
#include "utils.h"

static BOOL ShouldReportProxyConnectedState(APSProxyClient *client) {
    if (![client isActive]) {
        Log("client is not active");
        return NO;
    }

    Log("client is active, checking interfaces");
    if ([client isConnectedOnInterface:0] && ![client needsToDisconnectOnInterface:0]) {
        Log("client is connected on interface 0");
        return YES;
    }
    Log("client is not connected on interface 0");
    Log("isConnectedOnInterface:0=%s needsToDisconnectOnInterface:0=%s",
           [client isConnectedOnInterface:0] ? "YES" : "NO",
           [client needsToDisconnectOnInterface:0] ? "YES" : "NO");

    Log("checking interface 1 for fallback");
    if ([client isConnectedOnInterface:1] && ![client needsToDisconnectOnInterface:1]) {
        Log("client is connected on interface 1");
        return YES;
    }
    Log("client is not connected on interface 1");
    Log("isConnectedOnInterface:1=%s needsToDisconnectOnInterface:1=%s",
           [client isConnectedOnInterface:1] ? "YES" : "NO",
           [client needsToDisconnectOnInterface:1] ? "YES" : "NO");

    Log("client is not connected on any interface");
    return NO;
}

%group APSSupport

%hook APSProxyClient

- (void)incomingPresenceWithCertificate:(NSData *)certificate
                                  nonce:(NSData *)nonce
                                signature:(NSData *)signature
                                  token:(NSData *)token
                              hwVersion:(NSString *)hwVersion
                              swVersion:(NSString *)swVersion
                                swBuild:(NSString *)swBuild {
    Log("incomingPresence hook fired: hw=%s sw=%s build=%s",
           CStringOrPlaceholder(hwVersion),
           CStringOrPlaceholder(swVersion),
           CStringOrPlaceholder(swBuild));

    %orig;

    if (!ShouldReportProxyConnectedState(self)) {
        Log("proxy connected conditions not met, skip sendProxyIsConnected");
        return;
    }

    NSString *guid = CopyObjectIvarValueByName(self, "_guid", [NSString class]);
    APSEnvironment *environment = CopyObjectIvarValueByName(self, "_environment", NSClassFromString(@"APSEnvironment"));
    NSString *environmentName = [environment name];
    APSIDSProxyManager *proxyManager = [self proxyManager];

    if (guid.length == 0 || environmentName.length == 0 || !proxyManager) {
        Log("missing runtime state: guid=%s environment=%s proxyManager=%s",
               CStringOrPlaceholder(guid),
               CStringOrPlaceholder(environmentName),
               proxyManager ? "YES" : "NO");
        return;
    }

    Log("sending proxy connected: guid=%s environment=%s",
           CStringOrPlaceholder(guid),
           CStringOrPlaceholder(environmentName));
    [proxyManager sendProxyIsConnected:YES guid:guid environmentName:environmentName];
}

%end

%end

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
        %init(APSSupport);
    }
}