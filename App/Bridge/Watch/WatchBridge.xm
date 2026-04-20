#import "WatchBridge.h"
#import "../Internal/BridgeInternal.h"
#import "Logging.h"

#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/runtime.h>

@implementation WFCompatibilityReport

- (NSString *)stateDescription {
    switch (self.state) {
        case WFCompatibilityReportStateCompatible:          return @"compatible";
        case WFCompatibilityReportStateNeedsPairingSupport: return @"needsPairingSupport";
        case WFCompatibilityReportStateUnavailable:         return @"unavailable";
        default:                                            return @"indeterminate";
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:
        @"<WFCompatibilityReport: source=%@, state=%@, hasActiveWatch=%d, watchName=%@, "
        @"productType=%@, watchOSVersion=%@, chipID=%@, "
        @"deviceMax=%@, sysMin=%@, sysMax=%@, inferred=%d>",
        self.source == WFCompatibilityReportSourceMagicCode ? @"magicCode" : @"registry",
        self.stateDescription,
        self.hasActiveWatch,
        self.watchName,
        self.productType  ?: @"(null)",
        self.watchOSVersion ?: @"(null)",
        self.chipID       ?: @"(null)",
        self.deviceMaxCompatibilityVersion  ?: @"(null)",
        self.systemMinCompatibilityVersion  ?: @"(null)",
        self.systemMaxCompatibilityVersion  ?: @"(null)",
        self.inferred];
}

@end

@interface NRDevice : NSObject
- (id)valueForProperty:(id)property;
- (BOOL)supportsCapability:(NSUUID *)capability;
@end

@interface NRPairedDeviceRegistry : NSObject
+ (instancetype)sharedInstance;
+ (id)activePairedDeviceSelectorBlock;
+ (id)activeDeviceSelectorBlock;
+ (id)pairedDevicesSelectorBlock;
- (NRDevice *)getActivePairedDevice;
- (NSArray<NRDevice *> *)pairedDevices;
- (NSArray<NRDevice *> *)getAllDevicesWithArchivedAltAccountDevicesMatching:(BOOL (^)(NRDevice *device))predicate;
- (void)_pingActiveGizmoWithPriority:(NSInteger)priority withMessageSize:(NSInteger)messageSize withBlock:(void (^)(__unsafe_unretained id _Nullable response))block;
@end

@interface NRPairingCompatibilityVersionInfo : NSObject
+ (instancetype)systemVersions;
- (NSInteger)maxPairingCompatibilityVersion;
- (NSInteger)minPairingCompatibilityVersionForChipID:(NSString *)chipID;
@end

@interface NSSManager : NSObject
- (instancetype)initWithQueue:(dispatch_queue_t)queue;
- (id)connection;
@end

extern "C" uint32_t NRWatchOSVersionForRemoteDevice(id device);
extern "C" NSString *NRDevicePropertyIsArchived;
extern "C" NSString *NRDevicePropertyIsPaired;
extern "C" NSString *NRDevicePropertyMaxPairingCompatibilityVersion;
extern "C" NSString *NRDevicePropertyProductType;
extern "C" NSString *NRDevicePropertyChipID;
extern "C" NSString *NRDevicePropertyName;
extern "C" NSString *NRDevicePropertyMarketingVersion;
extern "C" NSString *NRDevicePropertySystemVersion;

static NSNumber *EncodedWatchOSVersionForDevice(NRDevice *device);
static NSDictionary<NSString *, NSNumber *> *CapabilitySupportForDevice(NRDevice *device, NSArray<NSString *> *uuidStrings);

static NSString *StringFromObject(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    }
    return nil;
}

static id SafeValueForKey(id object, NSString *key) {
    if (!object || key.length == 0) {
        return nil;
    }
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *StringFromCString(const char *value) {
    return value ? [NSString stringWithUTF8String:value] : nil;
}

static NSString *PointerStringForObject(id object) {
    return [NSString stringWithFormat:@"%p", object];
}

static NSString *DebugDescriptionIfDistinct(id object) {
    if (!object) {
        return nil;
    }

    NSString *description = [object description];
    NSString *debugDescription = [object debugDescription];
    if (debugDescription.length == 0 || [debugDescription isEqualToString:description]) {
        return nil;
    }
    return debugDescription;
}

static NSString *DataHexPreview(NSData *data, NSUInteger maxLength);
static NSData *MiniUUIDSetData(id capabilityValue);
static NSArray<NSString *> *MiniUUIDStringsFromDescription(id capabilityValue);
static NSArray<NSString *> *UUIDStringsFromMiniUUIDSetData(NSData *data, NSUInteger expectedCount);

static NSDictionary<NSString *, id> *ObjectSummary(id object) {
    if (!object) {
        return @{ @"value": NSNull.null };
    }

    NSMutableDictionary<NSString *, id> *summary = [NSMutableDictionary dictionary];
    summary[@"className"] = NSStringFromClass([object class]) ?: @"NSObject";
    summary[@"pointer"] = PointerStringForObject(object);
    summary[@"description"] = [object description] ?: @"";
    NSString *debugDescription = DebugDescriptionIfDistinct(object);
    if (debugDescription.length > 0) {
        summary[@"debugDescription"] = debugDescription;
    }
    if ([summary[@"className"] isEqualToString:@"NRMiniUUIDSet"]) {
        NSData *data = MiniUUIDSetData(object);
        if (data) {
            summary[@"data"] = @{
                @"className": @"NSData",
                @"length": @(data.length),
                @"hexPreview": DataHexPreview(data, 256),
            };
            NSArray<NSString *> *capabilities = UUIDStringsFromMiniUUIDSetData(data, MiniUUIDStringsFromDescription(object).count);
            if (capabilities.count > 0) {
                summary[@"decodedCapabilities"] = capabilities;
            }
        }
    }
    return summary;
}

static NSString *DataHexPreview(NSData *data, NSUInteger maxLength) {
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    if (bytes == NULL || data.length == 0) {
        return @"";
    }

    NSUInteger previewLength = MIN(data.length, maxLength);
    NSMutableString *hex = [NSMutableString stringWithCapacity:(previewLength * 2) + 3];
    for (NSUInteger index = 0; index < previewLength; index += 1) {
        [hex appendFormat:@"%02X", bytes[index]];
    }
    if (data.length > previewLength) {
        [hex appendString:@"..."];
    }
    return hex;
}

static id JSONNormalizedObject(id value, NSUInteger depth, NSMutableSet<NSString *> *visited) {
    if (!value) {
        return NSNull.null;
    }

    if ([value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSNull class]]) {
        return value;
    }

    if ([value isKindOfClass:[NSDate class]] ||
        [value isKindOfClass:[NSURL class]] ||
        [value isKindOfClass:[NSUUID class]]) {
        return [value description] ?: NSNull.null;
    }

    if ([value isKindOfClass:[NSData class]]) {
        NSData *data = (NSData *)value;
        return @{
            @"className": @"NSData",
            @"length": @(data.length),
            @"hexPreview": DataHexPreview(data, 96),
        };
    }

    NSString *pointer = PointerStringForObject(value);
    if ([visited containsObject:pointer]) {
        NSMutableDictionary<NSString *, id> *cycle = [ObjectSummary(value) mutableCopy];
        if (!cycle) {
            cycle = [NSMutableDictionary dictionary];
        }
        cycle[@"cycle"] = @YES;
        return cycle;
    }
    [visited addObject:pointer];

    if (depth == 0) {
        return ObjectSummary(value);
    }

    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id item in (NSArray *)value) {
            [result addObject:JSONNormalizedObject(item, depth - 1, visited) ?: NSNull.null];
        }
        return result;
    }

    if ([value isKindOfClass:[NSSet class]]) {
        NSArray *sortedValues = [[(NSSet *)value allObjects] sortedArrayUsingComparator:^NSComparisonResult(id lhs, id rhs) {
            return [[lhs description] compare:[rhs description]];
        }];
        return JSONNormalizedObject(sortedValues, depth - 1, visited);
    }

    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
        for (id key in [(NSDictionary *)value allKeys]) {
            NSString *stringKey = StringFromObject(key) ?: [key description] ?: @"(null)";
            result[stringKey] = JSONNormalizedObject(((NSDictionary *)value)[key], depth - 1, visited) ?: NSNull.null;
        }
        return result;
    }

    return ObjectSummary(value);
}

