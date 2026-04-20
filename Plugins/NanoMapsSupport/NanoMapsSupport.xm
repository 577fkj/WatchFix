#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdlib.h>

#include "utils.h"

static NSUInteger const kWFNMSMinimumWaypointLength = 3;

@interface NMArgument : NSObject
- (void)setTag:(NSInteger)tag;
- (void)setDataValue:(NSData *)value;
- (NSArray *)dataListValues;
@end

@interface NMSPreviewMessage : NSObject
- (NSInteger)type;
- (id)argumentForTag:(NSInteger)tag;
- (void)addArgument:(id)argument;
- (NSMutableArray *)arguments;
- (NSArray *)dataListValues;
@end

@interface NMSGeoMapItem : NSObject
- (void)readAll:(BOOL)readAll;
@end

static void WatchFixRewritePreviewWaypoints(id previewMessage) {
    if (!previewMessage) {
        return;
    }

    NMSPreviewMessage *typedPreviewMessage = (NMSPreviewMessage *)previewMessage;
    if ([typedPreviewMessage type] != 304) {
        return;
    }

    NMArgument *waypointListArgument = (NMArgument *)[typedPreviewMessage argumentForTag:417];
    if (!waypointListArgument) {
        return;
    }

    NSArray *dataListValues = [waypointListArgument dataListValues];
    NSData *firstWaypoint = [dataListValues firstObject];
    NSData *lastWaypoint = [dataListValues lastObject];
    if (!firstWaypoint || !lastWaypoint) {
        return;
    }

    Class argumentClass = NSClassFromString(@"NMArgument");
    if (!argumentClass) {
        Log(@"NMArgument class not found, skipping waypoint rewrite");
        return;
    }

    if (firstWaypoint.length >= kWFNMSMinimumWaypointLength) {
        NMArgument *startArgument = [[argumentClass alloc] init];
        [startArgument setTag:404];
        [startArgument setDataValue:firstWaypoint];
        [typedPreviewMessage addArgument:startArgument];
    }

    if (lastWaypoint.length >= kWFNMSMinimumWaypointLength) {
        NMArgument *endArgument = [[argumentClass alloc] init];
        [endArgument setTag:405];
        [endArgument setDataValue:lastWaypoint];
        [typedPreviewMessage addArgument:endArgument];
    }

    id arguments = [typedPreviewMessage arguments];
    if ([arguments isKindOfClass:[NSMutableArray class]]) {
        [arguments removeObject:waypointListArgument];
    }
}

%group NanoMapsSupport

%hook NMSRoutePlanningControllerClass

- (void)_handlePreviewNavMessage:(id)previewMessage {
    WatchFixRewritePreviewWaypoints(previewMessage);
    %orig(previewMessage);
}

%end

%hook NMSNanoDirectionWaypointClass

- (void)setGeoMapItem:(id)geoMapItem {
    if (geoMapItem && [geoMapItem respondsToSelector:@selector(readAll:)]) {
        [(NMSGeoMapItem *)geoMapItem readAll:YES];
    }
    %orig(geoMapItem);
}

%end

%end

%ctor {
    const char *progname = getprogname();
    if (!progname) {
        return;
    }

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    Log(@"Bundle ID   : %@", bundleID);
    Log(@"Program Name: %@", StringFromCString(progname));

    if (IOSVersionAtLeast(16, 0, 0)) {
        Log(@"host is iOS 16.0.0 or later, skipping NanoMapsSupport");
        return;
    }

    if (!is_equal(progname, "nanomapscd")) {
        return;
    }

    Class routePlanningControllerClass = objc_lookUpClass("NMCRoutePlanningController");
    Class nanoDirectionWaypointClass = objc_lookUpClass("NanoDirectionWaypoint");
    if (!routePlanningControllerClass || !nanoDirectionWaypointClass) {
        Log(@"required Maps classes not found: route=%@ waypoint=%@",
              BoolString(routePlanningControllerClass != Nil),
              BoolString(nanoDirectionWaypointClass != Nil));
        return;
    }

    Log(@"initializing NanoMapsSupport in %@", StringFromCString(progname));
    %init(NanoMapsSupport,
        NMSRoutePlanningControllerClass=routePlanningControllerClass,
        NMSNanoDirectionWaypointClass=nanoDirectionWaypointClass);
}
