#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <substrate.h>

#include <string>

#include "utils.h"

@interface NRDevice : NSObject
- (id)valueForProperty:(id)property;
- (BOOL)supportsCapability:(NSUUID *)capability;
@end

@interface NRPairedDeviceRegistry : NSObject
+ (instancetype)sharedInstance;
- (NSArray<NRDevice *> *)getAllDevicesWithArchivedAltAccountDevicesMatching:(BOOL (^)(NRDevice *device))predicate;
@end

extern "C" NSString *NRDevicePropertyProductType;
extern "C" uint32_t NRWatchOSVersionForRemoteDevice(NRDevice *device);

static NSString *const kRemoteCardProvisioningSettingsKey = @"RemoteCardProvisioningSettings";
static NSString *const kSupportedSKUsKey = @"SupportedSKUs";
static NSString *const kPost2018SKU = @"SKU_POST2018_ALL";
static NSString *const kCapabilityUUIDString = @"4AA3FF3B-3224-42E6-995E-481F49AE9260";

static dispatch_queue_t mobileDataLookupQueue = NULL;
static dispatch_queue_t mobileDataCacheQueue = NULL;
static NSMutableDictionary<NSData *, NSNumber *> *mobileDataRepairCache = nil;
static NSUUID *mobileDataCapabilityUUID = nil;

typedef BOOL (^WatchFixValidateDeviceBlock)(void *deviceContext);

static NSData *CopyCacheKeyFromValidationContext(const void *validateContext) {
    if (!validateContext) {
        return nil;
    }

    const auto *lookupKey = reinterpret_cast<const std::string *>(validateContext);
    if (!lookupKey) {
        return nil;
    }

    return [NSData dataWithBytes:lookupKey->data() length:lookupKey->size()];
}

static BOOL CopyValidationContextProductTypeAndWatchOS(const void *validateContext,
                                                       std::string *productTypeOut,
                                                       uint32_t *encodedWatchOSOut) {
    if (!validateContext || !productTypeOut || !encodedWatchOSOut) {
        return NO;
    }

    const uint8_t *contextBytes = reinterpret_cast<const uint8_t *>(validateContext);
    const BOOL usesLegacyOffsets = !isOSVersionAtLeast(14, 5, 0);
    const size_t productTypeOffset = usesLegacyOffsets ? 0x38 : 0x20;
    const size_t encodedWatchOSOffset = usesLegacyOffsets ? 0x50 : 0x38;

    *productTypeOut = *reinterpret_cast<const std::string *>(contextBytes + productTypeOffset);
    *encodedWatchOSOut = *reinterpret_cast<const uint32_t *>(contextBytes + encodedWatchOSOffset);
    return YES;
}

static dispatch_queue_t WatchFixMobileDataLookupQueue(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mobileDataLookupQueue = dispatch_queue_create("WatchFix.MobileDataSupport.lookup", DISPATCH_QUEUE_CONCURRENT);
    });
    return mobileDataLookupQueue;
}

static dispatch_queue_t WatchFixMobileDataCacheQueue(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mobileDataCacheQueue = dispatch_queue_create("WatchFix.MobileDataSupport.cache", DISPATCH_QUEUE_SERIAL);
        mobileDataRepairCache = [[NSMutableDictionary alloc] init];
    });
    return mobileDataCacheQueue;
}

static NSUUID *WatchFixMobileDataCapabilityUUID(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mobileDataCapabilityUUID = [[NSUUID alloc] initWithUUIDString:kCapabilityUUIDString];
    });
    return mobileDataCapabilityUUID;
}

static NSNumber *CopyCachedRepairState(NSData *cacheKey) {
    if (!cacheKey) {
        return nil;
    }

    __block NSNumber *cachedState = nil;
    dispatch_sync(WatchFixMobileDataCacheQueue(), ^{
        cachedState = mobileDataRepairCache[cacheKey];
    });
    return cachedState;
}

static void StoreCachedRepairState(NSData *cacheKey, BOOL supported) {
    if (!cacheKey) {
        return;
    }

    dispatch_sync(WatchFixMobileDataCacheQueue(), ^{
        mobileDataRepairCache[cacheKey] = @(supported);
    });
}

static BOOL WatchFixProductTypeMatchesRequestedProductType(NRDevice *device,
                                                           const char *requestedProductTypeCString,
                                                           uint32_t minimumWatchOS) {
    if (!device || !requestedProductTypeCString) {
        return NO;
    }

    NSString *productType = [device valueForProperty:NRDevicePropertyProductType];
    if (productType.length == 0) {
        return NO;
    }

    const char *deviceProductTypeCString = productType.UTF8String;
    if (is_empty(deviceProductTypeCString)) {
        return NO;
    }

    if (strncmp(deviceProductTypeCString, requestedProductTypeCString, productType.length) != 0) {
        return NO;
    }

    return NRWatchOSVersionForRemoteDevice(device) >= minimumWatchOS;
}

