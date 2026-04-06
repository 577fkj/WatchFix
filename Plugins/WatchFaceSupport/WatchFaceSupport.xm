#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>

#include "utils.h"

@interface NSCoder (WatchFixWatchFaceSupport)
- (id)customDataForKey:(NSString *)key;
@end

@interface NTKEditOption : NSObject <NSSecureCoding>
- (instancetype)initWithDevice:(id)device;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (void)encodeWithCoder:(NSCoder *)coder;
@end

@interface NTKFaceConfiguration : NSObject <NSCopying, NSSecureCoding>
- (instancetype)initWithCoder:(NSCoder *)coder;
- (void)encodeWithCoder:(NSCoder *)coder;
- (void)setCustomData:(id)data forKey:(NSString *)key;
- (void)addConfigurationKeysToJSONDictionary:(NSMutableDictionary *)json;
- (void)addConfigurationKeysToJSONDictionary:(NSMutableDictionary *)json face:(id)face;
@end

@interface NTKFace : NSObject <NSSecureCoding>
+ (instancetype)faceWithJSONObjectRepresentation:(NSDictionary *)json
                                       forDevice:(id)device
                                    forMigration:(BOOL)forMigration
                allowFallbackFromInvalidFaceStyle:(BOOL)allowFallback;
+ (instancetype)defaultFaceOfStyle:(NSInteger)faceStyle forDevice:(id)device;
- (instancetype)initWithCoder:(NSCoder *)coder;
- (NSString *)bundleIdentifier;
- (void)_commonInit;
- (id)configuration;
@end

@interface NTKFaceBundle : NSObject
- (NSString *)identifier;
- (id)defaultFaceForDevice:(id)device;
- (NSArray *)galleryFacesForDevice:(id)device;
@end

@interface NTKFaceBundleManager : NSObject
- (id)faceBundleForBundleIdentifier:(NSString *)identifier onDevice:(id)device;
- (id)faceBundleForBundleIdentifier:(NSString *)identifier onDevice:(id)device forMigration:(BOOL)forMigration;
- (void)enumerateFaceBundlesOnDevice:(id)device withBlock:(void (^)(id bundle))block;
- (void)enumerateFaceBundlesOnDevice:(id)device includingLegacy:(BOOL)includingLegacy withBlock:(void (^)(id bundle))block;
@end

@interface NTKFaceView : UIView
- (instancetype)initWithFaceStyle:(NSInteger)faceStyle forDevice:(id)device clientIdentifier:(id)clientIdentifier;
- (UIView *)contentView;
@end

static NSString *const kWFSStubFaceBundleIdentifier =
    @"app.watchfix.hephaestus.watch-face-support.WFSStubFaces";
static NSString *const kWFSStubFaceBundleGalleryTitle = @"WatchFix Face Support";
static NSString *const kWFSStubFaceBundleGalleryDescription =
    @"New watchOS faces that are unavailable in iOS";
static NSString *const kWFSStubFaceSharingName = @"Unavailable";
static NSString *const kWFSPlaceholderSymbolName = @"questionmark.square.dashed";
static NSString *const kWFSPlaceholderTitle = @"Not Available in iOS";
static NSString *const kWFSPlaceholderDetail =
    @"Customise this watch face directly on your watch\n\nSee WatchFix for more details";
static NSString *const kWFSConfigBackingKey = @"StubJsonBacking";
static NSString *const kWFSMetricsKey = @"metrics";
static NSInteger const kWFSDefaultFaceStyle = 44;

@class WFSStubFace;
@class WFSStubFaceBundle;
@class WFSStubFaceConfiguration;

static WFSStubFaceBundle *gSharedStubFaceBundle = nil;

static NSString *WatchFixBundleIdentifierForObject(id bundle) {
    if (!bundle) {
        return nil;
    }

    SEL selector = @selector(identifier);
    if ([bundle respondsToSelector:selector]) {
        return ((NSString *(*)(id, SEL))objc_msgSend)(bundle, selector);
    }

    Class bundleClass = object_getClass(bundle);
    if (bundleClass && class_respondsToSelector(bundleClass, selector)) {
        return ((NSString *(*)(id, SEL))objc_msgSend)(bundleClass, selector);
    }

    return nil;
}

