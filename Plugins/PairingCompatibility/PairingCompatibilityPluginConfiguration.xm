#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "PluginBridge.h"
#import "PluginConfig.h"
#import "Logging.h"
#include "PairingCompatibility.h"

static NSString *const kPairingMinKey = @"PairingCompatibilityMinVersion";
static NSString *const kPairingMaxKey = @"PairingCompatibilityMaxVersion";
static NSString *const kHelloThresholdKey = @"PairingCompatibilityHelloThreshold";
static NSString *const kModifyDeviceSupportRangeEnabledKey = @"PairingCompatibilityModifyDeviceSupportRangeEnabled";
static NSString *const kFrameworkHooksEnabledKey = @"PairingCompatibilityFrameworkCompatibilityHooksEnabled";
static NSString *const kNanoRegistryHooksEnabledKey = @"PairingCompatibilityNanoRegistryHooksEnabled";
static NSString *const kIDSHooksEnabledKey = @"PairingCompatibilityIDSHooksEnabled";
static NSString *const kMockIOSVersionHooksEnabledKey = @"PairingCompatibilityMockIOSVersionHooksEnabled";
static NSString *const kPassKitHooksEnabledKey = @"PairingCompatibilityPassKitHooksEnabled";
static NSString *const kBLEHooksEnabledKey = @"PairingCompatibilityBLEHooksEnabled";
static NSString *const kMockIOSMajorKey = @"PairingCompatibilityMockIOSMajorVersion";
static NSString *const kMockIOSMinorKey = @"PairingCompatibilityMockIOSMinorVersion";
static NSString *const kMockIOSBuildKey = @"PairingCompatibilityMockIOSBuild";
static NSString *const kChipIDsKey = @"PairingCompatibilityChipIDs";

static NSString *const kNanoRegistryPreferencesPath = @"/var/mobile/Library/Preferences/com.apple.NanoRegistry.plist";
static NSString *const kPairedSyncPreferencesPath = @"/var/mobile/Library/Preferences/com.apple.pairedsync.plist";

static NSInteger const kDeviceSupportRangeMinCompatibilityVersion = MIN_COMP;
static NSInteger const kDeviceSupportRangeMaxCompatibilityVersion = MAX_COMP;
static NSInteger const kDeviceSupportRangeActivityTimeout = ACTIVE_TIMEOUT;

typedef BOOL (^WFPairingOperationBlock)(NSError **error);

static NSString *WFPairingConfigurationLocalized(WFPluginConfigurationContext *context, NSString *key) {
    return [context localizedStringForKey:key fallback:nil];
}

