#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <sys/clonefile.h>
#import <unistd.h>

#include "utils.h"

@interface IDSService : NSObject
- (void)addDelegate:(id)delegate queue:(dispatch_queue_t)queue;
- (BOOL)sendProtobuf:(id)protobuf
      toDestinations:(NSSet *)destinations
            priority:(NSInteger)priority
             options:(NSDictionary *)options
          identifier:(id *)identifier
               error:(NSError **)error;
- (BOOL)sendResourceAtURL:(NSURL *)url
                 metadata:(NSDictionary *)metadata
           toDestinations:(NSSet *)destinations
                 priority:(NSInteger)priority
                  options:(NSDictionary *)options
               identifier:(id *)identifier
                    error:(NSError **)error;
@end

@interface IDSProtobuf : NSObject
- (instancetype)initWithProtobufData:(NSData *)data type:(NSUInteger)type isResponse:(BOOL)isResponse;
- (NSData *)data;
- (NSUInteger)type;
- (id)outgoingResponseIdentifier;
@end

@interface NPTOTemporaryFile : NSObject
- (NSURL *)URL;
- (NSDictionary *)metadata;
@end

@interface NMSMessageCenter : NSObject
- (instancetype)initWithDevice:(id)device service:(IDSService *)service;
- (void)addIncomingFileHandler:(NSString *)handler forMessageID:(NSUInteger)messageID;
- (void)service:(IDSService *)service
         account:(id)account
incomingResourceAtURL:(NSURL *)incomingURL
        metadata:(NSDictionary *)metadata
          fromID:(id)fromID
         context:(id)context;
@end

@interface NPTOCompanionSyncDeviceController : NSObject
- (instancetype)initWithDevice:(id)device service:(IDSService *)service;
- (id)device;
- (void)_beginSync;
- (void)_endSync;
@end

@interface NPTOCompanionSyncDeviceContentController : NSObject
- (instancetype)initWithDevice:(id)device;
- (void)setDelegate:(id)delegate;
- (id)composeSyncRequest;
- (PHAsset *)assetForLocalIdentifier:(NSString *)localIdentifier;
@end

@interface NPTOSyncRequest : NSObject
- (NSData *)data;
- (id)library;
- (id)collectionTargetList;
@end

@interface NRPairedDeviceRegistry : NSObject
+ (instancetype)sharedInstance;
- (id)deviceForIDSDevice:(id)device;
@end

@interface NRDevice : NSObject
- (BOOL)supportsCapability:(NSUUID *)capability;
@end

@interface PBDataWriter : NSObject
- (void)writeString:(NSString *)value forTag:(uint32_t)tag;
- (NSData *)data;
@end

@interface PBDataReader : NSObject
- (instancetype)initWithData:(NSData *)data;
- (BOOL)readTag:(uint32_t *)tag type:(uint8_t *)type;
- (NSData *)readData;
- (BOOL)readBOOL;
- (BOOL)hasMoreData;
- (BOOL)hasError;
@end

@interface PHImportController : NSObject
+ (instancetype)sharedInstance;
- (void)importUrls:(NSArray<NSURL *> *)urls
       withOptions:(id)options
          delegate:(id)delegate
             atEnd:(void (^)(id results))completion;
@end

@interface PHImportOptions : NSObject
- (void)setAllowDuplicates:(BOOL)allowDuplicates;
@end

@interface PHAssetChangeRequest (WatchFixPhotoLibrarySupport)
- (void)setModificationDate:(NSDate *)modificationDate;
@end

@interface PHAsset (WatchFixPhotoLibrarySupport)
+ (NSString *)localIdentifierWithUUID:(NSUUID *)uuid;
- (void)npto_exportForDevice:(id)device completionHandler:(void (^)(NPTOTemporaryFile *temporaryFile))completionHandler;
@end

@interface WFIDSDevice : NSObject
- (NSString *)uniqueID;
@end

@class PLSSyncDeviceController;