static WFSStubFaceBundle *WatchFixSharedStubFaceBundle(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class stubFaceBundleClass = objc_lookUpClass("WFSStubFaceBundle");
        if (!stubFaceBundleClass) {
            return;
        }
        gSharedStubFaceBundle = (WFSStubFaceBundle *)[[stubFaceBundleClass alloc] init];
    });
    return gSharedStubFaceBundle;
}

static void WatchFixAppendSharedStubBundleIfNeeded(BOOL sawStubBundle, void (^block)(id bundle)) {
    if (sawStubBundle || !block) {
        return;
    }

    block(WatchFixSharedStubFaceBundle());
}

static WFSStubFaceConfiguration *WatchFixStubConfigurationFromFace(WFSStubFace *face);

@interface WFSStubEditOption : NTKEditOption
@property(nonatomic, copy) NSDictionary *jsonRepresentation;
- (instancetype)initWithJSONObjectRepresentation:(NSDictionary *)json forDevice:(id)device;
@end

@interface WFSStubFaceConfiguration : NTKFaceConfiguration
@property(nonatomic, strong) NSMutableDictionary *jsonBacking;
- (void)mergeJSONObjectRepresentation:(NSDictionary *)json;
@end

@interface WFSStubFace : NTKFace
- (NSString *)realBundleIdentifier;
@end

@interface WFSStubFace ()
- (void)watchFix_installStubConfigurationIfNeeded;
@end

@interface WFSStubFaceBundle : NTKFaceBundle
+ (NSString *)identifier;
@end

@interface WFSStubFaceView : NTKFaceView
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *detailLabel;
@end

@implementation WFSStubEditOption

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithJSONObjectRepresentation:(NSDictionary *)json forDevice:(id)device {
    self = [super initWithDevice:device];
    if (!self) {
        return nil;
    }

    _jsonRepresentation = [json copy] ?: @{};
    return self;
}

- (instancetype)initWithDevice:(id)device {
    return [self initWithJSONObjectRepresentation:@{} forDevice:device];
}

- (instancetype)init {
    return [self initWithJSONObjectRepresentation:@{} forDevice:nil];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (!self) {
        return nil;
    }

    NSDictionary *jsonRepresentation = nil;
    if ([coder respondsToSelector:@selector(decodeObjectOfClass:forKey:)]) {
        jsonRepresentation = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"WFSJsonRepresentation"];
    } else {
        jsonRepresentation = [coder decodeObjectForKey:@"WFSJsonRepresentation"];
    }
    _jsonRepresentation = [jsonRepresentation copy] ?: @{};
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    [coder encodeObject:self.jsonRepresentation forKey:@"WFSJsonRepresentation"];
}

- (NSString *)dailySnapshotKey {
    return @"watchfix-unsupported";
}

- (NSString *)localizedName {
    return @"WatchFix Edit Option";
}

- (BOOL)isValidOption {
    return YES;
}

- (NSDictionary *)JSONObjectRepresentation {
    return self.jsonRepresentation ?: @{};
}

@end

@implementation WFSStubFaceConfiguration

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    _jsonBacking = [[NSMutableDictionary alloc] init];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (!self) {
        return nil;
    }

    NSDictionary *archivedBacking = nil;
    if ([coder respondsToSelector:@selector(customDataForKey:)]) {
        archivedBacking = [coder customDataForKey:kWFSConfigBackingKey];
    }
    if (!archivedBacking) {
        if ([coder respondsToSelector:@selector(decodeObjectOfClass:forKey:)]) {
            archivedBacking = [coder decodeObjectOfClass:[NSDictionary class] forKey:kWFSConfigBackingKey];
        } else {
            archivedBacking = [coder decodeObjectForKey:kWFSConfigBackingKey];
        }
    }

    if ([archivedBacking isKindOfClass:[NSDictionary class]]) {
        _jsonBacking = [archivedBacking mutableCopy];
    } else {
        _jsonBacking = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if ([self respondsToSelector:@selector(setCustomData:forKey:)]) {
        [self setCustomData:self.jsonBacking forKey:kWFSConfigBackingKey];
    }

    [super encodeWithCoder:coder];
    [coder encodeObject:self.jsonBacking forKey:kWFSConfigBackingKey];

    if ([self respondsToSelector:@selector(setCustomData:forKey:)]) {
        [self setCustomData:nil forKey:kWFSConfigBackingKey];
    }
}

