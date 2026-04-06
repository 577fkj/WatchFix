#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#include "utils.h"

@interface IDSService : NSObject
- (instancetype)initWithService:(NSString *)service;
- (void)addDelegate:(id)delegate queue:(dispatch_queue_t)queue;
- (void)setProtobufAction:(const char *)action forIncomingRequestsOfType:(NSUInteger)type;
- (BOOL)sendProtobuf:(id)protobuf
      toDestinations:(NSSet *)destinations
            priority:(NSInteger)priority
             options:(NSDictionary *)options
          identifier:(id *)identifier
               error:(NSError **)error;
@end

@interface IDSProtobuf : NSObject
- (instancetype)initWithProtobufData:(NSData *)data type:(NSUInteger)type isResponse:(BOOL)isResponse;
@end

@interface NRPairedDeviceRegistry : NSObject
+ (instancetype)sharedInstance;
- (id)getActivePairedDevice;
@end

@interface NRDevice : NSObject
- (BOOL)supportsCapability:(NSUUID *)capability;
@end

@interface PBDataWriter : NSObject
- (void)writeBOOL:(BOOL)value forTag:(uint32_t)tag;
- (void)writeData:(NSData *)value forTag:(uint32_t)tag;
- (void)writeDouble:(double)value forTag:(uint32_t)tag;
- (void)writeInt32:(int32_t)value forTag:(uint32_t)tag;
- (void)writeString:(NSString *)value forTag:(uint32_t)tag;
- (NSData *)data;
@end

@interface MPIdentifierSet : NSObject
- (instancetype)initWithModelKind:(id)modelKind block:(void (^)(MPIdentifierSet *identifierSet))block;
- (id)library;
- (void)setDeviceLibraryPersistentID:(int64_t)persistentID;
@end

@interface MPModelKind : NSObject
+ (instancetype)kindWithModelClass:(Class)modelClass;
@end

@interface MPModelAlbum : NSObject
- (instancetype)initWithIdentifiers:(id)identifiers;
- (id)identifiers;
@end

@interface MPModelPlaylist : NSObject
- (instancetype)initWithIdentifiers:(id)identifiers;
- (id)identifiers;
@end

@interface MPMediaLibrary (WatchFixMediaSyncSupport)
- (id)multiverseIdentifierForCollectionWithPersistentID:(int64_t)persistentID
                                           groupingType:(NSInteger)groupingType;
@end

@interface NSObject (WatchFixMediaSyncSupport)
- (NSData *)data;
- (id)incomingResponseIdentifier;
- (id)library;
- (int64_t)persistentID;
@end

extern id IDSDefaultPairedDevice;
extern NSString *const IDSSendMessageOptionExpectsPeerResponseKey;
extern NSString *const IDSSendMessageOptionForceLocalDeliveryKey;
extern NSString *const IDSSendMessageOptionTimeoutKey;

typedef void (^WFMSSKeepLocalCompletion)(BOOL success);
typedef void (^WFMSSCompletionHandler)(void);

typedef NS_ENUM(int32_t, WFMSSKeepLocalAction) {
    WFMSSKeepLocalActionPin = 1,
    WFMSSKeepLocalActionUnpin = 2,
};

typedef NS_ENUM(int32_t, WFMSSContainerType) {
    WFMSSContainerTypeAlbum = 0,
    WFMSSContainerTypePlaylist = 1,
};

typedef NS_ENUM(NSInteger, WFMSSCollectionGroupingType) {
    WFMSSCollectionGroupingTypeAlbum = 1,
    WFMSSCollectionGroupingTypePlaylist = 6,
};

static NSString *const kWFMSSIDSServiceName = @"com.apple.private.alloy.nanomediasync";
static NSString *const kWFMSSBridgeAlertTitle = @"MediaSyncSupport Media Pinning";
static const char *kWFMSSBridgePreferencesFrameworkPath = "/System/Library/PrivateFrameworks/BridgePreferences.framework/BridgePreferences";
static NSTimeInterval const kWFMSSTimeoutSeconds = 15.0;