extern "C" uint32_t NRWatchOSVersionForRemoteDevice(id device);
extern "C" CFStringRef IDSCopyIDForDevice(id device);
extern "C" void PBDataWriterWriteSubmessage(PBDataWriter *writer, id value, uint32_t tag);
extern "C" void PBReaderSkipValueWithTag(PBDataReader *reader, uint32_t tag, uint8_t type);

extern NSString *const IDSSendMessageOptionExpectsPeerResponseKey;
extern NSString *const IDSSendMessageOptionNonWakingKey;
extern NSString *const IDSSendMessageOptionPeerResponseIdentifierKey;
extern NSString *const IDSSendMessageOptionPushPriorityKey;
extern NSString *const IDSSendMessageOptionQueueOneIdentifierKey;
extern NSString *const IDSSendMessageOptionTimeoutKey;

static NSUInteger const kWFJupiterInboundMessageID = 9;
static NSUInteger const kWFPhotoSyncSignalProtobufType = 101;
static NSUInteger const kWFPhotoSyncSnapshotProtobufType = 102;
static NSUInteger const kWFPhotoSyncAssetRequestProtobufType = 103;
static NSInteger const kWFWatchOSMinimumMajor = 8;
static NSInteger const kWFSendPriorityHigh = 200;

static char kWFPhotoImportCapabilityAssociationKey;
static char kWFControllerAssociationKey;

static id WatchFixPairedDeviceForIDSDevice(id idsDevice) {
    if (!idsDevice) {
        return nil;
    }

    NRPairedDeviceRegistry *registry = [NRPairedDeviceRegistry sharedInstance];
    if (!registry) {
        return nil;
    }

    return [registry deviceForIDSDevice:idsDevice];
}

static id WatchFixIDSDestinationForDevice(id idsDevice) {
    if (!idsDevice) {
        return nil;
    }

    return CFBridgingRelease(IDSCopyIDForDevice(idsDevice));
}

static BOOL WatchFixSyncControllerIsFor(id controller) {
    if (![controller respondsToSelector:@selector(device)]) {
        return NO;
    }

    id idsDevice = [(id)controller device];
    id pairedDevice = WatchFixPairedDeviceForIDSDevice(idsDevice);
    if (!pairedDevice) {
        return NO;
    }

    uint32_t watchOSVersion = NRWatchOSVersionForRemoteDevice(pairedDevice);
    return watchOSVersion != UINT32_MAX && ((watchOSVersion >> 16) > kWFWatchOSMinimumMajor);
}

@interface PLSImportManager : NSObject
+ (instancetype)sharedManager;
- (void)importAssetsAtURLs:(NSArray<NSURL *> *)urls;
@end

@interface PLSSyncDeviceController : NSObject
@property(nonatomic, strong) id contentController;
@property(nonatomic, strong) id syncRequest;
@property(nonatomic, copy) NSString *syncHash;
@property(nonatomic, strong) dispatch_queue_t syncQueue;
@property(nonatomic, strong) dispatch_queue_t idsQueue;
@property(nonatomic, strong) NSOperationQueue *exportAssetsQueue;
@property(nonatomic, strong) NSOperationQueue *sendAssetsQueue;
@property(nonatomic, weak) IDSService *service;
@property(nonatomic, weak) id idsDevice;
- (void)sendPhotoSyncSignalIfNeeded;
- (void)cancelPendingPhotoTransferOperations;
@end

@implementation PLSImportManager

+ (instancetype)sharedManager {
    static PLSImportManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (void)importAssetsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) {
        return;
    }

    Class importControllerClass = NSClassFromString(@"PHImportController");
    Class importOptionsClass = NSClassFromString(@"PHImportOptions");
    if (!importControllerClass || !importOptionsClass) {
        Log(@"PHImportController or PHImportOptions unavailable");
        return;
    }

    PHImportController *importController = [importControllerClass sharedInstance];
    PHImportOptions *options = [[importOptionsClass alloc] init];
    [options setAllowDuplicates:NO];

    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);

    [importController importUrls:urls
                     withOptions:options
                        delegate:nil
                           atEnd:^(__unused id results) {
        dispatch_group_leave(group);
    }];

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
}