- (void)mergeJSONObjectRepresentation:(NSDictionary *)json {
    if (![json isKindOfClass:[NSDictionary class]]) {
        return;
    }

    NSMutableDictionary *copy = [json mutableCopy];
    [copy removeObjectForKey:kWFSMetricsKey];
    [self.jsonBacking addEntriesFromDictionary:copy];
}

- (void)addConfigurationKeysToJSONDictionary:(NSMutableDictionary *)json {
    if (![json isKindOfClass:[NSMutableDictionary class]]) {
        return;
    }

    [json addEntriesFromDictionary:self.jsonBacking ?: @{}];
}

- (void)addConfigurationKeysToJSONDictionary:(NSMutableDictionary *)json face:(id)face {
    (void)face;
    [self addConfigurationKeysToJSONDictionary:json];
}

- (id)copyWithZone:(NSZone *)zone {
    WFSStubFaceConfiguration *copy = [super copyWithZone:zone];
    if (![copy isKindOfClass:[WFSStubFaceConfiguration class]]) {
        copy = [[[self class] allocWithZone:zone] init];
    }

    copy.jsonBacking = [self.jsonBacking mutableCopy];
    return copy;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[WFSStubFaceConfiguration class]]) {
        return NO;
    }
    if (![super isEqual:object]) {
        return NO;
    }
    return [self.jsonBacking isEqual:((WFSStubFaceConfiguration *)object).jsonBacking];
}

- (NSUInteger)hash {
    return [super hash] ^ self.jsonBacking.hash;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ [backing=%@]", [super description], self.jsonBacking];
}

@end

static WFSStubFaceConfiguration *WatchFixStubConfigurationFromFace(WFSStubFace *face) {
    if (!face || ![face respondsToSelector:@selector(configuration)]) {
        return nil;
    }

    id configuration = [face configuration];
    if (![configuration isKindOfClass:[WFSStubFaceConfiguration class]]) {
        return nil;
    }
    return configuration;
}

@implementation WFSStubFace

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)watchFix_installStubConfigurationIfNeeded {
    id configuration = nil;
    if ([self respondsToSelector:@selector(configuration)]) {
        configuration = [self configuration];
    }

    if ([configuration isKindOfClass:[WFSStubFaceConfiguration class]]) {
        return;
    }

    @try {
        [self setValue:[[WFSStubFaceConfiguration alloc] init] forKey:@"_configuration"];
    } @catch (NSException *exception) {
        Log("failed to install stub face configuration: %s",
            CStringOrPlaceholder(exception.reason));
    }
}

- (NSString *)faceSharingName {
    return kWFSStubFaceSharingName;
}

- (NSString *)bundleIdentifier {
    return [WFSStubFaceBundle identifier];
}

- (NSString *)realBundleIdentifier {
    return [super bundleIdentifier];
}

- (void)_commonInit {
    [super _commonInit];
    [self watchFix_installStubConfigurationIfNeeded];
}

- (BOOL)_applyConfiguration:(id)configuration allowFailure:(BOOL)allowFailure {
    return [self _applyConfiguration:configuration allowFailure:allowFailure forMigration:NO];
}

- (BOOL)_applyConfiguration:(id)configuration allowFailure:(BOOL)allowFailure forMigration:(BOOL)forMigration {
    (void)allowFailure;
    (void)forMigration;

    WFSStubFaceConfiguration *targetConfiguration = WatchFixStubConfigurationFromFace(self);
    if (!targetConfiguration) {
        targetConfiguration = [[WFSStubFaceConfiguration alloc] init];
    }

    if ([configuration isKindOfClass:[WFSStubFaceConfiguration class]]) {
        targetConfiguration = configuration;
    } else if (configuration) {
        NSMutableDictionary *json = [NSMutableDictionary dictionary];
        if ([configuration respondsToSelector:@selector(addConfigurationKeysToJSONDictionary:face:)]) {
            [configuration addConfigurationKeysToJSONDictionary:json face:self];
        } else if ([configuration respondsToSelector:@selector(addConfigurationKeysToJSONDictionary:)]) {
            [configuration addConfigurationKeysToJSONDictionary:json];
        }
        [targetConfiguration mergeJSONObjectRepresentation:json];
    } else {
        return NO;
    }

    @try {
        [self setValue:targetConfiguration forKey:@"_configuration"];
    } @catch (NSException *exception) {
        Log("failed to apply stub configuration: %s", CStringOrPlaceholder(exception.reason));
        return NO;
    }
    return YES;
}