@interface WFMSSKincaidSyncHelper : NSObject

+ (instancetype)sharedInstance;

- (BOOL)activePairedDeviceNeedsKincaidSyncStyle;
- (void)setAlbumWithPersistentID:(int64_t)persistentID
                     isKeptLocal:(BOOL)isKeptLocal
                      completion:(WFMSSKeepLocalCompletion)completion;
- (void)setPlaylistWithPersistentID:(int64_t)persistentID
                        isKeptLocal:(BOOL)isKeptLocal
                         completion:(WFMSSKeepLocalCompletion)completion;

@end

@interface WFMSSKincaidSyncHelper ()

@property(nonatomic, strong) NSUUID *capability;
@property(nonatomic, strong) NSMutableDictionary *requestMap;
@property(nonatomic, strong) NRPairedDeviceRegistry *registry;
@property(nonatomic, strong) IDSService *service;
@property(nonatomic, strong) dispatch_queue_t serviceQueue;

- (NSData *)multiverseDataFromMediaModelObject:(id)modelObject;
- (id)modelObjectOfClass:(Class)modelClass withPersistentID:(int64_t)persistentID;
- (void)completePendingRequestForResponseIdentifier:(id)responseIdentifier success:(BOOL)success;
- (void)ensureService;
- (void)handleKeepLocalRequestForModelClass:(Class)modelClass
                               persistentID:(int64_t)persistentID
                                isKeptLocal:(BOOL)isKeptLocal
                                 completion:(WFMSSKeepLocalCompletion)completion;
- (id)sendKeepLocalRequestPayload:(NSData *)payload;
- (void)service:(id)service
        account:(id)account
     identifier:(id)identifier
didSendWithSuccess:(BOOL)didSend
          error:(NSError *)error;
- (void)service:(id)service
        account:(id)account
incomingUnhandledProtobuf:(id)protobuf
         fromID:(id)fromID
        context:(id)context;
- (void)storePendingCompletion:(WFMSSKeepLocalCompletion)completion responseIdentifier:(id)responseIdentifier;
- (void)_handleKeepLocalResponse:(id)protobuf
                         service:(id)service
                         account:(id)account
                          fromID:(id)fromID
                         context:(id)context;

@end

static int64_t WatchFixMediaSyncPersistentIDFromToken(id token) {
    if (!token) {
        return 0;
    }

    if ([token respondsToSelector:@selector(longLongValue)]) {
        return (int64_t)[token longLongValue];
    }

    if ([token respondsToSelector:@selector(identifiers)]) {
        id identifiers = [token identifiers];
        id library = [identifiers respondsToSelector:@selector(library)] ? [identifiers library] : nil;
        if ([library respondsToSelector:@selector(persistentID)]) {
            return (int64_t)[library persistentID];
        }
    }

    return 0;
}

static void WatchFixMediaSyncInvokeCompletion(id completion) {
    if (!completion) {
        return;
    }

    ((WFMSSCompletionHandler)completion)();
}

static void WatchFixMediaSyncPresentUnreachableServiceAlert(void) {
    void *handle = dlopen(kWFMSSBridgePreferencesFrameworkPath, RTLD_LAZY);
    if (!handle) {
        Log("failed to open BridgePreferences.framework");
        return;
    }

    typedef void (*WFMSSAlertFunction)(CFStringRef title, id dismissalHandler);
    WFMSSAlertFunction function = (WFMSSAlertFunction)dlsym(
        handle,
        "BPSPresentGizmoUnreachableServiceAlertWithDismissalHandler");
    if (!function) {
        dlclose(handle);
        Log("failed to resolve BPSPresentGizmoUnreachableServiceAlertWithDismissalHandler");
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        function((__bridge CFStringRef)kWFMSSBridgeAlertTitle, ^(id unused) {
        });
        dlclose(handle);
    });
}