static NSArray<NSDictionary<NSString *, NSString *> *> *KnownNRDevicePropertyDescriptors(void) {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *descriptors = [NSMutableArray array];
    void (^appendDescriptor)(NSString *, NSString *) = ^(NSString *symbol, NSString *key) {
        if (key.length == 0) {
            return;
        }
        [descriptors addObject:@{
            @"symbol": symbol,
            @"key": key,
        }];
    };

    appendDescriptor(@"NRDevicePropertyName", NRDevicePropertyName);
    appendDescriptor(@"NRDevicePropertyProductType", NRDevicePropertyProductType);
    appendDescriptor(@"NRDevicePropertyChipID", NRDevicePropertyChipID);
    appendDescriptor(@"NRDevicePropertyMarketingVersion", NRDevicePropertyMarketingVersion);
    appendDescriptor(@"NRDevicePropertySystemVersion", NRDevicePropertySystemVersion);
    appendDescriptor(@"NRDevicePropertyMaxPairingCompatibilityVersion", NRDevicePropertyMaxPairingCompatibilityVersion);
    appendDescriptor(@"NRDevicePropertyIsPaired", NRDevicePropertyIsPaired);
    appendDescriptor(@"NRDevicePropertyIsArchived", NRDevicePropertyIsArchived);

    return descriptors;
}

static NSDictionary<NSString *, id> *KnownValueForPropertySnapshot(NRDevice *device) {
    NSMutableArray<NSDictionary<NSString *, id> *> *entries = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *descriptor in KnownNRDevicePropertyDescriptors()) {
        NSString *key = descriptor[@"key"];
        id value = key.length > 0 ? [device valueForProperty:key] : nil;
        [entries addObject:@{
            @"symbol": descriptor[@"symbol"] ?: @"",
            @"key": key ?: @"",
            @"value": JSONNormalizedObject(value, 3, [NSMutableSet set]) ?: NSNull.null,
        }];
    }
    return @{
        @"entries": entries,
        @"count": @(entries.count),
    };
}

static NSDictionary<NSString *, id> *PropertySnapshotForObject(id object) {
    NSMutableDictionary<NSString *, id> *classes = [NSMutableDictionary dictionary];
    for (Class cls = [object class]; cls != Nil && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
        unsigned int propertyCount = 0;
        objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
        NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
        for (unsigned int index = 0; index < propertyCount; index += 1) {
            objc_property_t property = properties[index];
            NSString *name = StringFromCString(property_getName(property));
            if (name.length == 0) {
                continue;
            }

            NSString *attributes = StringFromCString(property_getAttributes(property));
            id value = SafeValueForKey(object, name);
            values[name] = @{
                @"attributes": attributes ?: @"",
                @"value": JSONNormalizedObject(value, 3, [NSMutableSet set]) ?: NSNull.null,
            };
        }
        free(properties);

        if (values.count > 0) {
            classes[NSStringFromClass(cls) ?: @"NSObject"] = values;
        }
    }
    return classes;
}

static NSDictionary<NSString *, id> *IvarSnapshotForObject(id object) {
    NSMutableDictionary<NSString *, id> *classes = [NSMutableDictionary dictionary];
    for (Class cls = [object class]; cls != Nil && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(cls, &ivarCount);
        NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
        for (unsigned int index = 0; index < ivarCount; index += 1) {
            Ivar ivar = ivars[index];
            NSString *name = StringFromCString(ivar_getName(ivar));
            if (name.length == 0) {
                continue;
            }

            NSString *typeEncoding = StringFromCString(ivar_getTypeEncoding(ivar));
            NSString *fallbackKey = [name hasPrefix:@"_"] ? [name substringFromIndex:1] : name;
            id value = nil;
            if ([typeEncoding hasPrefix:@"@"]) {
                value = object_getIvar(object, ivar);
            }
            if (!value) {
                value = SafeValueForKey(object, name);
            }
            if (!value && fallbackKey.length > 0 && ![fallbackKey isEqualToString:name]) {
                value = SafeValueForKey(object, fallbackKey);
            }

            values[name] = @{
                @"typeEncoding": typeEncoding ?: @"",
                @"value": JSONNormalizedObject(value, 3, [NSMutableSet set]) ?: NSNull.null,
            };
        }
        free(ivars);

        if (values.count > 0) {
            classes[NSStringFromClass(cls) ?: @"NSObject"] = values;
        }
    }
    return classes;
}

