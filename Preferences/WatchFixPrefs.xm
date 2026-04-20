#import <Preferences/Preferences.h>
#import <UIKit/UIKit.h>

typedef NS_OPTIONS(NSUInteger, PSSystemPolicyOptions) {
	PSSystemPolicyOptionsCamera = 1 << 13
};

@interface WFPreferencesController : PSListController
@property (nonatomic, strong) PSSystemPolicyForApp *policy;
@property (nonatomic, copy) NSDictionary *infoDictionary;
@end

@implementation WFPreferencesController

- (NSString *)infoString:(NSString *)key {
    if (!_infoDictionary) {
        NSBundle *mainBundle = [NSBundle bundleForClass:[self class]];
        _infoDictionary = mainBundle.infoDictionary;
    }
    id value = _infoDictionary[key];
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : nil;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"WatchFixRootSpecifiers" target:self] mutableCopy];

        if (!_policy) {
            NSBundle *mainBundle = [NSBundle bundleForClass:[self class]];
            NSString *bundleID = [[mainBundle bundleIdentifier] stringByDeletingPathExtension];
            _policy = [[PSSystemPolicyForApp alloc] initWithBundleIdentifier:bundleID];
        }


        NSArray<PSSpecifier *> *policySpecifiers = [_policy specifiersForPolicyOptions:PSSystemPolicyOptionsCamera force:YES];
        if (policySpecifiers && policySpecifiers.count > 0) {
            NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, policySpecifiers.count)];
            [_specifiers insertObjects:policySpecifiers atIndexes:indexes];
        }
    }

    return _specifiers;
}

- (NSString *)watchFixReleaseName:(PSSpecifier *)specifier {
    return [self infoString:@"WFBuildType"] ?: @"Unknown";
}

- (NSString *)watchFixVersionNumber:(PSSpecifier *)specifier {
    return [self infoString:@"CFBundleShortVersionString"] ?: @"Unknown";
}

- (NSString *)watchFixBuildNumber:(PSSpecifier *)specifier {
    return [self infoString:@"CFBundleVersion"] ?: @"Unknown";
}

- (NSString *)watchFixBuildType:(PSSpecifier *)specifier {
    NSString *configuration = [self infoString:@"WFConfiguration"] ?: @"Unknown";
    NSString *variant = [self infoString:@"WFVariant"] ?: @"Unknown";

    // Split configuration by "-"
    NSString *firstConfiguration = [[configuration componentsSeparatedByString:@"-"] firstObject] ?: configuration;

    // Capitalize first letter
    NSString *capitalizedConfiguration = [firstConfiguration capitalizedString];
    NSString *capitalizedVariant = [variant capitalizedString];

    return [NSString stringWithFormat:@"%@ (%@)", capitalizedConfiguration, capitalizedVariant];
}

- (void)openGithub:(PSSpecifier *)specifier {
    [self openExternalURLString:[self infoString:@"WFGitHubURL"]];
}

- (void)openPatreon:(PSSpecifier *)specifier {
    [self openExternalURLString:[self infoString:@"WFPatreonURL"]];
}

- (void)openAfdian:(PSSpecifier *)specifier {
    [self openExternalURLString:[self infoString:@"WFAfdianURL"]];
}

- (void)openExternalURLString:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || urlString.length == 0) {
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        return;
    }

    UIApplication *application = UIApplication.sharedApplication;
    [application openURL:url options:@{} completionHandler:nil];
}

@end
