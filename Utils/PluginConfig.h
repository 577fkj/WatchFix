#import <Foundation/Foundation.h>

@class UIViewController;

NS_ASSUME_NONNULL_BEGIN

@interface WFPluginConfigurationContext : NSObject

@property (nonatomic, readonly, copy) NSString *pluginIdentifier;
@property (nonatomic, readonly, copy) NSString *pluginTitle;
@property (nonatomic, readonly, copy) NSString *pluginDetail;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *pluginManifest;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *pluginConfiguration;
@property (nonatomic, readonly, getter=isPluginInstalled) BOOL pluginInstalled;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (nullable NSNumber *)numberValueForConfigurationKey:(NSString *)key;
- (NSString *)localizedStringForKey:(NSString *)key fallback:(nullable NSString *)fallback;
- (BOOL)saveConfiguration:(NSDictionary<NSString *, id> *)configuration error:(NSError * _Nullable * _Nullable)error;
- (BOOL)installPlugin:(NSError * _Nullable * _Nullable)error;
- (BOOL)removePlugin:(NSError * _Nullable * _Nullable)error;
- (BOOL)installUsingDefaultImplementation:(NSError * _Nullable * _Nullable)error;
- (BOOL)removeUsingDefaultImplementation:(NSError * _Nullable * _Nullable)error;

@end

@protocol WFPluginConfigurationProvider <NSObject>
@optional
+ (nullable UIViewController *)configurationViewControllerWithContext:(WFPluginConfigurationContext *)context;
+ (nullable NSDictionary<NSString *, id> *)configurationPageWithContext:(WFPluginConfigurationContext *)context;
+ (nullable NSDictionary<NSString *, id> *)normalizedConfiguration:(NSDictionary<NSString *, id> *)configuration
                                                           context:(WFPluginConfigurationContext *)context;
+ (BOOL)didSaveConfigurationWithContext:(WFPluginConfigurationContext *)context error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)installPluginWithContext:(WFPluginConfigurationContext *)context error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)removePluginWithContext:(WFPluginConfigurationContext *)context error:(NSError * _Nullable * _Nullable)error;
@end

NSDictionary *WFCurrentPluginConfiguration(void);
NSNumber *WFCurrentPluginConfigurationNumberValue(NSString *key);
NSInteger WFCurrentPluginIntegerConfigurationValue(NSString *key, NSInteger fallbackValue);
BOOL WFCurrentPluginBooleanConfigurationValue(NSString *key, BOOL fallbackValue);
NSString *WFCurrentPluginStringConfigurationValue(NSString *key, NSString * _Nullable fallbackValue);

NS_ASSUME_NONNULL_END