static NSString *WFPairingStringValue(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSInteger WFPairingConfigurationIntegerValue(NSDictionary<NSString *, id> *configuration, NSString *key, NSInteger fallbackValue) {
    id value = configuration[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value integerValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *stringValue = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (stringValue.length > 0) {
            return stringValue.integerValue;
        }
    }
    return fallbackValue;
}

static BOOL WFPairingConfigurationBoolValue(NSDictionary<NSString *, id> *configuration, NSString *key, BOOL fallbackValue) {
    id value = configuration[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *stringValue = [[(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        if ([stringValue isEqualToString:@"1"] || [stringValue isEqualToString:@"true"] || [stringValue isEqualToString:@"yes"] || [stringValue isEqualToString:@"on"]) {
            return YES;
        }
        if ([stringValue isEqualToString:@"0"] || [stringValue isEqualToString:@"false"] || [stringValue isEqualToString:@"no"] || [stringValue isEqualToString:@"off"]) {
            return NO;
        }
    }
    return fallbackValue;
}

static NSDictionary<NSString *, id> *WFPairingDefaultConfiguration(void) {
    return @{
        kPairingMinKey: @MIN_COMP,
        kPairingMaxKey: @MAX_COMP,
        kHelloThresholdKey: @HELLO_COMP,
        kModifyDeviceSupportRangeEnabledKey: @YES,
        kFrameworkHooksEnabledKey: @YES,
        kNanoRegistryHooksEnabledKey: @YES,
        kIDSHooksEnabledKey: @YES,
        kMockIOSVersionHooksEnabledKey: @YES,
        kPassKitHooksEnabledKey: @YES,
        kBLEHooksEnabledKey: @YES,
        kMockIOSMajorKey: @OS_MAJOR,
        kMockIOSMinorKey: @OS_MINOR,
        kMockIOSBuildKey: OS_BUILD,
        kChipIDsKey: @"",
    };
}

static NSDictionary<NSString *, id> *WFPairingNormalizedConfiguration(NSDictionary<NSString *, id> *configuration) {
    NSDictionary<NSString *, id> *defaults = WFPairingDefaultConfiguration();
    NSInteger minValue = MAX(0, MIN(64, WFPairingConfigurationIntegerValue(configuration, kPairingMinKey, [defaults[kPairingMinKey] integerValue])));
    NSInteger maxValue = MAX(minValue, MIN(64, WFPairingConfigurationIntegerValue(configuration, kPairingMaxKey, [defaults[kPairingMaxKey] integerValue])));
    NSInteger thresholdValue = MAX(0, MIN(64, WFPairingConfigurationIntegerValue(configuration, kHelloThresholdKey, [defaults[kHelloThresholdKey] integerValue])));
    NSInteger mockMajor = MAX(14, MIN(30, WFPairingConfigurationIntegerValue(configuration, kMockIOSMajorKey, OS_MAJOR)));
    NSInteger mockMinor = MAX(0, MIN(20, WFPairingConfigurationIntegerValue(configuration, kMockIOSMinorKey, OS_MINOR)));
    NSString *mockBuild = WFPairingStringValue(configuration[kMockIOSBuildKey]);
    if (mockBuild.length == 0) { mockBuild = OS_BUILD; }
    NSString *chipIDs = WFPairingStringValue(configuration[kChipIDsKey]) ?: @"";

    return @{
        kPairingMinKey: @(minValue),
        kPairingMaxKey: @(maxValue),
        kHelloThresholdKey: @(thresholdValue),
        kModifyDeviceSupportRangeEnabledKey: @(WFPairingConfigurationBoolValue(configuration, kModifyDeviceSupportRangeEnabledKey, [defaults[kModifyDeviceSupportRangeEnabledKey] boolValue])),
        kFrameworkHooksEnabledKey: @(WFPairingConfigurationBoolValue(configuration, kFrameworkHooksEnabledKey, [defaults[kFrameworkHooksEnabledKey] boolValue])),
        kNanoRegistryHooksEnabledKey: @(WFPairingConfigurationBoolValue(configuration, kNanoRegistryHooksEnabledKey, [defaults[kNanoRegistryHooksEnabledKey] boolValue])),
        kIDSHooksEnabledKey: @(WFPairingConfigurationBoolValue(configuration, kIDSHooksEnabledKey, [defaults[kIDSHooksEnabledKey] boolValue])),
        kMockIOSVersionHooksEnabledKey: @(WFPairingConfigurationBoolValue(configuration, kMockIOSVersionHooksEnabledKey, [defaults[kMockIOSVersionHooksEnabledKey] boolValue])),
        kPassKitHooksEnabledKey: @(WFPairingConfigurationBoolValue(configuration, kPassKitHooksEnabledKey, [defaults[kPassKitHooksEnabledKey] boolValue])),
        kBLEHooksEnabledKey: @(WFPairingConfigurationBoolValue(configuration, kBLEHooksEnabledKey, [defaults[kBLEHooksEnabledKey] boolValue])),
        kMockIOSMajorKey: @(mockMajor),
        kMockIOSMinorKey: @(mockMinor),
        kMockIOSBuildKey: mockBuild,
        kChipIDsKey: chipIDs,
    };
}

static void WFPairingSetPreferenceValue(CFStringRef appID, CFStringRef key, CFPropertyListRef value, CFStringRef user, CFStringRef host) {
    CFPreferencesSetValue(key, value, appID, user, host);
}

static BOOL WFPairingSynchronizePreferences(CFStringRef appID, CFStringRef user, CFStringRef host, NSError **error) {
    if (CFPreferencesSynchronize(appID, user, host)) {
        return YES;
    }

    if (error) {
        NSString *identifier = CFBridgingRelease(CFStringCreateCopy(kCFAllocatorDefault, appID));
        *error = [NSError errorWithDomain:@"cn.fkj233.watchfix.app"
                                     code:2001
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to synchronize preferences for %@", identifier ?: @"unknown domain"]}];
    }
    return NO;
}

static NSMutableDictionary *WFPairingMutablePreferencesDictionary(NSString *path, BOOL createIfMissing) {
    NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    if (!dictionary && createIfMissing) {
        dictionary = [NSMutableDictionary dictionary];
    }
    return dictionary;
}

static BOOL WFPairingWritePreferencesDictionary(NSMutableDictionary *dictionary, NSString *path, NSError **error) {
    if (!dictionary) {
        return YES;
    }

    if ([dictionary writeToFile:path atomically:YES]) {
        return YES;
    }

    if (error) {
        *error = [NSError errorWithDomain:@"cn.fkj233.watchfix.app"
                                     code:2002
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to write %@", path ?: @"preference file"]}];
    }
    return NO;
}

static BOOL WFPairingApplyNanoRegistrySupportRange(BOOL enabled, NSDictionary<NSString *, id> *configuration, NSError **error) {
    CFStringRef domain = CFSTR("com.apple.NanoRegistry");
    NSInteger minVersion = WFPairingConfigurationIntegerValue(configuration, kPairingMinKey, kDeviceSupportRangeMinCompatibilityVersion);
    NSInteger maxVersion = WFPairingConfigurationIntegerValue(configuration, kPairingMaxKey, kDeviceSupportRangeMaxCompatibilityVersion);
    NSNumber *minValue = @(minVersion);
    NSNumber *maxValue = @(maxVersion);
    NSString *chipIDsString = WFPairingStringValue(configuration[kChipIDsKey]) ?: @"";
    CFPropertyListRef chipIDsValue = enabled ? (__bridge CFPropertyListRef)chipIDsString : NULL;
    CFPropertyListRef minCompatibilityValue = enabled ? (__bridge CFPropertyListRef)minValue : NULL;
    CFPropertyListRef maxCompatibilityValue = enabled ? (__bridge CFPropertyListRef)maxValue : NULL;

    WFPairingSetPreferenceValue(domain, CFSTR("minPairingCompatibilityVersion"), minCompatibilityValue, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    WFPairingSetPreferenceValue(domain, CFSTR("maxPairingCompatibilityVersion"), maxCompatibilityValue, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    WFPairingSetPreferenceValue(domain, CFSTR("IOS_PAIRING_EOL_MIN_PAIRING_COMPATIBILITY_VERSION_CHIPIDS"), chipIDsValue, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    WFPairingSetPreferenceValue(domain, CFSTR("minPairingCompatibilityVersionWithChipID"), minCompatibilityValue, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    WFPairingSetPreferenceValue(domain, CFSTR("minPairingCompatibilityVersion"), minCompatibilityValue, kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
    WFPairingSetPreferenceValue(domain, CFSTR("maxPairingCompatibilityVersion"), maxCompatibilityValue, kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
    WFPairingSetPreferenceValue(domain, CFSTR("IOS_PAIRING_EOL_MIN_PAIRING_COMPATIBILITY_VERSION_CHIPIDS"), chipIDsValue, kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
    WFPairingSetPreferenceValue(domain, CFSTR("minPairingCompatibilityVersionWithChipID"), minCompatibilityValue, kCFPreferencesAnyUser, kCFPreferencesCurrentHost);

    if (!WFPairingSynchronizePreferences(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, error)) {
        // return NO;
        NSString *desc = error ? (*error).localizedDescription : @"unknown error";
        Log(@"Warning: Failed to synchronize NanoRegistry preferences for current user/any host: %@", desc);
        [WFPluginBridge showWarningBannerWithMessage:[NSString stringWithFormat:@"NanoRegistry sync (cu/ah): %@", desc] delay:0];
    }
    if (!WFPairingSynchronizePreferences(domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost, error)) {
        // return NO;
        NSString *desc = error ? (*error).localizedDescription : @"unknown error";
        Log(@"Warning: Failed to synchronize NanoRegistry preferences for any user/current host: %@", desc);
        [WFPluginBridge showWarningBannerWithMessage:[NSString stringWithFormat:@"NanoRegistry sync (au/ch): %@", desc] delay:1.5];
    }

    NSMutableDictionary *dictionary = WFPairingMutablePreferencesDictionary(kNanoRegistryPreferencesPath, enabled);
    if (enabled) {
        dictionary[@"minPairingCompatibilityVersion"] = minValue;
        dictionary[@"maxPairingCompatibilityVersion"] = maxValue;
        dictionary[@"IOS_PAIRING_EOL_MIN_PAIRING_COMPATIBILITY_VERSION_CHIPIDS"] = chipIDsString;
        dictionary[@"minPairingCompatibilityVersionWithChipID"] = minValue;
    } else if (dictionary) {
        [dictionary removeObjectForKey:@"minPairingCompatibilityVersion"];
        [dictionary removeObjectForKey:@"maxPairingCompatibilityVersion"];
        [dictionary removeObjectForKey:@"IOS_PAIRING_EOL_MIN_PAIRING_COMPATIBILITY_VERSION_CHIPIDS"];
        [dictionary removeObjectForKey:@"minPairingCompatibilityVersionWithChipID"];
    }

    if (!WFPairingWritePreferencesDictionary(dictionary, kNanoRegistryPreferencesPath, error)) {
        NSString *desc = error ? (*error).localizedDescription : @"unknown error";
        Log(@"Warning: Failed to write NanoRegistry preferences file: %@", desc);
        [WFPluginBridge showWarningBannerWithMessage:[NSString stringWithFormat:@"NanoRegistry write: %@", desc] delay:3.0];
    }

    return YES;
}

static BOOL WFPairingApplyPairedSyncSupportRange(BOOL enabled, NSError **error) {
    CFStringRef domain = CFSTR("com.apple.pairedsync");
    NSNumber *activityTimeout = @(kDeviceSupportRangeActivityTimeout);
    CFPropertyListRef value = enabled ? (__bridge CFPropertyListRef)activityTimeout : NULL;
    WFPairingSetPreferenceValue(domain, CFSTR("activityTimeout"), value, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!WFPairingSynchronizePreferences(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost, error)) {
        return NO;
    }

    NSMutableDictionary *dictionary = WFPairingMutablePreferencesDictionary(kPairedSyncPreferencesPath, enabled);
    if (enabled) {
        dictionary[@"activityTimeout"] = activityTimeout;
    } else if (dictionary) {
        [dictionary removeObjectForKey:@"activityTimeout"];
    }
    return WFPairingWritePreferencesDictionary(dictionary, kPairedSyncPreferencesPath, error);
}

static BOOL WFPairingApplyMobileAssetSupport(BOOL enabled, NSError **error) {
    NSString *assetPath = @"/private/var/MobileAsset/AssetsV2/com_apple_MobileAsset_NanoRegistryPairingCompatibilityIndex";
    if (enabled) {
        // move asset to (name).wfbak
        NSString *backupPath = [assetPath stringByAppendingString:@".wfbak"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:backupPath]) {
            if (![fileManager removeItemAtPath:backupPath error:error]) {
                return NO;
            }
        }
        if ([fileManager fileExistsAtPath:assetPath]) {
            if (![fileManager moveItemAtPath:assetPath toPath:backupPath error:error]) {
                return NO;
            }
        }
    } else {
        // move (name).wfbak back to (name)
        NSString *backupPath = [assetPath stringByAppendingString:@".wfbak"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:assetPath]) {
            if (![fileManager removeItemAtPath:assetPath error:error]) {
                return NO;
            }
        }
        if ([fileManager fileExistsAtPath:backupPath]) {
            if (![fileManager moveItemAtPath:backupPath toPath:assetPath error:error]) {
                return NO;
            }
        }
    }
    return YES;
}

static BOOL WFPairingApplyDeviceSupportRange(BOOL enabled, NSDictionary<NSString *, id> *configuration, NSError **error) {
    NSTimeInterval bannerDelay = 0;
    NSError *subError = nil;
    if (!WFPairingApplyNanoRegistrySupportRange(enabled, configuration, &subError)) {
        NSString *desc = subError.localizedDescription ?: @"unknown error";
        Log(@"Failed to apply NanoRegistry support range: %@", desc);
        [WFPluginBridge showWarningBannerWithMessage:[NSString stringWithFormat:@"NanoRegistry: %@", desc] delay:bannerDelay];
        bannerDelay += 1.5;
    }
    subError = nil;
    if (!WFPairingApplyPairedSyncSupportRange(enabled, &subError)) {
        NSString *desc = subError.localizedDescription ?: @"unknown error";
        Log(@"Failed to apply PairedSync support range: %@", desc);
        [WFPluginBridge showWarningBannerWithMessage:[NSString stringWithFormat:@"PairedSync: %@", desc] delay:bannerDelay];
        bannerDelay += 1.5;
    }
    subError = nil;
    if (!WFPairingApplyMobileAssetSupport(enabled, &subError)) {
        NSString *desc = subError.localizedDescription ?: @"unknown error";
        Log(@"Failed to apply MobileAsset support changes: %@", desc);
        [WFPluginBridge showWarningBannerWithMessage:[NSString stringWithFormat:@"MobileAsset: %@", desc] delay:bannerDelay];
    }
    return YES;
}

@interface WFPairingCompatibilityConfigurationViewController : UIViewController

@property (nonatomic, strong) WFPluginConfigurationContext *context;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, copy) NSDictionary<NSString *, id> *savedConfiguration;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *draftConfiguration;
@property (nonatomic, assign) BOOL isWorking;

- (instancetype)initWithContext:(WFPluginConfigurationContext *)context;

@end

@implementation WFPairingCompatibilityConfigurationViewController

- (instancetype)initWithContext:(WFPluginConfigurationContext *)context {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) {
        return nil;
    }

    _context = context;
    self.title = WFPairingConfigurationLocalized(context, @"plugin.PairingCompatibility.settings.title");
    [self reloadConfigurationDiscardingDraft:YES];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [self setupLayout];
    [self renderContent];
}

- (void)setupLayout {
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 20;
    [self.scrollView addSubview:self.contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:20],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:16],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-16],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-20],
    ]];
}

- (void)reloadConfigurationDiscardingDraft:(BOOL)discardDraft {
    self.savedConfiguration = WFPairingNormalizedConfiguration(self.context.pluginConfiguration);
    if (discardDraft || !self.draftConfiguration) {
        self.draftConfiguration = [self.savedConfiguration mutableCopy];
    } else {
        self.draftConfiguration = [WFPairingNormalizedConfiguration(self.draftConfiguration) mutableCopy];
    }
}

- (NSDictionary<NSString *, id> *)normalizedDraftConfiguration {
    return WFPairingNormalizedConfiguration(self.draftConfiguration);
}

- (BOOL)hasModifiedConfiguration {
    return ![self.normalizedDraftConfiguration isEqualToDictionary:self.savedConfiguration ?: @{}];
}

- (BOOL)isUsingDefaultConfiguration {
    return [self.normalizedDraftConfiguration isEqualToDictionary:WFPairingDefaultConfiguration()];
}

- (void)renderContent {
    if (!self.isViewLoaded || !self.contentStack) {
        return;
    }

    for (UIView *arrangedSubview in self.contentStack.arrangedSubviews) {
        [self.contentStack removeArrangedSubview:arrangedSubview];
        [arrangedSubview removeFromSuperview];
    }

    [self.contentStack addArrangedSubview:[self makeHeaderCard]];
    [self.contentStack addArrangedSubview:[self makeInstallationSection]];
    [self.contentStack addArrangedSubview:[self makeFeatureSection]];
    [self.contentStack addArrangedSubview:[self makeSettingsSection]];
    [self.contentStack addArrangedSubview:[self makeSaveSection]];
}

- (UIView *)makeHeaderCard {
    UIImage *icon = nil;
    NSString *scopeIdentifier = WFPairingStringValue(self.context.pluginManifest[@"WFPluginScopeIdentifier"]);
    if (scopeIdentifier.length > 0) {
        icon = [WFPluginBridge pluginIconForScopeIdentifier:scopeIdentifier];
    }
    UIImageView *iconView = [[UIImageView alloc] initWithImage:icon ?: [UIImage systemImageNamed:@"link.badge.plus"]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = icon ? nil : UIColor.systemBlueColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [iconView.widthAnchor constraintEqualToConstant:42].active = YES;
    [iconView.heightAnchor constraintEqualToConstant:42].active = YES;

    UILabel *titleLabel = [self makeLabelWithText:self.context.pluginTitle font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] color:UIColor.labelColor lines:0];
    UILabel *detailLabel = [self makeLabelWithText:self.context.pluginDetail font:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline] color:UIColor.secondaryLabelColor lines:0];
    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, detailLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 4;

    UIView *statusBadge = [self makeStatusBadge];
    [statusBadge setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *rowStack = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, textStack, statusBadge]];
    rowStack.axis = UILayoutConstraintAxisHorizontal;
    rowStack.alignment = UIStackViewAlignmentCenter;
    rowStack.spacing = 12;
    return [self makeCardWithArrangedSubviews:@[rowStack] spacing:12];
}

- (UIView *)makeStatusBadge {
    BOOL installed = self.context.isPluginInstalled;
    UIColor *tintColor = installed ? UIColor.systemGreenColor : UIColor.systemGrayColor;
    NSString *title = installed
        ? WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.installation.status.installed")
        : WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.installation.status.notInstalled");

    UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:installed ? @"checkmark.circle.fill" : @"minus.circle.fill"]];
    imageView.tintColor = tintColor;
    UILabel *label = [self makeLabelWithText:title font:[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1] color:tintColor lines:1];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[imageView, label]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 6;

    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.backgroundColor = [tintColor colorWithAlphaComponent:0.14];
    container.layer.cornerRadius = 999;
    [container addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:6],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-10],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-6],
    ]];
    return container;
}