@end

@implementation PLSSyncDeviceController

- (id)photoSyncContentController {
    if (!self.contentController) {
        Class contentControllerClass = NSClassFromString(@"NPTOCompanionSyncDeviceContentController");
        if (!contentControllerClass || !self.idsDevice) {
            return nil;
        }

        NPTOCompanionSyncDeviceContentController *contentController =
            [[contentControllerClass alloc] initWithDevice:self.idsDevice];
        if ([contentController respondsToSelector:@selector(setDelegate:)]) {
            [contentController setDelegate:self];
        }
        self.contentController = contentController;
    }

    return self.contentController;
}

- (void)cancelPendingPhotoTransferOperations {
    [self.exportAssetsQueue cancelAllOperations];
    [self.sendAssetsQueue cancelAllOperations];
    [self.exportAssetsQueue waitUntilAllOperationsAreFinished];
    [self.sendAssetsQueue waitUntilAllOperationsAreFinished];
}

- (void)sendPhotoSyncSignalIfNeeded {
    if (!self.syncRequest) {
        self.syncRequest = [[self photoSyncContentController] composeSyncRequest];
        NSData *requestData = [self.syncRequest data];
        if (requestData.length > 0) {
            unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {};
            CC_SHA256(requestData.bytes, (CC_LONG)requestData.length, digest);

            NSMutableString *output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
            for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
                [output appendFormat:@"%02x", digest[index]];
            }
            self.syncHash = output;
        }
    }

    if (![[self.syncRequest library] respondsToSelector:@selector(class)]) {
        return;
    }

    PBDataWriter *writer = [[NSClassFromString(@"PBDataWriter") alloc] init];
    if (!writer || self.syncHash.length == 0) {
        return;
    }

    [writer writeString:self.syncHash forTag:1];

    NSDictionary *options = @{
        IDSSendMessageOptionExpectsPeerResponseKey: @NO,
        IDSSendMessageOptionNonWakingKey: @YES,
        IDSSendMessageOptionPushPriorityKey: @5,
        IDSSendMessageOptionQueueOneIdentifierKey: @"NanoPhotosSync-SyncSignal",
        IDSSendMessageOptionTimeoutKey: @604800,
    };

    IDSProtobuf *protobuf = [[NSClassFromString(@"IDSProtobuf") alloc]
        initWithProtobufData:[writer data]
                        type:kWFPhotoSyncSignalProtobufType
                  isResponse:NO];

    if (!self.service || !self.idsDevice || !protobuf) {
        return;
    }

    id destinationID = WatchFixIDSDestinationForDevice(self.idsDevice);
    if (!destinationID) {
        Log(@"missing IDS destination for photo sync protobuf");
        return;
    }

    NSSet *destinations = [NSSet setWithObject:destinationID];
    id identifier = nil;
    NSError *error = nil;
    [self.service sendProtobuf:protobuf
                toDestinations:destinations
                      priority:kWFSendPriorityHigh
                       options:options
                    identifier:&identifier
                         error:&error];
    if (error) {
        Log(@"failed to send photo sync signal: %@", error.localizedDescription);
    }
}

- (void)service:(__unused id)service
         account:(__unused id)account