static NSData *WatchFixMediaSyncBuildKeepLocalRequestPayload(id modelObject, BOOL isKeptLocal) {
    WFMSSKincaidSyncHelper *helper = [WFMSSKincaidSyncHelper sharedInstance];
    NSData *multiverseData = [helper multiverseDataFromMediaModelObject:modelObject];
    if (multiverseData.length == 0) {
        Log("unable to derive multiverse data");
        return nil;
    }

    int32_t containerType = -1;
    if ([modelObject isKindOfClass:[MPModelAlbum class]]) {
        containerType = WFMSSContainerTypeAlbum;
    } else if ([modelObject isKindOfClass:[MPModelPlaylist class]]) {
        containerType = WFMSSContainerTypePlaylist;
    } else {
        Log("unsupported model object class: %s", object_getClassName(modelObject));
        return nil;
    }

    PBDataWriter *innerWriter = [[NSClassFromString(@"PBDataWriter") alloc] init];
    PBDataWriter *policyWriter = [[NSClassFromString(@"PBDataWriter") alloc] init];
    PBDataWriter *outerWriter = [[NSClassFromString(@"PBDataWriter") alloc] init];
    if (!innerWriter || !policyWriter || !outerWriter) {
        Log("PBDataWriter unavailable");
        return nil;
    }

    [innerWriter writeData:multiverseData forTag:0];
    [innerWriter writeInt32:containerType forTag:1];

    [policyWriter writeBOOL:YES forTag:0];
    [policyWriter writeInt32:0 forTag:1];
    [policyWriter writeInt32:0 forTag:2];
    [policyWriter writeInt32:3 forTag:3];
    [policyWriter writeDouble:15.0 forTag:4];
    [policyWriter writeString:@"com.apple.NanoMusic" forTag:5];

    [outerWriter writeData:[innerWriter data] forTag:0];
    [outerWriter writeInt32:(isKeptLocal ? WFMSSKeepLocalActionPin : WFMSSKeepLocalActionUnpin) forTag:1];
    [outerWriter writeData:[policyWriter data] forTag:2];
    return [outerWriter data];
}

@implementation WFMSSKincaidSyncHelper