- (UIView *)makeInstallationSection {
    NSString *buttonTitle = self.context.isPluginInstalled
        ? WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.installation.remove")
        : WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.installation.install");
    NSString *systemImage = self.context.isPluginInstalled ? @"trash" : @"square.and.arrow.down";
    UIColor *tintColor = self.context.isPluginInstalled ? UIColor.systemRedColor : nil;
    UIButton *button = [self makeButtonWithTitle:buttonTitle
                                     systemImage:systemImage
                                       isPrimary:!self.context.isPluginInstalled
                                       tintColor:tintColor
                                         enabled:!self.isWorking
                                          action:@selector(installationButtonTapped)];

    return [self makeSectionWithTitle:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.installation.title")
                              footer:nil
                              contents:@[[self makeCardWithArrangedSubviews:@[button] spacing:12]]];
}

- (UIView *)makeFeatureSection {
    NSMutableArray<UIView *> *contents = [NSMutableArray array];
    [contents addObject:[self makeToggleCardForKey:kModifyDeviceSupportRangeEnabledKey
                                          titleKey:@"plugin.PairingCompatibility.features.deviceSupportRange.title"
                                         detailKey:@"plugin.PairingCompatibility.features.deviceSupportRange.detail"
                                      defaultValue:YES]];
    [contents addObject:[self makeToggleCardForKey:kFrameworkHooksEnabledKey
                                          titleKey:@"plugin.PairingCompatibility.features.framework.title"
                                         detailKey:@"plugin.PairingCompatibility.features.framework.detail"
                                      defaultValue:YES]];
    [contents addObject:[self makeToggleCardForKey:kNanoRegistryHooksEnabledKey
                                          titleKey:@"plugin.PairingCompatibility.features.nanoRegistry.title"
                                         detailKey:@"plugin.PairingCompatibility.features.nanoRegistry.detail"
                                      defaultValue:YES]];
    [contents addObject:[self makeToggleCardForKey:kIDSHooksEnabledKey
                                          titleKey:@"plugin.PairingCompatibility.features.ids.title"
                                         detailKey:@"plugin.PairingCompatibility.features.ids.detail"
                                      defaultValue:YES]];
    [contents addObject:[self makeToggleCardForKey:kMockIOSVersionHooksEnabledKey
                                          titleKey:@"plugin.PairingCompatibility.features.mockIOS.title"
                                         detailKey:@"plugin.PairingCompatibility.features.mockIOS.detail"
                                      defaultValue:YES]];
    [contents addObject:[self makeToggleCardForKey:kPassKitHooksEnabledKey
                                          titleKey:@"plugin.PairingCompatibility.features.passKit.title"
                                         detailKey:@"plugin.PairingCompatibility.features.passKit.detail"
                                      defaultValue:YES]];
    [contents addObject:[self makeToggleCardForKey:kBLEHooksEnabledKey
                                          titleKey:@"plugin.PairingCompatibility.features.ble.title"
                                         detailKey:@"plugin.PairingCompatibility.features.ble.detail"
                                      defaultValue:YES]];

    return [self makeSectionWithTitle:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.features.title")
                               footer:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.features.footer")
                              contents:contents];
}