static NSDictionary<NSString *, id> *NRDevicerawJSON(NRDevice *device, BOOL hasActiveWatch) {
    NSMutableDictionary<NSString *, id> *snapshot = [NSMutableDictionary dictionary];
    snapshot[@"hasWatch"] = @(device != nil);
    snapshot[@"hasActiveWatch"] = @(hasActiveWatch);

    if (!device) {
        snapshot[@"nrDevice"] = NSNull.null;
        return snapshot;
    }

    NSMutableDictionary<NSString *, id> *deviceSnapshot = [NSMutableDictionary dictionary];
    deviceSnapshot[@"className"] = NSStringFromClass([device class]) ?: @"NRDevice";
    deviceSnapshot[@"pointer"] = PointerStringForObject(device);
    deviceSnapshot[@"description"] = [device description] ?: @"";
    NSString *debugDescription = DebugDescriptionIfDistinct(device);
    if (debugDescription.length > 0) {
        deviceSnapshot[@"debugDescription"] = debugDescription;
    }
    deviceSnapshot[@"knownValueForProperty"] = KnownValueForPropertySnapshot(device);
    deviceSnapshot[@"propertiesByClass"] = PropertySnapshotForObject(device);
    deviceSnapshot[@"ivarsByClass"] = IvarSnapshotForObject(device);
    snapshot[@"nrDevice"] = deviceSnapshot;
    return snapshot;
}

static NSArray<NSString *> *AdditionalNRDeviceDebugPropertyKeys(void) {
    return @[
        @"localizedModel",
        @"productType",
        @"systemName",
        @"systemVersion",
        @"systemBuildVersion",
        @"modelNumber",
        @"regulatoryModelNumber",
        @"serialNumber",
        @"chipID",
        @"isActive",
        @"isPaired",
        @"isCellularEnabled",
        @"isSetup",
        @"pairingCompatibilityVersion",
        @"minPairingCompatibilityVersion",
        @"maxPairingCompatibilityVersion",
        @"compatibilityState",
        @"statusCode",
        @"pairedDate",
        @"lastActiveDate",
        @"pairingID",
        @"pairingSessionIdentifier",
        @"regionCode",
        @"regionInfo",
        @"currentUserLocale",
        @"capabilities",
    ];
}

static NSDictionary<NSString *, id> *NRDeviceDebugPropertyValues(NRDevice *device) {
    NSMutableDictionary<NSString *, id> *properties = [NSMutableDictionary dictionary];
    if (!device) {
        return properties;
    }

    id oldProperties = SafeValueForKey(device, @"_oldPropertiesForChangeNotifications");
    if (!oldProperties) {
        oldProperties = SafeValueForKey(device, @"oldPropertiesForChangeNotifications");
    }

    NSDictionary<NSString *, id> *oldPropertyValues = nil;
    if ([oldProperties isKindOfClass:[NSDictionary class]]) {
        oldPropertyValues = oldProperties;
    } else {
        id values = SafeValueForKey(oldProperties, @"value");
        if ([values isKindOfClass:[NSDictionary class]]) {
            oldPropertyValues = values;
        }
    }

    if (oldPropertyValues.count > 0) {
        [properties addEntriesFromDictionary:oldPropertyValues];
    }

    for (NSDictionary<NSString *, NSString *> *descriptor in KnownNRDevicePropertyDescriptors()) {
        NSString *key = descriptor[@"key"];
        if (key.length == 0 || properties[key] != nil) {
            continue;
        }

        id value = [device valueForProperty:key];
        if (value) {
            properties[key] = value;
        }
    }

    for (NSString *key in AdditionalNRDeviceDebugPropertyKeys()) {
        if (key.length == 0 || properties[key] != nil) {
            continue;
        }

        id value = [device valueForProperty:key];
        if (value) {
            properties[key] = value;
        }
    }

    return properties;
}

