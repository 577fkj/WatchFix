#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const WFPluginBridgeDidChangeNotification;

@interface WFPluginBridge : NSObject

+ (NSDictionary<NSString *, NSNumber *> *)pluginStates;
+ (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)installedPluginVersions;
+ (NSDictionary<NSString *, NSNumber *> *)pairingCompatibilitySettings;
+ (NSDictionary<NSString *, id> *)configurationForPluginNamed:(NSString *)pluginName;
+ (BOOL)pluginHasConfigurationInterfaceNamed:(NSString *)pluginName NS_SWIFT_NAME(pluginHasConfigurationInterface(named:));
+ (nullable UIViewController *)configurationViewControllerForPluginNamed:(NSString *)pluginName error:(NSError * _Nullable * _Nullable)error;
+ (NSDictionary<NSString *, id> *)configurationPageForPluginNamed:(NSString *)pluginName error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)setPluginNamed:(NSString *)pluginName enabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)installPluginNamed:(NSString *)pluginName error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)removePluginNamed:(NSString *)pluginName error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)saveConfiguration:(NSDictionary<NSString *, id> *)configuration forPluginNamed:(NSString *)pluginName error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)savePairingCompatibilitySettings:(NSDictionary<NSString *, NSNumber *> *)settings error:(NSError * _Nullable * _Nullable)error;
+ (NSDictionary<NSString *, id> *)pluginLogSnapshot;
+ (BOOL)setPluginLoggingEnabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)clearPluginLogs:(NSError * _Nullable * _Nullable)error;
+ (BOOL)restartWatchServices:(NSError * _Nullable * _Nullable)error;
+ (nullable UIImage *)pluginIconForScopeIdentifier:(NSString *)scopeIdentifier;
+ (void)showWarningBannerWithMessage:(NSString *)message delay:(NSTimeInterval)delay;

@end

NS_ASSUME_NONNULL_END