- (UIView *)makeSettingsSection {
    NSMutableArray<UIView *> *contents = [NSMutableArray array];
    [contents addObject:[self makeStepperCardForKey:kPairingMinKey
                                          titleKey:@"plugin.PairingCompatibility.settings.min"
                                           minimum:0
                                           maximum:64
                                      defaultValue:MIN_COMP]];
    NSInteger minValue = WFPairingConfigurationIntegerValue(self.draftConfiguration, kPairingMinKey, 4);
    [contents addObject:[self makeStepperCardForKey:kPairingMaxKey
                                          titleKey:@"plugin.PairingCompatibility.settings.max"
                                           minimum:minValue
                                           maximum:64
                                      defaultValue:MAX_COMP]];
    [contents addObject:[self makeStepperCardForKey:kHelloThresholdKey
                                          titleKey:@"plugin.PairingCompatibility.settings.hello"
                                           minimum:0
                                           maximum:64
                                      defaultValue:HELLO_COMP]];
    [contents addObject:[self makeStepperCardForKey:kMockIOSMajorKey
                                          titleKey:@"plugin.PairingCompatibility.settings.mockIOSMajor"
                                           minimum:14
                                           maximum:30
                                      defaultValue:OS_MAJOR]];
    [contents addObject:[self makeStepperCardForKey:kMockIOSMinorKey
                                          titleKey:@"plugin.PairingCompatibility.settings.mockIOSMinor"
                                           minimum:0
                                           maximum:20
                                      defaultValue:OS_MINOR]];
    [contents addObject:[self makeTextFieldCardForKey:kMockIOSBuildKey
                                            titleKey:@"plugin.PairingCompatibility.settings.mockIOSBuild"
                                         placeholder:OS_BUILD]];
    [contents addObject:[self makeTextFieldCardForKey:kChipIDsKey
                                            titleKey:@"plugin.PairingCompatibility.settings.chipIDs"
                                         placeholder:@""]];

    return [self makeSectionWithTitle:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.settings.title")
                               footer:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.settings.footer")
                              contents:contents];
}