+ (instancetype)sharedInstance {
    static WFMSSKincaidSyncHelper *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _registry = [NRPairedDeviceRegistry sharedInstance];
        _capability = [[NSUUID alloc] initWithUUIDString:@"06FB3B8E-7CE9-4C98-A47E-87BCCCB70EC1"];
        _requestMap = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (BOOL)activePairedDeviceNeedsKincaidSyncStyle {
    id pairedDevice = [self.registry getActivePairedDevice];
    if (!pairedDevice || !self.capability) {
        return NO;
    }

    if (![pairedDevice respondsToSelector:@selector(supportsCapability:)]) {
        return NO;
    }

    return [pairedDevice supportsCapability:self.capability];
}

- (void)setAlbumWithPersistentID:(int64_t)persistentID
                     isKeptLocal:(BOOL)isKeptLocal
                      completion:(WFMSSKeepLocalCompletion)completion {
    [self handleKeepLocalRequestForModelClass:[MPModelAlbum class]
                                 persistentID:persistentID
                                  isKeptLocal:isKeptLocal
                                   completion:completion];
}

- (void)setPlaylistWithPersistentID:(int64_t)persistentID
                        isKeptLocal:(BOOL)isKeptLocal
                         completion:(WFMSSKeepLocalCompletion)completion {
    [self handleKeepLocalRequestForModelClass:[MPModelPlaylist class]
                                 persistentID:persistentID
                                  isKeptLocal:isKeptLocal
                                   completion:completion];
}

- (void)handleKeepLocalRequestForModelClass:(Class)modelClass
                               persistentID:(int64_t)persistentID
                                isKeptLocal:(BOOL)isKeptLocal
                                 completion:(WFMSSKeepLocalCompletion)completion {
    id modelObject = [self modelObjectOfClass:modelClass withPersistentID:persistentID];
    NSData *payload = WatchFixMediaSyncBuildKeepLocalRequestPayload(modelObject, isKeptLocal);
    id responseIdentifier = [self sendKeepLocalRequestPayload:payload];
    if (responseIdentifier) {
        [self storePendingCompletion:completion responseIdentifier:responseIdentifier];
        return;
    }

    if (completion) {
        completion(NO);
    }
}

- (id)modelObjectOfClass:(Class)modelClass withPersistentID:(int64_t)persistentID {
    id modelKind = [NSClassFromString(@"MPModelKind") kindWithModelClass:modelClass];
    if (!modelKind) {
        Log("MPModelKind unavailable for %s", class_getName(modelClass));
        return nil;
    }

    MPIdentifierSet *identifierSet = [[NSClassFromString(@"MPIdentifierSet") alloc]
        initWithModelKind:modelKind
                    block:^(MPIdentifierSet *identifierSet) {
                        [identifierSet setDeviceLibraryPersistentID:persistentID];
                    }];
    if (!identifierSet) {
        Log("failed to build MPIdentifierSet");
        return nil;
    }

    return [[modelClass alloc] initWithIdentifiers:identifierSet];
}

- (NSData *)multiverseDataFromMediaModelObject:(id)modelObject {
    if (!modelObject) {
        return nil;
    }

    WFMSSCollectionGroupingType groupingType = WFMSSCollectionGroupingTypeAlbum;
    if ([modelObject isKindOfClass:[MPModelAlbum class]]) {
        groupingType = WFMSSCollectionGroupingTypeAlbum;
    } else if ([modelObject isKindOfClass:[MPModelPlaylist class]]) {
        groupingType = WFMSSCollectionGroupingTypePlaylist;
    } else {
        return nil;
    }

    id identifiers = [modelObject respondsToSelector:@selector(identifiers)] ? [modelObject identifiers] : nil;
    id libraryIdentifiers = [identifiers respondsToSelector:@selector(library)] ? [identifiers library] : nil;
    if (![libraryIdentifiers respondsToSelector:@selector(persistentID)]) {
        Log("model object has no library persistent identifier");
        return nil;
    }

    int64_t persistentID = (int64_t)[libraryIdentifiers persistentID];
    id mediaLibrary = [NSClassFromString(@"MPMediaLibrary") defaultMediaLibrary];
    if (!mediaLibrary) {
        Log("MPMediaLibrary unavailable");
        return nil;
    }

    id multiverseIdentifier = [mediaLibrary multiverseIdentifierForCollectionWithPersistentID:persistentID
                                                                                  groupingType:groupingType];
    if ([multiverseIdentifier isKindOfClass:[NSData class]]) {
        return multiverseIdentifier;
    }

    if ([multiverseIdentifier respondsToSelector:@selector(data)]) {
        return [multiverseIdentifier data];
    }

    return nil;
}

- (void)ensureService {
    @synchronized (self) {
        if (self.service) {
            return;
        }

        NSString *queueName = [NSString stringWithFormat:@"%@.service-queue", NSStringFromClass([self class])];
        self.serviceQueue = dispatch_queue_create(queueName.UTF8String, DISPATCH_QUEUE_SERIAL);
        self.service = [[NSClassFromString(@"IDSService") alloc] initWithService:kWFMSSIDSServiceName];
        if (!self.service) {
            Log("IDSService unavailable for %s", kWFMSSIDSServiceName.UTF8String);
            return;
        }

        if ([self.service respondsToSelector:@selector(addDelegate:queue:)]) {
            [self.service addDelegate:self queue:self.serviceQueue];
        }
        if ([self.service respondsToSelector:@selector(setProtobufAction:forIncomingRequestsOfType:)]) {
            [self.service setProtobufAction:"_handleKeepLocalResponse:service:account:fromID:context:"
                    forIncomingRequestsOfType:2];
        }
    }
}

- (id)sendKeepLocalRequestPayload:(NSData *)payload {
    if (payload.length == 0) {
        return nil;
    }

    [self ensureService];
    if (!self.service || !IDSDefaultPairedDevice) {
        Log("IDS route unavailable");
        return nil;
    }

    IDSProtobuf *requestProtobuf = [[NSClassFromString(@"IDSProtobuf") alloc]
        initWithProtobufData:payload
                        type:1
                  isResponse:NO];
    if (!requestProtobuf) {
        Log("failed to construct IDSProtobuf");
        return nil;
    }

    NSDictionary *options = @{
        IDSSendMessageOptionExpectsPeerResponseKey : @YES,
        IDSSendMessageOptionForceLocalDeliveryKey : (id)kCFBooleanTrue,
        IDSSendMessageOptionTimeoutKey : @(kWFMSSTimeoutSeconds),
    };

    id responseIdentifier = nil;
    NSError *sendError = nil;
    BOOL didSend = [self.service sendProtobuf:requestProtobuf
                               toDestinations:[NSSet setWithObject:IDSDefaultPairedDevice]
                                     priority:0
                                      options:options
                                   identifier:&responseIdentifier
                                        error:&sendError];
    if (!didSend) {
        Log("IDS send failed: %s", CStringOrPlaceholder(sendError.localizedDescription));
        return nil;
    }

    return responseIdentifier;
}

- (void)storePendingCompletion:(WFMSSKeepLocalCompletion)completion responseIdentifier:(id)responseIdentifier {
    if (!completion || !responseIdentifier) {
        return;
    }

    @synchronized (self) {
        self.requestMap[responseIdentifier] = [completion copy];
    }
}

- (void)completePendingRequestForResponseIdentifier:(id)responseIdentifier success:(BOOL)success {
    if (!responseIdentifier) {
        return;
    }

    WFMSSKeepLocalCompletion completion = nil;
    @synchronized (self) {
        completion = self.requestMap[responseIdentifier];
        [self.requestMap removeObjectForKey:responseIdentifier];
    }

    if (completion) {
        completion(success);
    }
}

- (void)service:(id)service
        account:(id)account
     identifier:(id)identifier
didSendWithSuccess:(BOOL)didSend
          error:(NSError *)error {
    if (didSend) {
        return;
    }

    Log("IDS send callback reported failure: %s", CStringOrPlaceholder(error.localizedDescription));
    [self completePendingRequestForResponseIdentifier:identifier success:NO];
    WatchFixMediaSyncPresentUnreachableServiceAlert();
}

- (void)service:(id)service
        account:(id)account
incomingUnhandledProtobuf:(id)protobuf
         fromID:(id)fromID
        context:(id)context {
}

- (void)_handleKeepLocalResponse:(id)protobuf
                         service:(id)service
                         account:(id)account
                          fromID:(id)fromID
                         context:(id)context {
    id responseIdentifier = [context respondsToSelector:@selector(incomingResponseIdentifier)] ?
        [context incomingResponseIdentifier] :
        nil;
    [self completePendingRequestForResponseIdentifier:responseIdentifier success:YES];
}

@end

%group MediaSyncSupportHooks

%hook WFMediaPinningManager

- (void)pinAlbum:(id)album completionHandler:(id)completion {
    WFMSSKincaidSyncHelper *helper = [WFMSSKincaidSyncHelper sharedInstance];
    if (![helper activePairedDeviceNeedsKincaidSyncStyle]) {
        %orig;
        return;
    }

    int64_t persistentID = WatchFixMediaSyncPersistentIDFromToken(album);
    if (persistentID == 0) {
        Log("failed to extract album persistent ID");
        WatchFixMediaSyncInvokeCompletion(completion);
        return;
    }

    id albumToken = album;
    id completionToken = completion;
    [helper setAlbumWithPersistentID:persistentID
                         isKeptLocal:YES
                          completion:^(BOOL success) {
                              if (success) {
                                  %orig(albumToken, nil);
                              }
                              WatchFixMediaSyncInvokeCompletion(completionToken);
                          }];
}

- (void)pinPlaylist:(id)playlist completionHandler:(id)completion {
    WFMSSKincaidSyncHelper *helper = [WFMSSKincaidSyncHelper sharedInstance];
    if (![helper activePairedDeviceNeedsKincaidSyncStyle]) {
        %orig;
        return;
    }

    int64_t persistentID = WatchFixMediaSyncPersistentIDFromToken(playlist);
    if (persistentID == 0) {
        Log("failed to extract playlist persistent ID");
        WatchFixMediaSyncInvokeCompletion(completion);
        return;
    }

    id playlistToken = playlist;
    id completionToken = completion;
    [helper setPlaylistWithPersistentID:persistentID
                            isKeptLocal:YES
                             completion:^(BOOL success) {
                                 if (success) {
                                     %orig(playlistToken, nil);
                                 }
                                 WatchFixMediaSyncInvokeCompletion(completionToken);
                             }];
}

- (void)unpinAlbum:(id)album completionHandler:(id)completion {
    WFMSSKincaidSyncHelper *helper = [WFMSSKincaidSyncHelper sharedInstance];
    if (![helper activePairedDeviceNeedsKincaidSyncStyle]) {
        %orig;
        return;
    }

    int64_t persistentID = WatchFixMediaSyncPersistentIDFromToken(album);
    if (persistentID == 0) {
        Log("failed to extract album persistent ID for unpin");
        WatchFixMediaSyncInvokeCompletion(completion);
        return;
    }

    id albumToken = album;
    id completionToken = completion;
    [helper setAlbumWithPersistentID:persistentID
                         isKeptLocal:NO
                          completion:^(BOOL success) {
                              if (success) {
                                  %orig(albumToken, nil);
                              }
                              WatchFixMediaSyncInvokeCompletion(completionToken);
                          }];
}

- (void)unpinPlaylist:(id)playlist completionHandler:(id)completion {
    WFMSSKincaidSyncHelper *helper = [WFMSSKincaidSyncHelper sharedInstance];
    if (![helper activePairedDeviceNeedsKincaidSyncStyle]) {
        %orig;
        return;
    }

    int64_t persistentID = WatchFixMediaSyncPersistentIDFromToken(playlist);
    if (persistentID == 0) {
        Log("failed to extract playlist persistent ID for unpin");
        WatchFixMediaSyncInvokeCompletion(completion);
        return;
    }

    id playlistToken = playlist;
    id completionToken = completion;
    [helper setPlaylistWithPersistentID:persistentID
                            isKeptLocal:NO
                             completion:^(BOOL success) {
                                 if (success) {
                                     %orig(playlistToken, nil);
                                 }
                                 WatchFixMediaSyncInvokeCompletion(completionToken);
                             }];
}

%end

%end


%ctor {
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    Log("Bundle ID   : %s", CStringOrPlaceholder(bundleIdentifier));
    Log("Program Name: %s", getprogname());

    if (![bundleIdentifier isEqualToString:@"com.apple.Bridge"] &&
        ![bundleIdentifier isEqualToString:@"com.apple.NanoMusicSync"]) {
        return;
    }

    if (isOSVersionAtLeast(16, 0, 0)) {
        Log("running on iOS 16 or newer, skipping MediaSyncSupport hooks");
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class managerClass = objc_lookUpClass("NMSMediaPinningManager");
        if (!managerClass) {
            Log("NMSMediaPinningManager not found, skipping MediaSyncSupport");
            return;
        }

        %init(MediaSyncSupportHooks, WFMediaPinningManager=managerClass);
        Log("MediaSyncSupport hooks installed");
    });
}
