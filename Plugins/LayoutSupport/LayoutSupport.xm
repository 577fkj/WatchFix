#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

#include "utils.h"

static NSString *const kWFCarouselDomain = @"com.apple.Carousel";
static NSString *const kWFIconPositionsKey = @"IconPositions";
static NSString *const kWFNodesKey = @"nodes";
static NSString *const kWFBundleKey = @"Bundle";
static NSString *const kWFHexKey = @"Hex";
static NSString *const kWFReasonKey = @"Reason";
static NSString *const kWFDirectReasonKey = @"DirectReason";
static NSString *const kWFLastReasonKey = @"lastReason";
static NSString *const kWFVerticalOnlyKey = @"verticalOnly";
static NSString *const kWFSyncManagerIvarName = @"_syncManager";
static NSString *const kWFCarouselSettingsBundlePath =
    @"/System/Library/NanoPreferenceBundles/Customization/CarouselAppViewSettings.bundle";
static NSString *const kWFReversePlacementExceptionReason =
    @"Reverse emplacement failed; orphaned node detected in WatchFix 3-4-3 layout support";
static NSString *const kWFIntegrityExceptionReason =
    @"Failed integrity check in WatchFix 3-4-3 layout support";

typedef struct {
    int32_t low;
    int32_t high;
} WFHex;

@interface WFHexAppNode : NSObject
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier hex:(WFHex)hex;
- (NSString *)bundleIdentifier;
- (WFHex)hex;
@end

@interface WFHexAppGraph : NSObject <NSFastEnumeration>
- (instancetype)initWithNodes:(NSArray *)nodes;
- (NSArray *)allNodes;
- (NSMutableSet *)changedNodes;
- (id)delegate;
- (NSUInteger)count;
- (BOOL)containsNodeAtHex:(WFHex)hex;
- (id)nodeAtHex:(WFHex)hex;
- (void)setNode:(id)node toHex:(WFHex)hex;
- (void)moveNode:(id)node toHex:(WFHex)hex;
- (void)removeNodeWithoutReflow:(id)node;
- (void)revertMove;
@end

@interface WFDomainAccessor : NSObject
- (instancetype)initWithDomain:(NSString *)domain;
- (NSDictionary *)dictionaryForKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
- (BOOL)synchronize;
@end

@interface WFSyncManager : NSObject
- (void)synchronizeNanoDomain:(NSString *)domain keys:(NSSet *)keys;
@end

@interface WFGraphDelegate : NSObject
- (void)hexAppGraph:(id)graph
         addedNodes:(NSArray *)addedNodes
       removedNodes:(NSArray *)removedNodes
         movedNodes:(NSArray *)movedNodes;
@end

@interface WFIconPositionsStoreClass : NSObject
@end

@interface WFHexGraphClass : WFHexAppGraph
@end

@interface NSObject (LayoutSupport)
- (void)wf_layout_setGraphIsVertical:(BOOL)value;
- (BOOL)wf_layout_graphIsVertical;
@end

static char kWFVerticalGraphAssociationKey;

@implementation NSObject (LayoutSupport)