- (UIView *)makeSaveSection {
    BOOL modified = self.hasModifiedConfiguration;
    NSString *statusText = modified
        ? WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.settings.status.pending")
        : WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.settings.status.saved");
    UIView *statusCard = [self makeInfoCardWithText:statusText];

    UIButton *saveButton = [self makeButtonWithTitle:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.action.save")
                                        systemImage:@"square.and.arrow.down"
                                          isPrimary:YES
                                          tintColor:nil
                                            enabled:modified && !self.isWorking
                                             action:@selector(saveButtonTapped)];
    UIButton *restoreButton = [self makeButtonWithTitle:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.action.restore")
                                           systemImage:@"arrow.uturn.backward"
                                             isPrimary:NO
                                             tintColor:nil
                                               enabled:modified && !self.isWorking
                                                action:@selector(restoreButtonTapped)];
    UIButton *defaultsButton = [self makeButtonWithTitle:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.action.defaults")
                                            systemImage:@"arrow.counterclockwise"
                                              isPrimary:NO
                                              tintColor:nil
                                                enabled:!self.isUsingDefaultConfiguration && !self.isWorking
                                                 action:@selector(defaultsButtonTapped)];
    UIView *buttonCard = [self makeCardWithArrangedSubviews:@[saveButton, restoreButton, defaultsButton] spacing:12];

    return [self makeSectionWithTitle:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.save.title")
                               footer:nil
                              contents:@[statusCard, buttonCard]];
}