- (Class)editOptionClassFromEditMode:(NSInteger)mode resourceDirectoryExists:(BOOL)exists {
    (void)mode;
    (void)exists;
    return [WFSStubEditOption class];
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    [self watchFix_installStubConfigurationIfNeeded];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (!self) {
        return nil;
    }

    [self watchFix_installStubConfigurationIfNeeded];
    return self;
}

@end

@implementation WFSStubFaceBundle

+ (NSString *)identifier {
    return kWFSStubFaceBundleIdentifier;
}

- (NSString *)identifier {
    return [[self class] identifier];
}

- (NSString *)galleryTitle {
    return kWFSStubFaceBundleGalleryTitle;
}

- (NSString *)galleryDescriptionText {
    return kWFSStubFaceBundleGalleryDescription;
}

- (Class)faceClass {
    return [WFSStubFace class];
}

- (Class)faceViewClass {
    return [WFSStubFaceView class];
}

- (id)defaultFaceForDevice:(id)device {
    if ([WFSStubFace respondsToSelector:@selector(defaultFaceOfStyle:forDevice:)]) {
        return [WFSStubFace defaultFaceOfStyle:kWFSDefaultFaceStyle forDevice:device];
    }

    return [[WFSStubFace alloc] init];
}

- (NSArray *)galleryFacesForDevice:(id)device {
    (void)device;
    return @[];
}

@end

@implementation WFSStubFaceView

- (UIView *)watchFix_contentContainerView {
    UIView *contentView = nil;
    if ([self respondsToSelector:@selector(contentView)]) {
        contentView = [self contentView];
    }
    return contentView ?: self;
}