incomingUnhandledProtobuf:(IDSProtobuf *)protobuf
          fromID:(__unused id)fromID
         context:(__unused id)context {
    NSUInteger protobufType = [protobuf type];
    if (protobufType == kWFPhotoSyncAssetRequestProtobufType) {
        NSData *payload = [protobuf data];
        PBDataReader *reader = [[NSClassFromString(@"PBDataReader") alloc] initWithData:payload];
        NSData *requestedUUIDBytes = nil;

        while ([reader hasMoreData] && ![reader hasError]) {
            uint32_t tag = 0;
            uint8_t type = 0;
            [reader readTag:&tag type:&type];

            if (tag == 1) {
                requestedUUIDBytes = [reader readData];
            } else if (tag == 2) {
                [reader readBOOL];
            } else {
                PBReaderSkipValueWithTag(reader, tag, type);
            }
        }

        if (![reader hasError] && requestedUUIDBytes.length == 16) {
            NSUUID *requestedUUID =
                [[NSUUID alloc] initWithUUIDBytes:(const unsigned char *)requestedUUIDBytes.bytes];
            id outgoingResponseIdentifier = [protobuf outgoingResponseIdentifier];

            if (!self.exportAssetsQueue) {
                self.exportAssetsQueue = [[NSOperationQueue alloc] init];
                self.exportAssetsQueue.name = @"wfplsupport.export";
                self.exportAssetsQueue.maxConcurrentOperationCount = 3;
            }

            __weak __typeof__(self) weakSelf = self;
            [self.exportAssetsQueue addOperationWithBlock:^{
                __strong __typeof__(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }

                id contentController = [strongSelf photoSyncContentController];
                NSString *localIdentifier = [PHAsset localIdentifierWithUUID:requestedUUID];
                PHAsset *asset = [contentController assetForLocalIdentifier:localIdentifier];
                id pairedDevice = WatchFixPairedDeviceForIDSDevice(strongSelf.idsDevice);
                if (!asset || !pairedDevice) {
                    return;
                }

                [asset npto_exportForDevice:pairedDevice completionHandler:^(NPTOTemporaryFile *temporaryFile) {
                    __strong __typeof__(weakSelf) innerSelf = weakSelf;
                    if (!innerSelf || !temporaryFile) {
                        return;
                    }

                    if (!innerSelf.sendAssetsQueue) {
                        innerSelf.sendAssetsQueue = [[NSOperationQueue alloc] init];
                        innerSelf.sendAssetsQueue.name = @"wfplsupport.send";
                        innerSelf.sendAssetsQueue.maxConcurrentOperationCount = 2;
                    }

                    [innerSelf.sendAssetsQueue addOperationWithBlock:^{
                        __strong __typeof__(weakSelf) sendSelf = weakSelf;
                        if (!sendSelf || !sendSelf.service || !sendSelf.idsDevice) {
                            return;
                        }

                        id destinationID = WatchFixIDSDestinationForDevice(sendSelf.idsDevice);
                        if (!destinationID) {
                            return;
                        }

                        NSMutableDictionary *options = [NSMutableDictionary dictionaryWithObject:@60
                                                                                          forKey:IDSSendMessageOptionTimeoutKey];
                        if (outgoingResponseIdentifier) {
                            options[IDSSendMessageOptionPeerResponseIdentifierKey] = outgoingResponseIdentifier;
                        }

                        NSSet *destinations = [NSSet setWithObject:destinationID];
                        NSURL *resourceURL = [temporaryFile URL];
                        NSDictionary *metadata = [temporaryFile metadata];
                        id identifier = nil;
                        NSError *error = nil;

                        [sendSelf.service sendResourceAtURL:resourceURL
                                                   metadata:metadata
                                             toDestinations:destinations
                                                   priority:kWFSendPriorityHigh
                                                    options:options
                                                 identifier:&identifier
                                                      error:&error];

                        if (error) {
                            Log(@"failed to send exported photo resource: %@",
                                  error.localizedDescription);
                        }
                    }];
                }];
            }];
        }
        return;
    }

    if (protobufType != kWFPhotoSyncSnapshotProtobufType) {
        return;
    }

    if (self.syncQueue) {
        dispatch_sync(self.syncQueue, ^{
            [self sendPhotoSyncSignalIfNeeded];
        });
    } else {
        [self sendPhotoSyncSignalIfNeeded];
    }

    id library = [self.syncRequest library];
    if (!library) {
        return;
    }

    PBDataWriter *writer = [[NSClassFromString(@"PBDataWriter") alloc] init];
    if (!writer) {
        return;
    }

    PBDataWriterWriteSubmessage(writer, library, 1);
    PBDataWriterWriteSubmessage(writer, [self.syncRequest collectionTargetList], 2);
    if (self.syncHash.length > 0) {
        [writer writeString:self.syncHash forTag:3];
    }

    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithObject:@60
                                                                      forKey:IDSSendMessageOptionTimeoutKey];
    id outgoingResponseIdentifier = [protobuf outgoingResponseIdentifier];
    if (outgoingResponseIdentifier) {
        options[IDSSendMessageOptionPeerResponseIdentifierKey] = outgoingResponseIdentifier;
    }

    IDSProtobuf *response = [[NSClassFromString(@"IDSProtobuf") alloc]
        initWithProtobufData:[writer data]
                        type:kWFPhotoSyncSnapshotProtobufType
                  isResponse:YES];

    if (!self.service || !self.idsDevice || !response) {
        return;
    }

    id destinationID = WatchFixIDSDestinationForDevice(self.idsDevice);
    if (!destinationID) {
        Log(@"missing IDS destination for photo sync protobuf");
        return;
    }

    NSSet *destinations = [NSSet setWithObject:destinationID];
    id identifier = nil;
    NSError *error = nil;
    [self.service sendProtobuf:response
                toDestinations:destinations
                      priority:kWFSendPriorityHigh
                       options:options
                    identifier:&identifier
                         error:&error];
    if (error) {
        Log(@"failed to send photo sync snapshot response: %@", error.localizedDescription);
    }
}