- (UIView *)makeToggleCardForKey:(NSString *)key
                        titleKey:(NSString *)titleKey
                       detailKey:(NSString *)detailKey
                    defaultValue:(BOOL)defaultValue {
    UILabel *titleLabel = [self makeLabelWithText:WFPairingConfigurationLocalized(self.context, titleKey)
                                             font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]
                                            color:UIColor.labelColor
                                            lines:0];
    UILabel *detailLabel = [self makeLabelWithText:WFPairingConfigurationLocalized(self.context, detailKey)
                                             font:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]
                                            color:UIColor.secondaryLabelColor
                                            lines:0];
    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, detailLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 4;

    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    toggle.on = WFPairingConfigurationBoolValue(self.draftConfiguration, key, defaultValue);
    toggle.enabled = !self.isWorking;
    toggle.accessibilityIdentifier = key;
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *rowStack = [[UIStackView alloc] initWithArrangedSubviews:@[textStack, [UIView new], toggle]];
    rowStack.axis = UILayoutConstraintAxisHorizontal;
    rowStack.alignment = UIStackViewAlignmentCenter;
    rowStack.spacing = 12;
    return [self makeCardWithArrangedSubviews:@[rowStack] spacing:12];
}

- (UIView *)makeStepperCardForKey:(NSString *)key
                         titleKey:(NSString *)titleKey
                          minimum:(NSInteger)minimum
                          maximum:(NSInteger)maximum
                     defaultValue:(NSInteger)defaultValue {
    NSInteger value = MAX(minimum, MIN(maximum, WFPairingConfigurationIntegerValue(self.draftConfiguration, key, defaultValue)));

    UILabel *titleLabel = [self makeLabelWithText:WFPairingConfigurationLocalized(self.context, titleKey)
                                             font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]
                                            color:UIColor.labelColor
                                            lines:0];
    UILabel *valueLabel = [self makeLabelWithText:[NSString stringWithFormat:@"%ld", (long)value]
                                             font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]
                                            color:UIColor.labelColor
                                            lines:1];
    valueLabel.textAlignment = NSTextAlignmentRight;
    [valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *headerStack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, [UIView new], valueLabel]];
    headerStack.axis = UILayoutConstraintAxisHorizontal;
    headerStack.alignment = UIStackViewAlignmentFirstBaseline;

    UIStepper *stepper = [[UIStepper alloc] initWithFrame:CGRectZero];
    stepper.minimumValue = minimum;
    stepper.maximumValue = maximum;
    stepper.stepValue = 1;
    stepper.value = value;
    stepper.enabled = !self.isWorking;
    stepper.accessibilityIdentifier = key;
    [stepper addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *controlStack = [[UIStackView alloc] initWithArrangedSubviews:@[stepper, [UIView new]]];
    controlStack.axis = UILayoutConstraintAxisHorizontal;
    controlStack.alignment = UIStackViewAlignmentCenter;

    return [self makeCardWithArrangedSubviews:@[headerStack, controlStack] spacing:12];
}