static NSArray<NSString *> *MiniUUIDStringsFromDescription(id capabilityValue) {
    NSString *description = [capabilityValue description];
    if (description.length == 0) {
        return @[];
    }

    NSString *prefix = @"Mini Capabilities:";
    NSRange prefixRange = [description rangeOfString:prefix];
    NSString *body = prefixRange.location == NSNotFound ? description : [description substringFromIndex:NSMaxRange(prefixRange)];

    NSMutableOrderedSet<NSString *> *capabilities = [NSMutableOrderedSet orderedSet];
    for (NSString *component in [body componentsSeparatedByString:@","]) {
        NSString *trimmed = [[component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
        if ([trimmed hasSuffix:@"-"]) {
            trimmed = [trimmed substringToIndex:trimmed.length - 1];
        }
        if (trimmed.length > 0 && trimmed.length < 8) {
            NSString *padding = [@"" stringByPaddingToLength:8 - trimmed.length withString:@"0" startingAtIndex:0];
            trimmed = [padding stringByAppendingString:trimmed];
        }
        if (trimmed.length > 0) {
            [capabilities addObject:[trimmed uppercaseString]];
        }
    }
    return capabilities.array;
}

static NSData *MiniUUIDSetData(id capabilityValue) {
    id data = SafeValueForKey(capabilityValue, @"data");
    return [data isKindOfClass:[NSData class]] ? data : nil;
}

static NSArray<NSString *> *UUIDStringsFromMiniUUIDSetData(NSData *data, NSUInteger expectedCount) {
    if (!data || data.length == 0) {
        return @[];
    }

    if (expectedCount > 0 && data.length == expectedCount * 16) {
        NSMutableArray<NSString *> *uuids = [NSMutableArray arrayWithCapacity:expectedCount];
        const unsigned char *bytes = (const unsigned char *)data.bytes;
        for (NSUInteger offset = 0; offset < data.length; offset += 16) {
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDBytes:bytes + offset];
            if (uuid.UUIDString.length > 0) {
                [uuids addObject:uuid.UUIDString];
            }
        }
        return uuids;
    }

    if (data.length % 4 != 0) {
        return @[];
    }

    NSUInteger count = data.length / 4;
    NSMutableArray<NSString *> *miniUUIDs = [NSMutableArray arrayWithCapacity:count];
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    for (NSUInteger offset = 0; offset < data.length; offset += 4) {
        uint32_t value = ((uint32_t)bytes[offset]) |
            ((uint32_t)bytes[offset + 1] << 8) |
            ((uint32_t)bytes[offset + 2] << 16) |
            ((uint32_t)bytes[offset + 3] << 24);
        [miniUUIDs addObject:[NSString stringWithFormat:@"%08X", value]];
    }
    return miniUUIDs;
}

static NSArray<NSString *> *AllCapabilitiesFromPropertyValue(id capabilityValue) {
    NSArray<NSString *> *descriptionMiniUUIDs = MiniUUIDStringsFromDescription(capabilityValue);
    NSArray<NSString *> *dataUUIDs = UUIDStringsFromMiniUUIDSetData(MiniUUIDSetData(capabilityValue), descriptionMiniUUIDs.count);
    if (dataUUIDs.count > 0) {
        return dataUUIDs;
    }
    return descriptionMiniUUIDs;
}

static NSDictionary<NSString *, id> *NRDeviceReadableDebugInfo(NRDevice *device, BOOL hasActiveWatch) {
    NSMutableDictionary<NSString *, id> *info = [NSMutableDictionary dictionary];
    info[@"hasWatch"] = @(device != nil);
    info[@"hasActiveWatch"] = @(hasActiveWatch);

    if (!device) {
        info[@"properties"] = @{};
        info[@"capabilities"] = @[];
        return info;
    }

    NSDictionary<NSString *, id> *propertyValues = NRDeviceDebugPropertyValues(device);
    NSMutableDictionary<NSString *, id> *normalizedProperties = [NSMutableDictionary dictionary];
    for (NSString *key in propertyValues) {
        normalizedProperties[key] = JSONNormalizedObject(propertyValues[key], 3, [NSMutableSet set]) ?: NSNull.null;
    }

    info[@"properties"] = normalizedProperties;
    info[@"capabilities"] = AllCapabilitiesFromPropertyValue(propertyValues[@"capabilities"]);
    return info;
}

static NSDictionary<NSString *, id> *ActiveWatchDebugPayload(NRDevice *device, BOOL hasActiveWatch) {
    return @{
        @"displayInfo": NRDeviceReadableDebugInfo(device, hasActiveWatch),
        @"rawJSON": NRDevicerawJSON(device, hasActiveWatch),
    };
}

static BOOL DeviceMatchesRegistryFilter(NRDevice *device, id pairedKey, id archivedKey) {
    if (!device) {
        return NO;
    }
    NSNumber *isPaired = pairedKey ? NumberFromObject([device valueForProperty:pairedKey]) : nil;
    if (isPaired && !isPaired.boolValue) {
        return NO;
    }
    NSNumber *isArchived = archivedKey ? NumberFromObject([device valueForProperty:archivedKey]) : nil;
    if (isArchived.boolValue) {
        return NO;
    }
    return YES;
}

static NRDevice *FirstMatchingRegistryDevice(NSArray<NRDevice *> *devices, id pairedKey, id archivedKey) {
    for (NRDevice *device in devices ?: @[]) {
        if (DeviceMatchesRegistryFilter(device, pairedKey, archivedKey)) {
            return device;
        }
    }
    return nil;
}

static NRDevice *ActivePairedWatch(BOOL *isActiveOut) {
    NRPairedDeviceRegistry *registry = [NRPairedDeviceRegistry sharedInstance];
    Log(@"[WatchFixApp] Retrieved NanoRegistry paired device registry: %@", registry);
    if (!registry) {
        return nil;
    }

    NRDevice *device = [registry getActivePairedDevice];
    Log(@"[WatchFixApp] Retrieved active paired device from registry: %@", device);
    if (DeviceMatchesRegistryFilter(device, NRDevicePropertyIsPaired, NRDevicePropertyIsArchived)) {
        Log(@"[WatchFixApp] Active paired device matches filter criteria");
        if (isActiveOut) { *isActiveOut = YES; }
        return device;
    }

    BOOL (^selectorBlock)(id) = [NRPairedDeviceRegistry activePairedDeviceSelectorBlock];
    NSArray<NRDevice *> *devices = [registry getAllDevicesWithArchivedAltAccountDevicesMatching:^BOOL(NRDevice *device) {
        Log(@"[WatchFixApp] Evaluating device %@ with activePairedDeviceSelectorBlock", device);
        if (!DeviceMatchesRegistryFilter(device, NRDevicePropertyIsPaired, NRDevicePropertyIsArchived)) {
            return NO;
        }
        return selectorBlock ? selectorBlock(device) : YES;
    }];
    Log(@"[WatchFixApp] Retrieved devices matching activePairedDeviceSelectorBlock criteria: %@", devices);
    device = FirstMatchingRegistryDevice(devices, NRDevicePropertyIsPaired, NRDevicePropertyIsArchived);
    Log(@"[WatchFixApp] First device matching activePairedDeviceSelectorBlock criteria: %@", device);
    if (device) {
        if (isActiveOut) { *isActiveOut = YES; }
        return device;
    }

    BOOL (^activeSelectorBlock)(id) = [NRPairedDeviceRegistry respondsToSelector:@selector(activeDeviceSelectorBlock)] ?
        [NRPairedDeviceRegistry activeDeviceSelectorBlock] : nil;
    if (activeSelectorBlock) {
        devices = [registry getAllDevicesWithArchivedAltAccountDevicesMatching:^BOOL(NRDevice *device) {
            Log(@"[WatchFixApp] Evaluating device %@ with activeDeviceSelectorBlock", device);
            if (!DeviceMatchesRegistryFilter(device, NRDevicePropertyIsPaired, NRDevicePropertyIsArchived)) {
                return NO;
            }
            return activeSelectorBlock(device);
        }];
        Log(@"[WatchFixApp] Retrieved devices matching activeDeviceSelectorBlock criteria: %@", devices);
        device = FirstMatchingRegistryDevice(devices, NRDevicePropertyIsPaired, NRDevicePropertyIsArchived);
        Log(@"[WatchFixApp] First device matching activeDeviceSelectorBlock criteria: %@", device);
        if (device) {
            if (isActiveOut) { *isActiveOut = YES; }
            return device;
        }
    }

    BOOL (^pairedSelectorBlock)(id) = [NRPairedDeviceRegistry respondsToSelector:@selector(pairedDevicesSelectorBlock)] ?
        [NRPairedDeviceRegistry pairedDevicesSelectorBlock] : nil;
    if (pairedSelectorBlock) {
        devices = [registry getAllDevicesWithArchivedAltAccountDevicesMatching:^BOOL(NRDevice *device) {
            Log(@"[WatchFixApp] Evaluating device %@ with pairedDevicesSelectorBlock", device);
            if (!DeviceMatchesRegistryFilter(device, NRDevicePropertyIsPaired, NRDevicePropertyIsArchived)) {
                return NO;
            }
            return pairedSelectorBlock(device);
        }];
        Log(@"[WatchFixApp] Retrieved devices matching pairedDevicesSelectorBlock criteria: %@", devices);
        device = FirstMatchingRegistryDevice(devices, NRDevicePropertyIsPaired, NRDevicePropertyIsArchived);
        Log(@"[WatchFixApp] First device matching pairedDevicesSelectorBlock criteria: %@", device);
        if (device) {
            if (isActiveOut) { *isActiveOut = NO; }
            return device;
        }
    }

    if ([registry respondsToSelector:@selector(pairedDevices)]) {
        device = FirstMatchingRegistryDevice([registry pairedDevices], NRDevicePropertyIsPaired, NRDevicePropertyIsArchived);
        Log(@"[WatchFixApp] First device in pairedDevices matching filter criteria: %@", device);
        if (device) {
            if (isActiveOut) { *isActiveOut = NO; }
            return device;
        }
    }

    return nil;
}

static NRDevice *ActivePairedWatchWithRetries(BOOL *isActiveOut) {
    for (NSUInteger attempt = 0; attempt < kRegistryRetryCount; attempt += 1) {
        BOOL hasActiveWatch = NO;
        NRDevice *device = ActivePairedWatch(&hasActiveWatch);
        if (device) {
            if (isActiveOut) { *isActiveOut = hasActiveWatch; }
            return device;
        }
        if (attempt + 1 < kRegistryRetryCount) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:kRegistryRetryInterval]];
        }
    }
    return nil;
}

