#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

typedef unsigned long long WatchFixNRDeviceSize;
typedef unsigned long long WatchFixPBBDeviceSize;

@interface WatchFixProductVersion : NSObject
@property (nonatomic, copy) NSString *familyName;
@property (nonatomic, assign) NSInteger major;
@property (nonatomic, assign) NSInteger minor;
@end

extern NSString *NRDevicePropertyProductType;
extern NSString *PBBridgeAdvertisingSizeKey;

__BEGIN_DECLS
WatchFixNRDeviceSize NRDeviceSizeForProductType(id productType);
WatchFixPBBDeviceSize BPSVariantSizeForProductType(id productType);
NSString *BPSLocalizedVariantSizeForProductType(id productType);
NSString *BPSShortLocalizedVariantSizeForProductType(id productType);
WatchFixPBBDeviceSize PBVariantSizeForProductType(id productType);
NSDictionary *PBAdvertisingInfoFromPayload(id payload);
NSString *BPSDeviceRemoteAssetString(void);
UIColor *BPSTextColor(void);
__END_DECLS

@interface WatchFixSoftwareUpdateTableView : UIView
- (UITextView *)updateCompanionTextView;
@end

@interface WatchFixSetupContext : NSObject
- (NSDictionary *)userInfo;
@end

@interface WatchFixBPSRemoteImageView : UIView
- (void)setFallbackImageName:(NSString *)name;
@end

@interface BPSWatchView : UIView
- (id)initWithStyle:(NSUInteger)style versionModifier:(id)versionModifier allowsMaterialFallback:(BOOL)allowsMaterialFallback;
- (CGSize)screenImageSize;
- (void)layoutWatchScreenImageView;
- (void)overrideMaterial:(NSInteger)material size:(NSInteger)size;
- (NSInteger)deviceSize;
- (NSUInteger)style;
- (UIView *)watchScreenImageView;
@end

@interface WatchFixPBBridgeProgressView : UIView
- (id)initWithStyle:(NSInteger)style andVersion:(NSInteger)version overrideSize:(NSInteger)overrideSize;
- (CGSize)_size;
- (CGFloat)_tickLength;
@end

@interface WatchFixPBBridgeWatchAttributeController : NSObject
+ (id)sharedDeviceController;
+ (NSInteger)_materialForCLHSValue:(NSInteger)clhs;
+ (NSString *)resourceString:(NSString *)prefix material:(NSInteger)material size:(NSInteger)size forAttributes:(NSUInteger)attrs;
+ (NSInteger)sizeFromDevice:(id)device;
- (NSInteger)size;
- (void)setDevice:(id)device;
- (NSString *)resourceString:(NSString *)prefix forAttributes:(NSUInteger)attrs;
- (NSInteger)fallbackMaterialForSize:(NSInteger)size;
- (NSInteger)material;
- (NSInteger)internalSize;
- (void)setInternalSize:(NSInteger)internalSize;
- (NSInteger)hardwareBehavior;
- (NSMutableDictionary *)stringCache;
@end

@interface NSObject (WatchFixWatchAppRuntime)
- (id)valueForProperty:(id)property;
@end

@interface PBBridgeAssetsManager : NSObject
- (void)beginPullingAssetsForDeviceMaterial:(NSInteger)material
                                       size:(NSInteger)size
                                   branding:(id)branding
                                 completion:(void (^)(NSInteger result))completion;
@end