- (UIView *)makeTextFieldCardForKey:(NSString *)key
                           titleKey:(NSString *)titleKey
                        placeholder:(NSString *)placeholder {
    UILabel *titleLabel = [self makeLabelWithText:WFPairingConfigurationLocalized(self.context, titleKey)
                                             font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]
                                            color:UIColor.labelColor
                                            lines:0];
    UITextField *textField = [[UITextField alloc] initWithFrame:CGRectZero];
    textField.text = WFPairingStringValue(self.draftConfiguration[key]) ?: @"";
    textField.placeholder = placeholder;
    textField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    textField.textColor = UIColor.labelColor;
    textField.borderStyle = UITextBorderStyleNone;
    textField.accessibilityIdentifier = key;
    textField.enabled = !self.isWorking;
    textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    textField.autocorrectionType = UITextAutocorrectionTypeNo;
    textField.spellCheckingType = UITextSpellCheckingTypeNo;
    [textField addTarget:self action:@selector(textFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    return [self makeCardWithArrangedSubviews:@[titleLabel, textField] spacing:8];
}

- (UILabel *)makeLabelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text ?: @"";
    label.font = font;
    label.textColor = color;
    label.numberOfLines = lines;
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

- (UIView *)makeCardWithArrangedSubviews:(NSArray<UIView *> *)arrangedSubviews spacing:(CGFloat)spacing {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:arrangedSubviews];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = spacing;

    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    container.layer.cornerRadius = 16;
    container.layer.cornerCurve = kCACornerCurveContinuous;
    [container addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-16],
    ]];
    return container;
}

- (UIView *)makeInfoCardWithText:(NSString *)text {
    UILabel *label = [self makeLabelWithText:text
                                        font:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]
                                       color:UIColor.secondaryLabelColor
                                       lines:0];
    return [self makeCardWithArrangedSubviews:@[label] spacing:12];
}

- (UIView *)makeSectionWithTitle:(NSString *)title footer:(NSString *)footer contents:(NSArray<UIView *> *)contents {
    NSMutableArray<UIView *> *arrangedSubviews = [NSMutableArray array];
    [arrangedSubviews addObject:[self makeLabelWithText:title
                                                  font:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]
                                                 color:UIColor.labelColor
                                                 lines:0]];
    [arrangedSubviews addObjectsFromArray:contents ?: @[]];
    if (footer.length > 0) {
        [arrangedSubviews addObject:[self makeLabelWithText:footer
                                                      font:[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]
                                                     color:UIColor.secondaryLabelColor
                                                     lines:0]];
    }

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:arrangedSubviews];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    return stack;
}

- (UIButton *)makeButtonWithTitle:(NSString *)title
                      systemImage:(NSString *)systemImage
                        isPrimary:(BOOL)isPrimary
                        tintColor:(UIColor *)tintColor
                          enabled:(BOOL)enabled
                           action:(SEL)action {
    UIButtonConfiguration *configuration = isPrimary ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
    configuration.title = title;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    configuration.buttonSize = UIButtonConfigurationSizeLarge;
    configuration.imagePadding = 8;
    configuration.showsActivityIndicator = self.isWorking;
    if (systemImage.length > 0) {
        configuration.image = [UIImage systemImageNamed:systemImage];
    }

    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    button.enabled = enabled && !self.isWorking;
    if (tintColor) {
        button.tintColor = tintColor;
    }
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)textFieldChanged:(UITextField *)sender {
    NSString *key = sender.accessibilityIdentifier;
    if (key.length == 0) {
        return;
    }
    self.draftConfiguration[key] = sender.text ?: @"";
}

- (void)toggleChanged:(UISwitch *)sender {
    NSString *key = sender.accessibilityIdentifier;
    if (key.length == 0) {
        return;
    }
    self.draftConfiguration[key] = @(sender.isOn);
    self.draftConfiguration = [WFPairingNormalizedConfiguration(self.draftConfiguration) mutableCopy];
    [self renderContent];
}

- (void)stepperChanged:(UIStepper *)sender {
    NSString *key = sender.accessibilityIdentifier;
    if (key.length == 0) {
        return;
    }
    self.draftConfiguration[key] = @((NSInteger)llround(sender.value));
    self.draftConfiguration = [WFPairingNormalizedConfiguration(self.draftConfiguration) mutableCopy];
    [self renderContent];
}