static NSNumber *ScanIntegerValue(NSDictionary<NSString *, id> *scanResult, NSString *key) {
    return NumberFromObject(scanResult[key]);
}

static NSString *ScanStringValue(NSDictionary<NSString *, id> *scanResult, NSString *key) {
    return StringFromObject(scanResult[key]);
}

static NSString *FormattedWatchOSVersion(uint32_t encodedVersion) {
    if (encodedVersion == UINT32_MAX || encodedVersion == 0) {
        return nil;
    }
    NSInteger major = (encodedVersion >> 16) & 0xFF;
    NSInteger minor = (encodedVersion >> 8) & 0xFF;
    NSInteger patch = encodedVersion & 0xFF;
    if (patch > 0) {
        return [NSString stringWithFormat:@"%ld.%ld.%ld", (long)major, (long)minor, (long)patch];
    }
    return [NSString stringWithFormat:@"%ld.%ld", (long)major, (long)minor];
}

static NSNumber *EncodedVersionNumberFromString(NSString *versionString) {
    if (versionString.length == 0) {
        return nil;
    }

    NSArray<NSString *> *components = [versionString componentsSeparatedByString:@"."];
    NSInteger values[3] = {0, 0, 0};
    NSUInteger count = 0;

    for (NSString *component in components) {
        if (count >= 3) {
            break;
        }

        NSString *trimmed = [component stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) {
            break;
        }

        NSScanner *scanner = [NSScanner scannerWithString:trimmed];
        NSInteger parsedValue = 0;
        if (![scanner scanInteger:&parsedValue] || !scanner.isAtEnd) {
            break;
        }

        values[count] = MAX(0, MIN(255, parsedValue));
        count += 1;
    }

    if (count == 0) {
        return nil;
    }

    uint32_t encodedValue = ((uint32_t)values[0] << 16) | ((uint32_t)values[1] << 8) | (uint32_t)values[2];
    return @(encodedValue);
}

static NSNumber *EncodedWatchOSVersionForDevice(NRDevice *device) {
    if (!device) {
        return nil;
    }

    uint32_t encodedVersion = NRWatchOSVersionForRemoteDevice(device);
    if (encodedVersion != UINT32_MAX && encodedVersion != 0) {
        return @(encodedVersion);
    }

    NSString *watchOSVersion = StringFromObject([device valueForProperty:NRDevicePropertyMarketingVersion]);
    if (watchOSVersion.length == 0) {
        watchOSVersion = StringFromObject([device valueForProperty:NRDevicePropertySystemVersion]);
    }
    return EncodedVersionNumberFromString(watchOSVersion);
}

static NSDictionary<NSString *, NSNumber *> *CapabilitySupportForDevice(NRDevice *device, NSArray<NSString *> *uuidStrings) {
    NSMutableOrderedSet<NSString *> *uniqueUUIDs = [NSMutableOrderedSet orderedSet];
    for (id value in uuidStrings ?: @[]) {
        NSString *uuidString = [StringFromObject(value) uppercaseString];
        if (uuidString.length > 0) {
            [uniqueUUIDs addObject:uuidString];
        }
    }

    NSMutableDictionary<NSString *, NSNumber *> *results = [NSMutableDictionary dictionary];
    BOOL canCheckCapabilities = device && [device respondsToSelector:@selector(supportsCapability:)];
    for (NSString *uuidString in uniqueUUIDs) {
        BOOL supported = NO;
        if (canCheckCapabilities) {
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidString];
            supported = uuid ? [device supportsCapability:uuid] : NO;
        }
        results[uuidString] = @(supported);
    }

    return results;
}

static NSString *WatchDisplayName(NRDevice *device) {
    NSString *name = StringFromObject([device valueForProperty:NRDevicePropertyName]);
    if (name.length > 0) {
        return name;
    }
    NSString *productType = StringFromObject([device valueForProperty:NRDevicePropertyProductType]);
    return productType.length > 0 ? productType : @"Apple Watch";
}