- (void)controllerDidInvalidateContent:(__unused id)contentController {
    if (!self.syncQueue) {
        return;
    }

    __weak __typeof__(self) weakSelf = self;
    dispatch_async(self.syncQueue, ^{
        __strong __typeof__(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        [strongSelf cancelPendingPhotoTransferOperations];
        strongSelf.syncRequest = nil;
        strongSelf.syncHash = nil;
        [strongSelf sendPhotoSyncSignalIfNeeded];
    });
}

@end

%group PhotoLibrarySupportCommon

%hook NMSMessageCenter

- (instancetype)initWithDevice:(id)device service:(id)service {
    id object = %orig(device, service);
    if (!object) {
        return nil;
    }

    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion <= 14 &&
        [object respondsToSelector:@selector(addIncomingFileHandler:forMessageID:)]) {
        [object addIncomingFileHandler:@"wf_pls_handleJupiterInboundFile:"
                          forMessageID:kWFJupiterInboundMessageID];
    }

    id pairedDevice = WatchFixPairedDeviceForIDSDevice(device);
    static NSUUID *capabilityUUID = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        capabilityUUID = [[NSUUID alloc] initWithUUIDString:@"EF9E8C3A-6B59-47E0-BA2F-212213F1A30D"];
    });
    if ([pairedDevice respondsToSelector:@selector(supportsCapability:)] &&
        [pairedDevice supportsCapability:capabilityUUID]) {
        objc_setAssociatedObject(object,
                                 &kWFPhotoImportCapabilityAssociationKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    return object;
}

- (void)service:(id)service
         account:(id)account
incomingResourceAtURL:(NSURL *)incomingURL
        metadata:(NSDictionary *)metadata
          fromID:(id)fromID
         context:(id)context {
    BOOL isPhotoImportCompatible =
        [objc_getAssociatedObject(self, &kWFPhotoImportCapabilityAssociationKey) boolValue];
    if (incomingURL && isPhotoImportCompatible) {
        NSString *basename = incomingURL.URLByDeletingPathExtension.lastPathComponent ?: incomingURL.lastPathComponent;
        NSString *temporaryPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[NSString stringWithFormat:@"wf_incoming-%@",
                                                                    basename ?: @"resource"]];

        if (clonefile(incomingURL.fileSystemRepresentation, temporaryPath.fileSystemRepresentation, 0) == 0) {
            NSURL *temporaryURL = [NSURL fileURLWithPath:temporaryPath];
            [[PLSImportManager sharedManager] importAssetsAtURLs:@[ temporaryURL ]];
            unlink(temporaryURL.fileSystemRepresentation);
        } else {
            Log(@"clonefile failed for incoming photo resource at %@", incomingURL.path);
        }
        return;
    }

    %orig(service, account, incomingURL, metadata, fromID, context);
}

