#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include "APSSupport.h"
#include "utils.h"

static const char *WFSkipObjCTypeQualifiers(const char *type) {
    if (!type) {
        return NULL;
    }

    while (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' ||
           *type == 'O' || *type == 'R' || *type == 'V') {
        type++;
    }
    return type;
}

static BOOL WFIsIntegerArgumentType(const char *type) {
    type = WFSkipObjCTypeQualifiers(type);
    if (!type || !*type) {
        return NO;
    }

    switch (*type) {
        case 'c': case 'C':
        case 's': case 'S':
        case 'i': case 'I':
        case 'l': case 'L':
        case 'q': case 'Q':
        case 'B':
            return YES;
        default:
            return NO;
    }
}

static char *WFCopyThirdArgumentType(id object, SEL selector) {
    if (!object || !selector) {
        return NULL;
    }

    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (!method) {
        return NULL;
    }

    unsigned int argumentCount = method_getNumberOfArguments(method);
    if (argumentCount <= 2) {
        return NULL;
    }

    return method_copyArgumentType(method, 2);
}

static BOOL WFCallBoolMethodWithIntegerArgument(id object, SEL selector, NSInteger value, BOOL *result) {
    if (!object || !selector || !result || ![object respondsToSelector:selector]) {
        return NO;
    }

    char *argumentType = WFCopyThirdArgumentType(object, selector);
    BOOL isInteger = WFIsIntegerArgumentType(argumentType);

    if (!isInteger) {
        Log(@"APSSupport: refusing unsafe %@ call; arg2 type=%s",
            NSStringFromSelector(selector),
            argumentType ?: "<unknown>");
        if (argumentType) {
            free(argumentType);
        }
        return NO;
    }

    Log(@"APSSupport: %@ arg2 type=%s; using legacy integer interface=%ld",
        NSStringFromSelector(selector),
        argumentType,
        (long)value);
    free(argumentType);

    IMP implementation = [object methodForSelector:selector];
    if (!implementation) {
        return NO;
    }

    typedef BOOL (*WFBoolIntegerIMP)(id, SEL, NSInteger);
    *result = ((WFBoolIntegerIMP)implementation)(object, selector, value);
    return YES;
}

static BOOL ShouldReportProxyConnectedState(APSProxyClient *client) {
    if (!client || ![client respondsToSelector:@selector(isActive)]) {
        Log(@"APSSupport: missing APSProxyClient/isActive; skip proxy report");
        return NO;
    }

    if (![client isActive]) {
        Log(@"client is not active");
        return NO;
    }

    Log(@"client is active, checking whether legacy integer interface APIs are safe");

    SEL connectedSelector = NSSelectorFromString(@"isConnectedOnInterface:");
    SEL disconnectSelector = NSSelectorFromString(@"needsToDisconnectOnInterface:");

    // These private APIs are not ABI-stable. On the affected iOS 17.2.1
    // build, the observed apsd crash is consistent with the interface argument
    // no longer matching this tweak's hard-coded integer assumption. Only keep
    // the legacy 0/1 probing when runtime type encodings prove that BOTH
    // selectors still take an integer-like argument.
    char *connectedType = WFCopyThirdArgumentType(client, connectedSelector);
    char *disconnectType = WFCopyThirdArgumentType(client, disconnectSelector);
    BOOL legacyIntegerABI = WFIsIntegerArgumentType(connectedType) && WFIsIntegerArgumentType(disconnectType);

    Log(@"APSSupport runtime ABI: isConnectedOnInterface arg=%s, needsToDisconnectOnInterface arg=%s",
        connectedType ?: "<missing>",
        disconnectType ?: "<missing>");

    if (connectedType) free(connectedType);
    if (disconnectType) free(disconnectType);

    if (!legacyIntegerABI) {
        // incomingPresence itself is the strong signal that a live proxy peer
        // has just contacted apsd. Keep the active-client guard but do not guess
        // what object Apple now expects as the interface key.
        Log(@"APSSupport: non-integer/unknown interface ABI; skip unsafe interface probes and use active incoming-presence fallback");
        return YES;
    }

    for (NSInteger interface = 0; interface <= 1; interface++) {
        BOOL connected = NO;
        BOOL needsDisconnect = NO;

        if (!WFCallBoolMethodWithIntegerArgument(client, connectedSelector, interface, &connected) ||
            !WFCallBoolMethodWithIntegerArgument(client, disconnectSelector, interface, &needsDisconnect)) {
            Log(@"APSSupport: runtime ABI changed while probing; use active incoming-presence fallback");
            return YES;
        }

        Log(@"interface %ld: connected=%@ needsDisconnect=%@",
            (long)interface,
            BoolString(connected),
            BoolString(needsDisconnect));

        if (connected && !needsDisconnect) {
            Log(@"client is connected on interface %ld", (long)interface);
            return YES;
        }
    }

    Log(@"client is not connected on any legacy integer interface");
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
    Log(@"incomingPresence hook fired: hw=%@ sw=%@ build=%@",
          hwVersion,
          swVersion,
          swBuild);

    %orig;

    if (!ShouldReportProxyConnectedState(self)) {
        Log(@"proxy connected conditions not met, skip sendProxyIsConnected");
        return;
    }

    NSString *guid = CopyObjectIvarValueByName(self, "_guid", [NSString class]);
    APSEnvironment *environment = CopyObjectIvarValueByName(self, "_environment", NSClassFromString(@"APSEnvironment"));
    NSString *environmentName = [environment name];
    APSIDSProxyManager *proxyManager = [self proxyManager];

    if (guid.length == 0 || environmentName.length == 0 || !proxyManager) {
        Log(@"missing runtime state: guid=%@ environment=%@ proxyManager=%@",
              guid,
              environmentName,
              BoolString(proxyManager != nil));
        return;
    }

    Log(@"sending proxy connected: guid=%@ environment=%@",
          guid,
          environmentName);
    [proxyManager sendProxyIsConnected:YES guid:guid environmentName:environmentName];
}

%end

%end

%ctor {
    const char *progname = getprogname();
    if (!progname) {
        return;
    }
    // NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    // Log(@"Bundle ID   : %@", bundleID);
    // Log(@"Program Name: %@", StringFromCString(progname));
    if (is_equal(progname, "apsd")) {
        Log(@"Initializing APSSupport...");
        %init(APSSupport);
    }
}