static WFCompatibilityReport *CompatibilityReportForDevice(NRDevice *device,
                                                                    NRPairingCompatibilityVersionInfo *systemVersions) {
    Log(@"[WatchFixApp] Generating compatibility report for device: %@", device);
    NSString *watchName      = WatchDisplayName(device);
    NSNumber *deviceMaxValue = NumberFromObject([device valueForProperty:NRDevicePropertyMaxPairingCompatibilityVersion]);
    NSString *chipID         = StringFromObject([device valueForProperty:NRDevicePropertyChipID]);
    NSString *productType    = StringFromObject([device valueForProperty:NRDevicePropertyProductType]);
    NSString *watchOSVersion  = StringFromObject([device valueForProperty:NRDevicePropertyMarketingVersion]);
    if (!watchOSVersion){
        watchOSVersion  = StringFromObject([device valueForProperty:NRDevicePropertySystemVersion]);
    }
    if (!watchOSVersion) {
        uint32_t encodedVersion = NRWatchOSVersionForRemoteDevice(device);
        watchOSVersion = FormattedWatchOSVersion(encodedVersion);
    }

    NSInteger systemMax      = [systemVersions maxPairingCompatibilityVersion];
    NSNumber *systemMaxValue = @(systemMax);
    NSNumber *systemMinValue = nil;
    WFCompatibilityReportState state = WFCompatibilityReportStateIndeterminate;

    if (deviceMaxValue && chipID.length > 0) {
        NSInteger systemMin = [systemVersions minPairingCompatibilityVersionForChipID:chipID];
        systemMinValue = @(systemMin);
        BOOL requiresPairingSupport = [deviceMaxValue integerValue] > systemMax || [deviceMaxValue integerValue] < systemMin;
        state = requiresPairingSupport ? WFCompatibilityReportStateNeedsPairingSupport : WFCompatibilityReportStateCompatible;
    }

    WFCompatibilityReport *report = [[WFCompatibilityReport alloc] init];
    report.source           = WFCompatibilityReportSourceRegistry;
    report.state            = state;
    report.hasActiveWatch   = YES;
    report.watchName        = watchName.length > 0 ? watchName : @"Apple Watch";
    report.inferred         = NO;
    report.productType      = productType.length > 0  ? productType  : nil;
    report.watchOSVersion   = watchOSVersion.length > 0 ? watchOSVersion : nil;
    report.chipID           = chipID.length > 0       ? chipID       : nil;
    report.deviceMaxCompatibilityVersion = deviceMaxValue;
    report.systemMinCompatibilityVersion = systemMinValue;
    report.systemMaxCompatibilityVersion = systemMaxValue;
    Log(@"[WatchFixApp] Generated compatibility report: %@", report);
    return report;
}

static WFCompatibilityReport *CompatibilityReportForScan(NSDictionary<NSString *, id> *scanResult,
                                                                  NRPairingCompatibilityVersionInfo *systemVersions) {
    NSString *watchName     = ScanStringValue(scanResult, @"watchName");
    NSString *productType   = ScanStringValue(scanResult, @"productType");
    NSString *watchOSVersion = ScanStringValue(scanResult, @"watchOSVersion");
    NSString *chipID        = ScanStringValue(scanResult, @"chipID");
    NSNumber *deviceMaxValue = ScanIntegerValue(scanResult, @"pairingCompatibilityVersion");
    NSString *rawDescription = ScanStringValue(scanResult, @"rawDescription");

    if (watchName.length == 0) {
        watchName = productType.length > 0 ? productType : @"Apple Watch";
    }

    NSInteger systemMax      = [systemVersions maxPairingCompatibilityVersion];
    NSNumber *systemMaxValue = @(systemMax);
    NSNumber *systemMinValue = nil;
    BOOL inferred = NO;
    WFCompatibilityReportState state = WFCompatibilityReportStateIndeterminate;

    if (deviceMaxValue && chipID.length > 0) {
        NSInteger systemMin = [systemVersions minPairingCompatibilityVersionForChipID:chipID];
        systemMinValue = @(systemMin);
        BOOL requiresPairingSupport = [deviceMaxValue integerValue] > systemMax || [deviceMaxValue integerValue] < systemMin;
        state = requiresPairingSupport ? WFCompatibilityReportStateNeedsPairingSupport : WFCompatibilityReportStateCompatible;
    } else {
        inferred = YES;
    }

    WFCompatibilityReport *report = [[WFCompatibilityReport alloc] init];
    report.source           = WFCompatibilityReportSourceMagicCode;
    report.state            = state;
    report.hasActiveWatch   = NO;
    report.watchName        = watchName;
    report.inferred         = inferred;
    report.productType      = productType.length > 0     ? productType     : nil;
    report.watchOSVersion   = watchOSVersion.length > 0  ? watchOSVersion  : nil;
    report.chipID           = chipID.length > 0          ? chipID          : nil;
    report.deviceMaxCompatibilityVersion = deviceMaxValue;
    report.systemMinCompatibilityVersion = systemMinValue;
    report.systemMaxCompatibilityVersion = systemMaxValue;
    report.rawDescription   = rawDescription.length > 0  ? rawDescription  : nil;
    return report;
}


@protocol SUBManagerDelegate <NSObject>
@optional
- (void)manager:(id)manager scanRequestDidLocateUpdate:(id)update error:(NSError *)error;
@end

typedef void (^SUManagerStateHandler)(NSInteger managerState, id _Nullable descriptor, NSError * _Nullable error);

@interface SUBManager : NSObject
- (instancetype)initWithDelegate:(id<SUBManagerDelegate>)delegate;
- (void)managerState:(SUManagerStateHandler)completion;
- (void)scanForUpdates;
@end

@interface SUBridgeManager : NSObject <SUBManagerDelegate>
+ (instancetype)sharedManager;
- (void)checkForSoftwareUpdate:(void (^)(NSDictionary<NSString *, id> * _Nullable result, NSError * _Nullable error))completion;
@end

@implementation SUBridgeManager {
    void (^_completion)(NSDictionary<NSString *, id> * _Nullable, NSError * _Nullable);
    SUBManager *_manager;
    BOOL _scanning;
    BOOL _scanTriggered;
    NSUInteger _scanToken;
}

+ (instancetype)sharedManager {
    static SUBridgeManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SUBridgeManager alloc] init];
    });
    return instance;
}

- (SUBManager *)manager {
    if (!_manager) {
        _manager = [[SUBManager alloc] initWithDelegate:self];
    }
    return _manager;
}