- (void)wf_layout_setGraphIsVertical:(BOOL)value {
    objc_setAssociatedObject(
        self,
        &kWFVerticalGraphAssociationKey,
        @(value),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)wf_layout_graphIsVertical {
    id boxed = objc_getAssociatedObject(self, &kWFVerticalGraphAssociationKey);
    return [boxed respondsToSelector:@selector(boolValue)] ? [boxed boolValue] : NO;
}

@end

static inline WFHex WFHexMake(int32_t low, int32_t high) {
    WFHex hex;
    hex.low = low;
    hex.high = high;
    return hex;
}

static inline BOOL WFHexEqual(WFHex lhs, WFHex rhs) {
    return lhs.low == rhs.low && lhs.high == rhs.high;
}

static NSInteger WFRowIndexForHex(WFHex hex) {
    return (NSInteger)hex.high + 2;
}

static int32_t WFRowStartForIndex(NSUInteger rowIndex) {
    return -((int32_t)((rowIndex + 1) / 2));
}

static NSUInteger WFRowLengthForIndex(NSUInteger rowIndex) {
    return (rowIndex % 2 == 0) ? 3U : 4U;
}

static BOOL WFHexIsInVerticalDomain(WFHex hex) {
    NSInteger rowIndex = WFRowIndexForHex(hex);
    if (rowIndex < 0) {
        return NO;
    }

    int32_t start = WFRowStartForIndex((NSUInteger)rowIndex);
    NSUInteger length = WFRowLengthForIndex((NSUInteger)rowIndex);
    return hex.low >= start && hex.low < start + (int32_t)length;
}

static NSUInteger WFHexRank(WFHex hex) {
    if (!WFHexIsInVerticalDomain(hex)) {
        return NSNotFound;
    }

    NSUInteger rowIndex = (NSUInteger)WFRowIndexForHex(hex);
    NSUInteger slotsBefore = (rowIndex / 2U) * 7U + ((rowIndex % 2U) ? 3U : 0U);
    int32_t start = WFRowStartForIndex(rowIndex);
    return slotsBefore + (NSUInteger)(hex.low - start);
}

static WFHex WFSlotAtRank(NSUInteger rank) {
    NSUInteger pairIndex = rank / 7U;
    NSUInteger offset = rank % 7U;
    NSUInteger rowIndex = pairIndex * 2U;
    NSUInteger offsetInRow = offset;
    if (offset >= 3U) {
        rowIndex += 1U;
        offsetInRow -= 3U;
    }

    return WFHexMake(WFRowStartForIndex(rowIndex) + (int32_t)offsetInRow, (int32_t)rowIndex - 2);
}

static WFHex WFNextHexFromState(WFHex *state) {
    if (!state || state->high < -2) {
        if (state) {
            state->low = 1;
            state->high = -2;
        }
        return WFHexMake(0, -2);
    }

    NSInteger rowIndex = WFRowIndexForHex(*state);
    if (rowIndex < 0) {
        state->low = 1;
        state->high = -2;
        return WFHexMake(0, -2);
    }

    int32_t start = WFRowStartForIndex((NSUInteger)rowIndex);
    NSUInteger length = WFRowLengthForIndex((NSUInteger)rowIndex);
    if (state->low < start) {
        state->low = start;
    }

    if (state->low >= start + (int32_t)length) {
        rowIndex += 1;
        start = WFRowStartForIndex((NSUInteger)rowIndex);
        state->low = start;
        state->high = (int32_t)rowIndex - 2;
    }

    WFHex result = *state;
    state->low += 1;
    return result;
}

static NSComparisonResult WFCompareHexes(WFHex lhs, WFHex rhs) {
    NSUInteger lhsRank = WFHexRank(lhs);
    NSUInteger rhsRank = WFHexRank(rhs);
    if (lhsRank != NSNotFound && rhsRank != NSNotFound) {
        if (lhsRank < rhsRank) {
            return NSOrderedAscending;
        }
        if (lhsRank > rhsRank) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }

    if (lhs.high != rhs.high) {
        return lhs.high < rhs.high ? NSOrderedAscending : NSOrderedDescending;
    }
    if (lhs.low != rhs.low) {
        return lhs.low < rhs.low ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

static NSArray *WFOrderedNodes(id graph) {
    NSArray *allNodes = [graph allNodes];
    return [allNodes sortedArrayUsingComparator:^NSComparisonResult(id lhs, id rhs) {
        WFHex lhsHex = [lhs hex];
        WFHex rhsHex = [rhs hex];
        NSComparisonResult result = WFCompareHexes(lhsHex, rhsHex);
        if (result != NSOrderedSame) {
            return result;
        }

        NSString *lhsBundle = [lhs bundleIdentifier];
        NSString *rhsBundle = [rhs bundleIdentifier];
        if ([lhsBundle isKindOfClass:[NSString class]] && [rhsBundle isKindOfClass:[NSString class]]) {
            return [lhsBundle compare:rhsBundle];
        }
        return NSOrderedSame;
    }];
}

static id WFCreateDomainAccessor(void) {
    Class accessorClass = objc_lookUpClass("NPSDomainAccessor");
    if (!accessorClass) {
        Log("NPSDomainAccessor is unavailable");
        return nil;
    }

    return [[accessorClass alloc] initWithDomain:kWFCarouselDomain];
}

static BOOL WFValidateContiguousGraphOccupancy(id graph) {
    NSArray *orderedNodes = WFOrderedNodes(graph);
    NSUInteger expectedIndex = 0;
    for (id node in orderedNodes) {
        if (!WFHexEqual([node hex], WFSlotAtRank(expectedIndex))) {
            return NO;
        }
        expectedIndex += 1;
    }
    return YES;
}

static WFHex WFFirstAvailable343Hex(id graph) {
    WFHex state = WFHexMake(0, -2);
    while ([graph containsNodeAtHex:WFNextHexFromState(&state)]) {
    }
    return WFHexMake(state.low - 1, state.high);
}

static void WFPlaceNodesAsContiguousPrefix(id graph, NSArray *orderedNodes) {
    NSMutableSet *changedNodes = [graph changedNodes];
    NSUInteger index = 0;
    for (id node in orderedNodes) {
        WFHex desiredHex = WFSlotAtRank(index);
        if (!WFHexEqual([node hex], desiredHex)) {
            [graph setNode:node toHex:desiredHex];
            [changedNodes addObject:node];
        }
        index += 1;
    }
}

static void WFCompactVerticalGraph(id graph) {
    if (![graph wf_layout_graphIsVertical]) {
        return;
    }

    WFPlaceNodesAsContiguousPrefix(graph, WFOrderedNodes(graph));
}

static void WFNotifyDelegateAboutMovedNodes(id graph) {
    NSSet *changedNodes = [graph changedNodes];
    if ([changedNodes count] == 0) {
        return;
    }

    id delegate = [graph delegate];
    SEL selector = @selector(hexAppGraph:addedNodes:removedNodes:movedNodes:);
    if (![delegate respondsToSelector:selector]) {
        return;
    }

    [(WFGraphDelegate *)delegate hexAppGraph:graph
                                  addedNodes:nil
                                removedNodes:nil
                                  movedNodes:[changedNodes allObjects]];
}

%group LayoutSupportIconPositionsStoreHooks

%hook WFIconPositionsStoreClass

- (id)loadPositions {
    id domainAccessor = WFCreateDomainAccessor();
    if (!domainAccessor) {
        return %orig;
    }

    [domainAccessor synchronize];
    NSDictionary *iconPositionsDictionary = [domainAccessor dictionaryForKey:kWFIconPositionsKey];
    if (![iconPositionsDictionary isKindOfClass:[NSDictionary class]]) {
        return %orig;
    }

    NSArray *serializedNodes = iconPositionsDictionary[kWFNodesKey];
    if (![serializedNodes isKindOfClass:[NSArray class]]) {
        return nil;
    }

    Class nodeClass = objc_lookUpClass("CSLHexAppNode");
    Class graphClass = objc_lookUpClass("CSLHexAppGraph");
    if (!nodeClass || !graphClass) {
        Log("failed to rebuild layout graph because required classes are unavailable");
        return %orig;
    }

    NSMutableArray *rebuiltNodes = [NSMutableArray arrayWithCapacity:[serializedNodes count]];
    for (id entry in serializedNodes) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSString *bundleIdentifier = entry[kWFBundleKey];
        NSArray *hexArray = entry[kWFHexKey];
        if (![bundleIdentifier isKindOfClass:[NSString class]] ||
            [bundleIdentifier length] == 0 ||
            ![hexArray isKindOfClass:[NSArray class]] ||
            [hexArray count] != 2) {
            continue;
        }

        NSNumber *lowValue = [hexArray firstObject];
        NSNumber *highValue = [hexArray lastObject];
        if (![lowValue isKindOfClass:[NSNumber class]] || ![highValue isKindOfClass:[NSNumber class]]) {
            continue;
        }

        id node = [[nodeClass alloc] initWithBundleIdentifier:bundleIdentifier
                                                          hex:WFHexMake([lowValue intValue], [highValue intValue])];
        if (node) {
            [rebuiltNodes addObject:node];
        }
    }

    id graph = [[graphClass alloc] initWithNodes:rebuiltNodes];
    if (!graph) {
        return %orig;
    }

    [graph wf_layout_setGraphIsVertical:YES];

    if (!WFValidateContiguousGraphOccupancy(graph)) {
        for (id node in [graph allNodes]) {
            if (!WFHexIsInVerticalDomain([node hex])) {
                [graph setNode:node toHex:WFFirstAvailable343Hex(graph)];
            }
        }
        [[graph changedNodes] removeAllObjects];
        WFCompactVerticalGraph(graph);
    }

    return graph;
}

- (void)savePositions:(id)graph {
    if (![graph wf_layout_graphIsVertical]) {
        %orig;
        return;
    }

    id domainAccessor = WFCreateDomainAccessor();
    if (!domainAccessor) {
        %orig;
        return;
    }

    if (graph) {
        NSMutableArray *serializedNodes = [NSMutableArray array];
        for (id node in WFOrderedNodes(graph)) {
            NSString *bundleIdentifier = [node bundleIdentifier];
            if (![bundleIdentifier isKindOfClass:[NSString class]] || [bundleIdentifier length] == 0) {
                continue;
            }

            WFHex hex = [node hex];
            [serializedNodes addObject:@{
                kWFHexKey: @[@(hex.low), @(hex.high)],
                kWFBundleKey: bundleIdentifier,
                kWFReasonKey: @2,
                kWFDirectReasonKey: @1,
            }];
        }

        NSDictionary *iconPositionsDictionary = @{
            kWFNodesKey: serializedNodes,
            kWFLastReasonKey: @2,
            kWFVerticalOnlyKey: @YES,
        };
        [domainAccessor setObject:iconPositionsDictionary forKey:kWFIconPositionsKey];
    } else {
        [domainAccessor removeObjectForKey:kWFIconPositionsKey];
    }

    [domainAccessor synchronize];

    id syncManager = [self valueForKey:kWFSyncManagerIvarName];
    Class syncManagerClass = objc_lookUpClass("NPSManager");
    if (syncManagerClass && [syncManager isKindOfClass:syncManagerClass]) {
        [(WFSyncManager *)syncManager synchronizeNanoDomain:kWFCarouselDomain
                                                       keys:[NSSet setWithObject:kWFIconPositionsKey]];
    }
}

%end

%end

%group LayoutSupportHexGraphHooks

%hook WFHexGraphClass

- (BOOL)isLonelyHex:(WFHex)hex {
    if ([self wf_layout_graphIsVertical]) {
        return NO;
    }
    return %orig;
}

- (WFHex)firstGoodEmptyHex {
    if ([self wf_layout_graphIsVertical]) {
        return WFFirstAvailable343Hex(self);
    }
    return %orig;
}

- (void)collapseToHex:(WFHex)hex ignoringNode:(id)ignoredNode {
    if ([self wf_layout_graphIsVertical]) {
        (void)hex;
        (void)ignoredNode;
        WFCompactVerticalGraph(self);
        return;
    }
    %orig;
}

- (void)moveNode:(id)node toHex:(WFHex)targetHex final:(BOOL)finalFlag {
    if (![self wf_layout_graphIsVertical]) {
        %orig;
        return;
    }

    (void)finalFlag;
    if (!node) {
        return;
    }

    NSMutableSet *changedNodes = [self changedNodes];
    [changedNodes removeAllObjects];

    WFHex currentHex = [node hex];
    if (WFHexEqual(currentHex, targetHex) || !WFHexIsInVerticalDomain(targetHex)) {
        return;
    }

    [self revertMove];

    NSArray *orderedNodes = WFOrderedNodes(self);
    NSUInteger originalIndex = [orderedNodes indexOfObjectIdenticalTo:node];
    if (originalIndex == NSNotFound) {
        return;
    }

    NSMutableArray *reorderedNodes = [orderedNodes mutableCopy];
    [reorderedNodes removeObjectAtIndex:originalIndex];

    NSUInteger insertionIndex = WFHexRank(targetHex);
    if (insertionIndex == NSNotFound) {
        return;
    }
    if (insertionIndex > [reorderedNodes count]) {
        insertionIndex = [reorderedNodes count];
    }

    [reorderedNodes insertObject:node atIndex:insertionIndex];
    WFPlaceNodesAsContiguousPrefix(self, reorderedNodes);

    if (!WFValidateContiguousGraphOccupancy(self)) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:kWFIntegrityExceptionReason
                                     userInfo:nil];
    }

    WFNotifyDelegateAboutMovedNodes(self);
}