- (void)watchFix_buildPlaceholderIfNeeded {
    if (self.iconView || self.titleLabel || self.detailLabel) {
        return;
    }

    UIView *contentView = [self watchFix_contentContainerView];

    self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.tintColor = [UIColor secondaryLabelColor];
    self.iconView.image = [UIImage systemImageNamed:kWFSPlaceholderSymbolName];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.titleLabel.text = kWFSPlaceholderTitle;

    self.detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.detailLabel.textAlignment = NSTextAlignmentCenter;
    self.detailLabel.numberOfLines = 0;
    self.detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.detailLabel.textColor = [UIColor secondaryLabelColor];
    self.detailLabel.text = kWFSPlaceholderDetail;

    [contentView addSubview:self.iconView];
    [contentView addSubview:self.titleLabel];
    [contentView addSubview:self.detailLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [self.titleLabel.bottomAnchor constraintEqualToAnchor:contentView.centerYAnchor],
        [self.titleLabel.widthAnchor constraintLessThanOrEqualToAnchor:contentView.widthAnchor multiplier:0.85],
        [self.iconView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [self.iconView.bottomAnchor constraintEqualToAnchor:self.titleLabel.topAnchor constant:-8.0],
        [self.iconView.widthAnchor constraintEqualToAnchor:contentView.widthAnchor multiplier:0.25],
        [self.iconView.heightAnchor constraintEqualToAnchor:self.iconView.widthAnchor],
        [self.detailLabel.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [self.detailLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8.0],
        [self.detailLabel.widthAnchor constraintLessThanOrEqualToAnchor:contentView.widthAnchor multiplier:0.85],
    ]];
}

- (UIImageView *)switcherSnapshotView {
    return nil;
}

- (void)setSwitcherSnapshotView:(id)view {
    (void)view;
}

- (instancetype)initWithFaceStyle:(NSInteger)faceStyle forDevice:(id)device clientIdentifier:(id)clientIdentifier {
    self = [super initWithFaceStyle:faceStyle forDevice:device clientIdentifier:clientIdentifier];
    if (!self) {
        return nil;
    }

    [self watchFix_buildPlaceholderIfNeeded];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (!self) {
        return nil;
    }

    [self watchFix_buildPlaceholderIfNeeded];
    return self;
}

@end

%group WatchFaceSupportFaceFactory

%hook NTKFace

+ (id)faceWithJSONObjectRepresentation:(NSDictionary *)json
                              forDevice:(id)device
                           forMigration:(BOOL)forMigration
       allowFallbackFromInvalidFaceStyle:(BOOL)allowFallback {
    id face = %orig;
    if ([face isKindOfClass:[WFSStubFace class]]) {
        WFSStubFaceConfiguration *configuration = WatchFixStubConfigurationFromFace(face);
        if (configuration) {
            [configuration mergeJSONObjectRepresentation:json];
        }
    }
    return face;
}

%end

%end

%group WatchFaceSupportLookupLegacy

%hook NTKFaceBundleManager

- (id)faceBundleForBundleIdentifier:(NSString *)identifier onDevice:(id)device {
    id bundle = %orig;
    return bundle ?: WatchFixSharedStubFaceBundle();
}

%end

%end

%group WatchFaceSupportLookupMigration

%hook NTKFaceBundleManager

- (id)faceBundleForBundleIdentifier:(NSString *)identifier onDevice:(id)device forMigration:(BOOL)forMigration {
    id bundle = %orig;
    return bundle ?: WatchFixSharedStubFaceBundle();
}

%end

%end

%group WatchFaceSupportEnumerateLegacy

%hook NTKFaceBundleManager

- (void)enumerateFaceBundlesOnDevice:(id)device withBlock:(void (^)(id bundle))block {
    __block BOOL sawStubBundle = NO;
    void (^trackingBlock)(id bundle) = ^(id bundle) {
        NSString *identifier = WatchFixBundleIdentifierForObject(bundle);
        if ([identifier isEqualToString:kWFSStubFaceBundleIdentifier]) {
            sawStubBundle = YES;
        }
        if (block) {
            block(bundle);
        }
    };

    %orig(device, trackingBlock);
    WatchFixAppendSharedStubBundleIfNeeded(sawStubBundle, block);
}

%end

%end

%group WatchFaceSupportEnumerateModern

%hook NTKFaceBundleManager

- (void)enumerateFaceBundlesOnDevice:(id)device includingLegacy:(BOOL)includingLegacy withBlock:(void (^)(id bundle))block {
    __block BOOL sawStubBundle = NO;
    void (^trackingBlock)(id bundle) = ^(id bundle) {
        NSString *identifier = WatchFixBundleIdentifierForObject(bundle);
        if ([identifier isEqualToString:kWFSStubFaceBundleIdentifier]) {
            sawStubBundle = YES;
        }
        if (block) {
            block(bundle);
        }
    };

    %orig(device, includingLegacy, trackingBlock);
    WatchFixAppendSharedStubBundleIfNeeded(sawStubBundle, block);
}

%end

%end

static void WatchFixInstallWatchFaceSupportHooks(void) {
    Class faceClass = objc_lookUpClass("NTKFace");
    Class bundleManagerClass = objc_lookUpClass("NTKFaceBundleManager");
    if (!faceClass || !bundleManagerClass) {
        Log("required NanoTimeKit classes are unavailable, skipping WatchFaceSupport");
        return;
    }

    WatchFixSharedStubFaceBundle();

    %init(WatchFaceSupportFaceFactory, NTKFace=faceClass);
    Log("face factory hooks installed");

    %init(WatchFaceSupportLookupLegacy, NTKFaceBundleManager=bundleManagerClass);
    Log("legacy bundle lookup hook installed");
    %init(WatchFaceSupportLookupMigration, NTKFaceBundleManager=bundleManagerClass);
    Log("migration bundle lookup hook installed");

    %init(WatchFaceSupportEnumerateLegacy, NTKFaceBundleManager=bundleManagerClass);
    Log("legacy bundle enumeration hook installed");

    %init(WatchFaceSupportEnumerateModern, NTKFaceBundleManager=bundleManagerClass);
    Log("modern bundle enumeration hook installed");
}

%ctor {
    const char *progname = getprogname();
    if (!progname) {
        return;
    }

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    const char *bundleIDCString = [bundleID UTF8String];
    Log("Bundle ID   : %s", bundleIDCString);
    Log("Program Name: %s", progname);

    if (!is_equal(bundleIDCString, "com.apple.Bridge") && !is_equal(progname, "nanotimekitcompaniond")) {
        return;
    }

    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Log("installing WatchFaceSupport hooks");
        WatchFixInstallWatchFaceSupportHooks();
    });
}