%new
- (void)wf_pls_handleJupiterInboundFile:(NPTOTemporaryFile *)temporaryFile {
    NSURL *incomingURL = [temporaryFile URL];
    if (!incomingURL) {
        return;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:incomingURL.path]) {
        return;
    }

    NSDictionary *metadata = [temporaryFile metadata] ?: @{};
    NSInteger mediaType = [metadata[@"mt"] integerValue];
    NSError *error = nil;

    [[PHPhotoLibrary sharedPhotoLibrary] performChangesAndWait:^{
        PHAssetChangeRequest *changeRequest = nil;
        if (mediaType == 1) {
            changeRequest = [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:incomingURL];
        } else if (mediaType == 2) {
            changeRequest = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:incomingURL];
        }

        if (!changeRequest) {
            return;
        }

        changeRequest.creationDate = metadata[@"cd"];
        changeRequest.modificationDate = metadata[@"md"];
    } error:&error];

    if (error) {
        Log(@"failed to import Jupiter inbound file: %@", error.localizedDescription);
    }
}

%end

%end

%group PhotoLibrarySupportLegacySync

%hook NPTOCompanionSyncDeviceController

- (instancetype)initWithDevice:(id)device service:(id)service {
    id controller = %orig(device, service);
    if (!controller || !WatchFixSyncControllerIsFor(controller)) {
        return controller;
    }

    PLSSyncDeviceController *helper = [[PLSSyncDeviceController alloc] init];
    helper.idsDevice = device;
    helper.service = service;

    WFIDSDevice *idsDevice = (WFIDSDevice *)device;
    NSString *uniqueID = nil;
    if ([idsDevice respondsToSelector:@selector(uniqueID)]) {
        uniqueID = idsDevice.uniqueID;
    }

    NSString *idsQueueName = [NSString stringWithFormat:@"%@.%@",
                                                        NSStringFromClass([helper class]),
                                                        uniqueID ?: @"unknown"];
    helper.idsQueue = dispatch_queue_create(idsQueueName.UTF8String, DISPATCH_QUEUE_SERIAL);
    helper.syncQueue = dispatch_queue_create("wfplsupport.sync", DISPATCH_QUEUE_SERIAL);

    if ([service respondsToSelector:@selector(addDelegate:queue:)]) {
        [service addDelegate:helper queue:helper.idsQueue];
    }

    objc_setAssociatedObject(controller,
                             &kWFControllerAssociationKey,
                             helper,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return controller;
}

- (void)_beginSync {
    if (WatchFixSyncControllerIsFor(self)) {
        PLSSyncDeviceController *helper =
            objc_getAssociatedObject(self, &kWFControllerAssociationKey);
        if (helper.syncQueue) {
            dispatch_sync(helper.syncQueue, ^{
                [helper cancelPendingPhotoTransferOperations];
                [helper sendPhotoSyncSignalIfNeeded];
            });
        }
        return;
    }

    %orig;
}

- (void)_endSync {
    if (WatchFixSyncControllerIsFor(self)) {
        PLSSyncDeviceController *helper =
            objc_getAssociatedObject(self, &kWFControllerAssociationKey);
        if (helper.syncQueue) {
            dispatch_sync(helper.syncQueue, ^{
                [helper cancelPendingPhotoTransferOperations];
            });
        }
        return;
    }

    %orig;
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
    if (!is_equal("nptocompaniond", progname)) {
        return;
    }

    NSInteger hostOSMajorVersion = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
    Log(@"initializing PhotoLibrarySupport for host major %ld", (long)hostOSMajorVersion);

    if (hostOSMajorVersion >= 17) {
        Log(@"host major version >= 17, skipping PhotoLibrarySupport hooks");
        return;
    }

    %init(PhotoLibrarySupportCommon);

    if (hostOSMajorVersion >= 16) {
        return;
    }

    %init(PhotoLibrarySupportLegacySync);
}