static NRDevice *CopyFirstMatchingPairedWatch(const char *requestedProductTypeCString,
                                              uint32_t minimumWatchOS) {
    if (!requestedProductTypeCString) {
        return nil;
    }

    NSArray<NRDevice *> *matches = [[NRPairedDeviceRegistry sharedInstance]
        getAllDevicesWithArchivedAltAccountDevicesMatching:^BOOL(NRDevice *device) {
            return WatchFixProductTypeMatchesRequestedProductType(device,
                                                                  requestedProductTypeCString,
                                                                  minimumWatchOS);
        }];
    return matches.firstObject;
}

static BOOL PairedWatchMeetsMobileDataRepairRequirements(const void *validateContext,
                                                         uint32_t minimumWatchOS) {
    Log("validating paired watch for minimum watchOS 0x%X", minimumWatchOS);
    if (!validateContext) {
        Log("no validation context provided");
        return NO;
    }

    NSData *cacheKey = CopyCacheKeyFromValidationContext(validateContext);
    NSNumber *cachedState = CopyCachedRepairState(cacheKey);
    if (cachedState) {
        Log("returning cached repair state: %s", cachedState.boolValue ? "SUPPORTED" : "NOT SUPPORTED");
        return cachedState.boolValue;
    }

    std::string requestedProductType;
    uint32_t encodedWatchOS = 0;
    if (!CopyValidationContextProductTypeAndWatchOS(validateContext,
                                                    &requestedProductType,
                                                    &encodedWatchOS)) {
        Log("failed to extract product type and watchOS version from validation context");
        return NO;
    }

    if ((encodedWatchOS >> 24) != 0) {
        Log("encoded watchOS version 0x%X has non-zero major version, which is unexpected and cannot be handled",
               encodedWatchOS);
        StoreCachedRepairState(cacheKey, NO);
        return NO;
    }

    if (requestedProductType.rfind("Watch", 0) != 0) {
        Log("requested product type '%s' does not start with 'Watch', cannot validate",
               requestedProductType.c_str());
        StoreCachedRepairState(cacheKey, NO);
        return NO;
    }

    if (encodedWatchOS < minimumWatchOS) {
        Log("encoded watchOS version 0x%X does not meet minimum watchOS requirement 0x%X",
               encodedWatchOS,
               minimumWatchOS);
        StoreCachedRepairState(cacheKey, NO);
        return NO;
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NRDevice *matchedWatch = nil;
    NSString *productType = [NSString stringWithUTF8String:requestedProductType.c_str()];
    const char *requestedProductTypeCString = productType.UTF8String;
    dispatch_async(WatchFixMobileDataLookupQueue(), ^{
        Log("performing paired watch lookup for product type '%s'", requestedProductTypeCString);
        matchedWatch = CopyFirstMatchingPairedWatch(requestedProductTypeCString, minimumWatchOS);
        dispatch_semaphore_signal(semaphore);
    });

    BOOL signaled = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0;
    if (!signaled || !matchedWatch) {
        Log("paired watch lookup timed out or returned no match for %s", requestedProductTypeCString ?: "<nil>");
        return NO;
    }

    BOOL supportsCapability = [matchedWatch supportsCapability:WatchFixMobileDataCapabilityUUID()];
    StoreCachedRepairState(cacheKey, supportsCapability);
    Log("paired watch %s cellular capability for %s",
           supportsCapability ? "supports" : "does not support",
           requestedProductTypeCString ?: "<nil>");
    return supportsCapability;
}

static BOOL WatchFixShouldWrapValidateCallback(uint64_t maskedMessageTypes) {
    return (maskedMessageTypes & (0x20 | 0x200)) != 0;
}

static BOOL WatchFixIsBlockObject(id candidate) {
    if (!candidate) {
        return NO;
    }

    Class blockClass = NSClassFromString(@"NSBlock");
    return blockClass && [candidate isKindOfClass:blockClass];
}

static BOOL WrappedValidateCellularPlanDevice(WatchFixValidateDeviceBlock originalValidateBlock,
                                              uint64_t maskedMessageTypes,
                                              void *deviceContext) {
    if (originalValidateBlock && originalValidateBlock(deviceContext)) {
        Log("original validate callback returned YES, skip MobileDataSupport validation");
        return YES;
    }

    if (maskedMessageTypes & 0x20) {
        Log("validating for message type 0x20");
        return PairedWatchMeetsMobileDataRepairRequirements(deviceContext, 0x40000);
    }

    if (maskedMessageTypes & 0x200) {
        Log("validating for message type 0x200");
        return PairedWatchMeetsMobileDataRepairRequirements(deviceContext, 0x70000);
    }

    Log("unsupported message types 0x%llx, cannot validate", maskedMessageTypes);

    return NO;
}

%group MobileDataSupportFunctionHooks

%hookf(CFPropertyListRef, CFPropertyListCreateWithData, CFAllocatorRef allocator, CFDataRef data, CFOptionFlags options, CFPropertyListFormat *format, CFErrorRef *error)
{
    NSDictionary *origPlist = (NSDictionary *)CFBridgingRelease(%orig);
    if (![origPlist isKindOfClass:[NSDictionary class]]) {
        return (CFPropertyListRef)CFBridgingRetain(origPlist);
    }

    if (!origPlist[kRemoteCardProvisioningSettingsKey]) {
        return (CFPropertyListRef)CFBridgingRetain(origPlist);
    }

    NSMutableDictionary *newPlist = [origPlist mutableCopy];
    NSDictionary *settings = [newPlist objectForKey:kRemoteCardProvisioningSettingsKey];

    if (!settings || ![settings isKindOfClass:[NSDictionary class]]) {
        return (CFPropertyListRef)CFBridgingRetain(origPlist);
    }

    NSMutableDictionary *mutableSettings = [settings mutableCopy];
    NSArray *existingSkus = [mutableSettings objectForKey:kSupportedSKUsKey];
    NSMutableArray *mutableSkus;
    if (existingSkus && [existingSkus isKindOfClass:[NSArray class]]) {
        mutableSkus = [existingSkus mutableCopy];
    } else {
        mutableSkus = [NSMutableArray array];
    }

    if (![mutableSkus containsObject:kPost2018SKU]) {
        [mutableSkus addObject:kPost2018SKU];
    }

    [mutableSettings setObject:mutableSkus forKey:kSupportedSKUsKey];
    [newPlist setObject:mutableSettings forKey:kRemoteCardProvisioningSettingsKey];

    return (CFPropertyListRef)CFBridgingRetain(newPlist);
}

%end

%group MobileDataSupportDelegateHooks

%hook CellularPlanIDSServiceDelegate

- (BOOL)registerWithName:(NSString *)name
supportedIncomingMessageTypes:(uint64_t)supportedIncomingMessageTypes
   validateDeviceCallback:(id)validateDeviceCallback
    devicesChangedCallback:(id)devicesChangedCallback
  incomingMessageCallback:(id)incomingMessageCallback {
    uint64_t maskedMessageTypes = supportedIncomingMessageTypes & 0x7FFF;
    if (!WatchFixShouldWrapValidateCallback(maskedMessageTypes)) {
        Log("skipping validate callback wrapper for unsupported message types 0x%llx", maskedMessageTypes);
        return %orig(name,
                     maskedMessageTypes,
                     validateDeviceCallback,
                     devicesChangedCallback,
                     incomingMessageCallback);
    }

    if (validateDeviceCallback && !WatchFixIsBlockObject(validateDeviceCallback)) {
        Log("validate callback %p is not a block, skipping wrapper for message types 0x%llx",
            validateDeviceCallback,
            maskedMessageTypes);
        return %orig(name,
                     maskedMessageTypes,
                     validateDeviceCallback,
                     devicesChangedCallback,
                     incomingMessageCallback);
    }

    WatchFixValidateDeviceBlock originalValidateBlock = [(WatchFixValidateDeviceBlock)validateDeviceCallback copy];
    id wrappedValidateCallback = ^BOOL(void *deviceContext) {
        return WrappedValidateCellularPlanDevice(originalValidateBlock,
                                                 maskedMessageTypes,
                                                 deviceContext);
    };
    Log("wrapping validate callback %p as heap block %p for message types 0x%llx",
        validateDeviceCallback,
        originalValidateBlock,
        maskedMessageTypes);

    return %orig(name,
                 maskedMessageTypes,
                 wrappedValidateCallback,
                 devicesChangedCallback,
                 incomingMessageCallback);
}

%end

%end

%ctor {
    const char *progname = getprogname();
    if (!starts_with("CommCenter", progname)) {
        return;
    }

    if (isOSVersionAtLeast(17, 0, 0)) {
        Log("skip MobileDataSupport on iOS 17 or later");
        return;
    }

    Log("initializing MobileDataSupport");
    %init(MobileDataSupportFunctionHooks);
    Log("initialized CFPropertyListCreateWithData hook");

    if (objc_lookUpClass("CellularPlanIDSServiceDelegate")) {
        %init(MobileDataSupportDelegateHooks);
        Log("initialized CellularPlanIDSServiceDelegate hook");
    } else {
        Log("CellularPlanIDSServiceDelegate not found, skip delegate hook");
    }
}