- (void)installationButtonTapped {
    [self.view endEditing:YES];
    if (self.context.isPluginInstalled) {
        [self removePlugin];
    } else {
        [self installPlugin];
    }
}

- (void)installPlugin {
    NSDictionary<NSString *, id> *configuration = self.normalizedDraftConfiguration;
    BOOL shouldSave = self.hasModifiedConfiguration;
    WFPluginConfigurationContext *context = self.context;
    [self performOperationWithSuccessMessage:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.installation.success.installed")
                                   operation:^BOOL(NSError **error) {
        if (shouldSave && ![context saveConfiguration:configuration error:error]) {
            return NO;
        }
        return [context installPlugin:error];
    }];
}

- (void)removePlugin {
    WFPluginConfigurationContext *context = self.context;
    [self performOperationWithSuccessMessage:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.installation.success.removed")
                                   operation:^BOOL(NSError **error) {
        return [context removePlugin:error];
    }];
}

- (void)saveButtonTapped {
    [self.view endEditing:YES];
    NSDictionary<NSString *, id> *configuration = self.normalizedDraftConfiguration;
    WFPluginConfigurationContext *context = self.context;
    [self performOperationWithSuccessMessage:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.settings.success.saved")
                                   operation:^BOOL(NSError **error) {
        return [context saveConfiguration:configuration error:error];
    }];
}

- (void)restoreButtonTapped {
    self.draftConfiguration = [self.savedConfiguration mutableCopy];
    [self renderContent];
}

- (void)defaultsButtonTapped {
    self.draftConfiguration = [WFPairingDefaultConfiguration() mutableCopy];
    [self renderContent];
}

- (void)performOperationWithSuccessMessage:(NSString *)successMessage operation:(WFPairingOperationBlock)operation {
    if (self.isWorking || !operation) {
        return;
    }

    self.isWorking = YES;
    [self renderContent];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *operationError = nil;
        BOOL success = operation(&operationError);

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            strongSelf.isWorking = NO;
            if (success) {
                [strongSelf reloadConfigurationDiscardingDraft:YES];
                [strongSelf showAlertWithTitle:WFPairingConfigurationLocalized(strongSelf.context, @"plugin.PairingCompatibility.alert.success")
                                       message:successMessage];
            } else {
                [strongSelf showAlertWithTitle:WFPairingConfigurationLocalized(strongSelf.context, @"plugin.PairingCompatibility.alert.error")
                                       message:operationError.localizedDescription ?: WFPairingConfigurationLocalized(strongSelf.context, @"plugin.PairingCompatibility.alert.error.unknown")];
            }
            [strongSelf renderContent];
        });
    });
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WFPairingConfigurationLocalized(self.context, @"plugin.PairingCompatibility.action.ok")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@interface PairingCompatibilityPluginConfiguration : NSObject <WFPluginConfigurationProvider>
@end

@implementation PairingCompatibilityPluginConfiguration

+ (UIViewController *)configurationViewControllerWithContext:(WFPluginConfigurationContext *)context {
    return [[WFPairingCompatibilityConfigurationViewController alloc] initWithContext:context];
}

+ (NSDictionary<NSString *,id> *)normalizedConfiguration:(NSDictionary<NSString *,id> *)configuration context:(WFPluginConfigurationContext *)context {
    return WFPairingNormalizedConfiguration(configuration);
}

+ (BOOL)installPluginWithContext:(WFPluginConfigurationContext *)context error:(NSError * _Nullable __autoreleasing *)error {
    if (![context installUsingDefaultImplementation:error]) {
        return NO;
    }

    BOOL shouldModifyDeviceSupportRange = WFPairingConfigurationBoolValue(context.pluginConfiguration, kModifyDeviceSupportRangeEnabledKey, YES);
    if (!shouldModifyDeviceSupportRange) {
        return YES;
    }

    NSError *applyError = nil;
    if (WFPairingApplyDeviceSupportRange(YES, context.pluginConfiguration, &applyError)) {
        return YES;
    }

    [context removeUsingDefaultImplementation:nil];
    if (error) {
        *error = applyError;
    }
    return NO;
}

+ (BOOL)didSaveConfigurationWithContext:(WFPluginConfigurationContext *)context error:(NSError * _Nullable __autoreleasing *)error {
    if (!context.pluginInstalled) {
        return YES;
    }

    BOOL shouldModifyDeviceSupportRange = WFPairingConfigurationBoolValue(context.pluginConfiguration, kModifyDeviceSupportRangeEnabledKey, YES);
    if (!shouldModifyDeviceSupportRange) {
        return WFPairingApplyDeviceSupportRange(NO, nil, error);
    }

    if (![context installUsingDefaultImplementation:error]) {
        return NO;
    }
    return WFPairingApplyDeviceSupportRange(YES, context.pluginConfiguration, error);
}

+ (BOOL)removePluginWithContext:(WFPluginConfigurationContext *)context error:(NSError * _Nullable __autoreleasing *)error {
    if (!WFPairingApplyDeviceSupportRange(NO, nil, error)) {
        return NO;
    }
    return [context removeUsingDefaultImplementation:error];
}

@end