%end

%end

static BOOL WFInstallLayoutSupportHooks(void) {
    if (isOSVersionAtLeast(17, 0, 0)) {
        Log("LayoutSupport is not needed on iOS 17 or later");
        return NO;
    }

    NSBundle *bundle = [NSBundle bundleWithPath:kWFCarouselSettingsBundlePath];
    if (!bundle || ![bundle load]) {
        Log("failed to load CarouselAppViewSettings.bundle");
        return NO;
    }

    Class iconPositionsStoreClass = objc_lookUpClass("CSLIconPositionsStore");
    Class hexGraphClass = objc_lookUpClass("CSLHexAppGraph");
    if (!iconPositionsStoreClass || !hexGraphClass) {
        Log("required carousel classes are unavailable");
        return NO;
    }

    %init(LayoutSupportIconPositionsStoreHooks, WFIconPositionsStoreClass=iconPositionsStoreClass);
    %init(LayoutSupportHexGraphHooks, WFHexGraphClass=hexGraphClass);

    Log("LayoutSupport hooks installed");
    return YES;
}

%ctor {
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    const char *programName = getprogname();
    Log("Bundle ID   : %s", CStringOrPlaceholder(bundleIdentifier));
    Log("Program Name: %s", programName ? programName : "<nil>");

    if (![bundleIdentifier isEqualToString:@"com.apple.Bridge"]) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WFInstallLayoutSupportHooks();
    });
}