- (NSMutableDictionary<NSString *, id> *)scanResultDictionaryForUpdate:(id)update {
    NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
    result[@"hasUpdate"] = @(update != nil);
    result[@"source"] = @"softwareupdate";

    if (update) {
        NSString *updateName = StringFromObject(SafeValueForKey(update, @"humanReadableUpdateName"));
        NSString *updateVersion = StringFromObject(SafeValueForKey(update, @"productVersion"));
        NSString *buildVersion = StringFromObject(SafeValueForKey(update, @"productBuildVersion"));
        NSString *marketingVersion = StringFromObject(SafeValueForKey(update, @"marketingVersion"));
        NSString *productSystemName = StringFromObject(SafeValueForKey(update, @"productSystemName"));
        NSString *publisher = StringFromObject(SafeValueForKey(update, @"publisher"));
        NSString *osName = StringFromObject(SafeValueForKey(update, @"osName"));
        NSString *documentationID = StringFromObject(SafeValueForKey(update, @"documentationID"));

        if (updateName.length > 0) {
            result[@"updateName"] = updateName;
        }
        if (updateVersion.length > 0) {
            result[@"updateVersion"] = updateVersion;
        }
        if (buildVersion.length > 0) {
            result[@"buildVersion"] = buildVersion;
        }
        if (marketingVersion.length > 0) {
            result[@"marketingVersion"] = marketingVersion;
        }
        if (productSystemName.length > 0) {
            result[@"productSystemName"] = productSystemName;
        }
        if (publisher.length > 0) {
            result[@"publisher"] = publisher;
        }
        if (osName.length > 0) {
            result[@"osName"] = osName;
        }
        if (documentationID.length > 0) {
            result[@"documentationID"] = documentationID;
        }

        // 数字型字段：大小信息
        id downloadSize = SafeValueForKey(update, @"downloadSize");
        id preparationSize = SafeValueForKey(update, @"preparationSize");
        id installationSize = SafeValueForKey(update, @"installationSize");
        id totalRequiredFreeSpace = SafeValueForKey(update, @"totalRequiredFreeSpace");
        id manifestLength = SafeValueForKey(update, @"manifestLength");

        if (downloadSize) { result[@"downloadSize"] = downloadSize; }
        if (preparationSize) { result[@"preparationSize"] = preparationSize; }
        if (installationSize) { result[@"installationSize"] = installationSize; }
        if (totalRequiredFreeSpace) { result[@"totalRequiredFreeSpace"] = totalRequiredFreeSpace; }
        if (manifestLength) { result[@"manifestLength"] = manifestLength; }

        // 布尔型字段
        id terms = SafeValueForKey(update, @"terms");
        id installTonightScheduled = SafeValueForKey(update, @"installTonightScheduled");
        id displayTermsRequested = SafeValueForKey(update, @"displayTermsRequested");

        if (terms) { result[@"terms"] = terms; }
        if (installTonightScheduled) { result[@"installTonightScheduled"] = installTonightScheduled; }
        if (displayTermsRequested) { result[@"displayTermsRequested"] = displayTermsRequested; }
    }

    return result;
}

- (void)checkForSoftwareUpdate:(void (^)(NSDictionary<NSString *, id> * _Nullable result, NSError * _Nullable error))completion {
    Log(@"[WatchFixApp] Starting software update scan");

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // NSError *pingError = nil;
        // if (![WatchAPI syncWatchIsReachable:&pingError]) {
        //     dispatch_async(dispatch_get_main_queue(), ^{
        //         if (completion) {
        //             completion(nil, pingError);
        //         }
        //     });
        //     return;
        // }

        dispatch_async(dispatch_get_main_queue(), ^{
            SUBManager *mgr = nil;
            NSUInteger token = 0;

            @synchronized (self) {
                _completion = [completion copy];
                _scanning = YES;
                _scanTriggered = NO;
                _scanToken += 1;
                token = _scanToken;
                mgr = self.manager;
            }

            Log(@"[WatchFixApp] Created SUBManager for software update scan: %@", mgr);

            if (!mgr) {
                [self finishWithResult:nil error:BridgeError(41, @"Unable to create software update manager")];
                return;
            }

            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSoftwareUpdateScanTimeout * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) {
                    return;
                }

                @synchronized (self) {
                    if (!_scanning || token != _scanToken) {
                        return;
                    }
                }

                [self handleTimeout];
            });

            Log(@"[WatchFixApp] Registering managerState callback before scan: %@", mgr);
            [mgr managerState:^(NSInteger managerState, id descriptor, NSError *error) {
                Log(@"[WatchFixApp] managerState callback invoked: state=%ld descriptor=%@ error=%@",
                      (long)managerState, descriptor, error);
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) {
                    return;
                }

                [self handleManagerState:managerState descriptor:descriptor error:error manager:mgr];
            }];
        });
    });
}

- (void)handleManagerState:(NSInteger)managerState descriptor:(id)descriptor error:(NSError *)error manager:(SUBManager *)manager {
    BOOL shouldStartScan = NO;

    Log(@"[WatchFixApp] SUBManager managerState callback: state=%ld descriptor=%@ error=%@",
          (long)managerState, descriptor, error);

    @synchronized (self) {
        if (!_scanning || manager != _manager) {
            Log(@"[WatchFixApp] Ignoring stale managerState callback: manager=%@ current=%@", manager, _manager);
            return;
        }

        if (!error && !_scanTriggered) {
            _scanTriggered = YES;
            shouldStartScan = YES;
        }
    }

    if (error) {
        [self finishWithResult:nil error:error];
        return;
    }

    if (!shouldStartScan) {
        return;
    }

    Log(@"[WatchFixApp] Starting software update scan after managerState registration: %@", manager);
    [manager scanForUpdates];
}

- (void)finishWithResult:(NSDictionary<NSString *, id> * _Nullable)result error:(NSError * _Nullable)error {
    Log(@"[WatchFixApp] Finishing software update scan with result: %@, error: %@", result, error);

    void (^completion)(NSDictionary<NSString *, id> * _Nullable, NSError * _Nullable) = nil;

    @synchronized (self) {
        if (!_scanning) {
            return;
        }

        _scanning = NO;
        _scanTriggered = NO;
        completion = _completion;
        _completion = nil;
        _manager = nil;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) {
            completion(result, error);
        }
    });
}

- (void)handleTimeout {
    Log(@"[WatchFixApp] Software update scan timed out");
    [self finishWithResult:nil error:BridgeError(42, @"Software update scan timed out")];
}

- (void)manager:(id)manager scanRequestDidLocateUpdate:(id)update error:(NSError *)error {
    @synchronized (self) {
        if (!_scanning || manager != _manager) {
            Log(@"[WatchFixApp] Ignoring stale SUBManager callback: manager=%@ current=%@", manager, _manager);
            return;
        }
    }

    Log(@"[WatchFixApp] SUBManager scan callback: update=%@, error=%@", update, error);

    if (error) {
        if ([error.domain isEqualToString:@"SUBError"] && error.code == 34) {
            NSMutableDictionary<NSString *, id> *result = [self scanResultDictionaryForUpdate:update];
            if (update) {
                result[@"needsPhoneUpdate"] = @YES;
                [self finishWithResult:result error:nil];
                return;
            }
        }

        [self finishWithResult:nil error:error];
        return;
    }

    [self finishWithResult:[self scanResultDictionaryForUpdate:update] error:nil];
}

@end

@implementation WatchAPI

