#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, WFCompatibilityReportSource) {
    WFCompatibilityReportSourceRegistry,
    WFCompatibilityReportSourceMagicCode,
};

typedef NS_ENUM(NSUInteger, WFCompatibilityReportState) {
    WFCompatibilityReportStateIndeterminate,
    WFCompatibilityReportStateCompatible,
    WFCompatibilityReportStateNeedsPairingSupport,
    WFCompatibilityReportStateUnavailable,
};

@interface WFCompatibilityReport : NSObject

@property(nonatomic, assign)         WFCompatibilityReportSource source;
@property(nonatomic, assign)         WFCompatibilityReportState  state;
@property(nonatomic, assign)         BOOL      hasActiveWatch;
@property(nonatomic, copy)           NSString *watchName;
@property(nonatomic, copy, nullable) NSString *productType;
@property(nonatomic, copy, nullable) NSString *watchOSVersion;
@property(nonatomic, copy, nullable) NSString *chipID;
@property(nonatomic, strong, nullable) NSNumber *deviceMaxCompatibilityVersion;
@property(nonatomic, strong, nullable) NSNumber *systemMinCompatibilityVersion;
@property(nonatomic, strong, nullable) NSNumber *systemMaxCompatibilityVersion;
@property(nonatomic, assign)         BOOL      inferred;
@property(nonatomic, copy, nullable) NSString *rawDescription;

@end

@interface WatchAPI : NSObject

+ (BOOL)syncWatchIsReachable:(NSError * _Nullable * _Nullable)error;
+ (nullable WFCompatibilityReport *)currentCompatibilityReport:(NSError * _Nullable * _Nullable)error;
+ (nullable WFCompatibilityReport *)compatibilityReportForScannedResult:(NSDictionary<NSString *, id> *)scanResult error:(NSError * _Nullable * _Nullable)error;
+ (void)scanLatestSoftwareUpdateWithCompletion:(void (^)(NSDictionary<NSString *, id> * _Nullable result, NSError * _Nullable error))completion;
+ (BOOL)rebootActiveWatch:(NSError * _Nullable * _Nullable)error;
+ (NSDictionary<NSString *, id> *)activeWatchValidationSnapshotForCapabilityUUIDStrings:(NSArray<NSString *> *)uuidStrings;
+ (NSDictionary<NSString *, id> *)activeWatchDebugPayload;
+ (NSDictionary<NSString *, id> *)activeWatchDebugSnapshotForCapabilityUUIDStrings:(NSArray<NSString *> *)uuidStrings;

@end

NS_ASSUME_NONNULL_END