+ (BOOL)syncWatchIsReachable:(NSError * _Nullable __autoreleasing *)error {
    NSAssert(![NSThread isMainThread], @"syncWatchIsReachable must not be called on the main thread");
    if ([NSThread isMainThread]) {
        if (error) { *error = BridgeError(60, @"syncWatchIsReachable must not be called on the main thread"); }
        return NO;
    }
    Log(@"[WatchFixApp] Checking if active paired watch is reachable...");
    NRPairedDeviceRegistry *registry = [NRPairedDeviceRegistry sharedInstance];
    NRDevice *device = [registry getActivePairedDevice];
    if (!device) {
        if (error) { *error = BridgeError(61, @"No active paired watch"); }
        return NO;
    }
    Log(@"[WatchFixApp] Found active paired watch: %@. Pinging to check reachability...", device);
    __block BOOL reachable = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [registry _pingActiveGizmoWithPriority:300 withMessageSize:8 withBlock:^(__unsafe_unretained id _Nullable response) {
        if (response) {
            reachable = YES;
        }
        dispatch_semaphore_signal(semaphore);
    }];
    Log(@"[WatchFixApp] Ping sent. Waiting for response with timeout...");
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC));
    dispatch_semaphore_wait(semaphore, timeout);
    Log(@"[WatchFixApp] Ping response received: reachable=%d", reachable);
    if (!reachable) {
        if (error) { *error = BridgeError(62, @"Watch is not reachable"); }
        return NO;
    }
    return YES;
}

+ (nullable WFCompatibilityReport *)currentCompatibilityReport:(NSError * _Nullable __autoreleasing *)error {
    // NSError *pingError = nil;
    // if (![self syncWatchIsReachable:&pingError]) {
    //     if (error) { *error = pingError; }
    //     return nil;
    // }

    NRPairingCompatibilityVersionInfo *systemVersions = [NRPairingCompatibilityVersionInfo systemVersions];
    if (!systemVersions) {
        if (error) { *error = BridgeError(30, @"Unable to load NanoRegistry compatibility information"); }
        return nil;
    }

    BOOL hasActiveWatch = NO;
    NRDevice *device = ActivePairedWatchWithRetries(&hasActiveWatch);
    if (!device) {
        WFCompatibilityReport *unavailable = [[WFCompatibilityReport alloc] init];
        unavailable.source         = WFCompatibilityReportSourceRegistry;
        unavailable.state          = WFCompatibilityReportStateUnavailable;
        unavailable.hasActiveWatch = NO;
        unavailable.watchName      = @"Apple Watch";
        unavailable.inferred       = NO;
        return unavailable;
    }

    WFCompatibilityReport *report = CompatibilityReportForDevice(device, systemVersions);
    report.hasActiveWatch = hasActiveWatch;
    if (!hasActiveWatch) { report.inferred = YES; }
    return report;
}

+ (nullable WFCompatibilityReport *)compatibilityReportForScannedResult:(NSDictionary<NSString *, id> *)scanResult
                                                                   error:(NSError * _Nullable __autoreleasing *)error {
    if (![scanResult isKindOfClass:[NSDictionary class]]) {
        if (error) { *error = BridgeError(31, @"Invalid scan result"); }
        return nil;
    }
    NRPairingCompatibilityVersionInfo *systemVersions = [NRPairingCompatibilityVersionInfo systemVersions];
    if (!systemVersions) {
        if (error) { *error = BridgeError(32, @"Unable to load NanoRegistry compatibility information"); }
        return nil;
    }
    return CompatibilityReportForScan(scanResult, systemVersions);
}

+ (void)scanLatestSoftwareUpdateWithCompletion:(void (^)(NSDictionary<NSString *, id> * _Nullable, NSError * _Nullable))completion {
    [[SUBridgeManager sharedManager] checkForSoftwareUpdate:completion];
}

+ (NSDictionary<NSString *, id> *)activeWatchValidationSnapshotForCapabilityUUIDStrings:(NSArray<NSString *> *)uuidStrings {
    BOOL hasActiveWatch = NO;
    NRDevice *device = ActivePairedWatchWithRetries(&hasActiveWatch);
    NSMutableDictionary<NSString *, id> *snapshot = [NSMutableDictionary dictionary];
    snapshot[@"hasWatch"] = @(device != nil);
    snapshot[@"hasActiveWatch"] = @(hasActiveWatch);

    NSNumber *encodedWatchOSVersion = EncodedWatchOSVersionForDevice(device);
    if (encodedWatchOSVersion) {
        snapshot[@"encodedWatchOSVersion"] = encodedWatchOSVersion;
    }

    snapshot[@"capabilities"] = CapabilitySupportForDevice(device, uuidStrings);
    return snapshot;
}

+ (NSDictionary<NSString *, id> *)activeWatchDebugPayload {
    BOOL hasActiveWatch = NO;
    NRDevice *device = ActivePairedWatchWithRetries(&hasActiveWatch);
    return ActiveWatchDebugPayload(device, hasActiveWatch);
}

+ (NSDictionary<NSString *, id> *)activeWatchDebugSnapshotForCapabilityUUIDStrings:(NSArray<NSString *> *)uuidStrings {
    (void)uuidStrings;
    BOOL hasActiveWatch = NO;
    NRDevice *device = ActivePairedWatchWithRetries(&hasActiveWatch);
    return NRDevicerawJSON(device, hasActiveWatch);
}

+ (BOOL)rebootActiveWatch:(NSError * _Nullable __autoreleasing *)error {
    dispatch_queue_t queue = dispatch_queue_create("cn.fkj233.watchfix.reboot", DISPATCH_QUEUE_SERIAL);
    id manager = [[NSSManager alloc] initWithQueue:queue];
    Log(@"[WatchFixApp] Created NSSManager for rebooting watch: %@", manager);
    id connection = [manager connection];
    Log(@"[WatchFixApp] Retrieved connection from NSSManager: %@", connection);
    Log(@"[WatchFixApp] Connection class: %@", [connection class]);
    if ([connection respondsToSelector:@selector(rebootDevice)]) {
        Log(@"[WatchFixApp] Sending reboot command to watch via connection");
        [connection performSelector:@selector(rebootDevice)];
        return YES;
    }
    if ([manager respondsToSelector:@selector(rebootDevice)]) {
        Log(@"[WatchFixApp] Sending reboot command to watch via manager");
        [manager performSelector:@selector(rebootDevice)];
        return YES;
    }
    Log(@"[WatchFixApp] Unable to send reboot command: no known method found on connection or manager");
    if (error) { *error = BridgeError(51, @"Unable to send reboot request to the active watch"); }
    return NO;
}

@end
