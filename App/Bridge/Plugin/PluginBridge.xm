#import "PluginBridge.h"
#import "../Internal/BridgeInternal.h"
#import "Logging.h"
#import "PluginConfig.h"

#import <UIKit/UIKit.h>

#include <errno.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <roothide.h>

static NSString *const kStateRelativePath = @"/var/mobile/Library/Preferences/cn.fkj233.watchfix.plist";
static NSString *const kPluginStatesKey = @"PluginStates";
static NSString *const kPluginConfigurationsKey = @"PluginConfigurations";
static NSString *const kPairingConfigurationKey = @"PairingCompatibility";
static NSString *const kPluginRestartExecutablesKey = @"WFPluginRestartExecutables";
static NSString *const kPluginManifestKey = @"WFPluginManifest";
static NSString *const kPluginHasInstallableContentKey = @"WFPluginHasInstallableContent";
static NSString *const kPluginConfigurationClassKey = @"WFPluginConfigurationClass";
static NSString *const kInstallArtifactsKey = @"WFInstallArtifacts";
static NSString *const kPluginPrefix = @"WatchFix_";
static NSString *const kDynamicLibrariesRelativePath = @"/Library/MobileSubstrate/DynamicLibraries";
static NSString *const kPluginVersionKey = @"WFPluginVersion";
static NSString *const kPluginBuildVersionKey = @"WFPluginBuildVersion";

#define WFBridgeLog(fmt, ...) Log((@"[WatchFixBridge] " fmt), ##__VA_ARGS__)

static NSDictionary<NSString *, id> *DirectPluginConfigurationNamed(NSString *pluginName);
static BOOL SavePluginConfigurationNamed(NSString *pluginName, NSDictionary<NSString *, id> *configuration, NSError **error);
static BOOL ApplyDefaultPluginNamed(NSString *pluginName, BOOL enabled, NSError **error);
static NSDictionary<NSString *, NSNumber *> *DirectInstalledPluginStates(void);
static WFPluginConfigurationContext *PluginConfigurationContextForPluginNamed(NSString *pluginName, NSDictionary **pluginInfoOut, NSError **error);
static Class PluginConfigurationProviderClass(NSString *pluginName, NSDictionary *pluginInfo);

NSNotificationName const WFPluginBridgeDidChangeNotification = @"WFPluginBridgeDidChangeNotification";

static void PostPluginBridgeDidChangeNotification(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:WFPluginBridgeDidChangeNotification object:nil];
}

static BOOL ProviderClassImplementsConfigurationInterface(NSString *pluginName, NSDictionary *pluginInfo) {
    Class providerClass = PluginConfigurationProviderClass(pluginName, pluginInfo);
    if (!providerClass) {
        return NO;
    }

    SEL customSelector = @selector(configurationViewControllerWithContext:);
    if ([providerClass respondsToSelector:customSelector]) {
        return YES;
    }

    SEL pageSelector = @selector(configurationPageWithContext:);
    if (![providerClass respondsToSelector:pageSelector]) {
        return NO;
    }

    WFPluginConfigurationContext *context = PluginConfigurationContextForPluginNamed(pluginName, nil, nil);
    if (!context) {
        return NO;
    }
    typedef NSDictionary<NSString *, id> *(*PageIMP)(id, SEL, WFPluginConfigurationContext *);
    PageIMP implementation = (PageIMP)[providerClass methodForSelector:pageSelector];
    NSDictionary *page = implementation(providerClass, pageSelector, context);
    if (![page isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    id sectionsValue = page[@"sections"];
    if ([sectionsValue isKindOfClass:[NSArray class]]) {
        return [(NSArray *)sectionsValue count] > 0;
    }

    return page.count > 0;
}

FOUNDATION_EXPORT NSString *RBSRequestErrorDomain;

extern "C" char **environ;
extern "C" int posix_spawnattr_set_persona_np(const posix_spawnattr_t *attr, uid_t persona, uint32_t flags);
extern "C" int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *attr, uid_t uid);
extern "C" int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *attr, gid_t gid);

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1

@interface VMUProcInfo : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) int pid;
@end

@interface VMUProcList : NSObject
- (NSArray<VMUProcInfo *> *)allProcInfos;
@end

@interface RBSProcessIdentifier : NSObject
+ (instancetype)identifierWithPid:(int)pid;
@end

@interface RBSProcessPredicate : NSObject
+ (instancetype)predicateMatchingIdentifier:(RBSProcessIdentifier *)identifier;
@end

@interface RBSTerminateContext : NSObject
+ (instancetype)defaultContextWithExplanation:(NSString *)explanation;
@end

@interface RBSTerminateRequest : NSObject
- (instancetype)initWithPredicate:(RBSProcessPredicate *)predicate context:(RBSTerminateContext *)context;
- (BOOL)execute:(NSError **)error;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier
                                               format:(int)format
                                                scale:(CGFloat)scale;
@end

static uid_t const kRootPersonaID = 99;

static NSString *JBRootPath(NSString *path) {
    const char *resolved = jbroot(path.fileSystemRepresentation);
    if (resolved) {
        NSString *stringValue = [NSString stringWithUTF8String:resolved];
        if (stringValue.length > 0) {
            return stringValue;
        }
    }
    return path;
}

static NSString *StringOrNil(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSNumber *NumberOrNil(id value) {
    return [value isKindOfClass:[NSNumber class]] ? value : NumberFromObject(value);
}

static NSArray<NSString *> *StatePathCandidates(void) {
    NSString *jbrootPath = JBRootPath(kStateRelativePath);
    if ([jbrootPath isEqualToString:kStateRelativePath]) {
        return @[kStateRelativePath];
    }
    return @[kStateRelativePath, jbrootPath];
}

static NSString *StatePathForWrite(void) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *candidate in StatePathCandidates()) {
        if ([fileManager fileExistsAtPath:candidate]) {
            return candidate;
        }
    }
    return JBRootPath(kStateRelativePath);
}

static NSMutableDictionary *MutableStateDictionary(void) {
    for (NSString *candidate in StatePathCandidates()) {
        NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:candidate];
        if ([stored isKindOfClass:[NSDictionary class]]) {
            return [stored mutableCopy];
        }
    }
    return [NSMutableDictionary dictionary];
}

static BOOL WriteStateDictionary(NSDictionary *state, NSError **error) {
    NSString *statePath = StatePathForWrite();
    NSString *directoryPath = [statePath stringByDeletingLastPathComponent];
    NSError *fileError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:&fileError]) {
        if (error) {
            *error = BridgeError(30, fileError.localizedDescription ?: @"Unable to create WatchFix state directory");
        }
        return NO;
    }

    if ([state writeToFile:statePath atomically:YES]) {
        return YES;
    }

    if (error) {
        *error = BridgeError(31, @"Unable to write WatchFix state plist");
    }
    return NO;
}

static NSDictionary *DirectStateDictionary(void) {
    for (NSString *candidate in StatePathCandidates()) {
        NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:candidate];
        if ([stored isKindOfClass:[NSDictionary class]]) {
            return stored;
        }
    }
    return @{};
}

static id DictionaryValueForKey(NSDictionary *dictionary, NSString *key) {
    if (![dictionary isKindOfClass:[NSDictionary class]] || key.length == 0) {
        return nil;
    }

    id directValue = dictionary[key];
    if (directValue) {
        return directValue;
    }

    for (id candidateKey in dictionary) {
        if (![candidateKey isKindOfClass:[NSString class]]) {
            continue;
        }
        if ([[(NSString *)candidateKey lowercaseString] isEqualToString:key.lowercaseString]) {
            return dictionary[candidateKey];
        }
    }

    return nil;
}

static NSDictionary *PluginManifestDictionary(NSDictionary *pluginInfo) {
    NSDictionary *manifest = [pluginInfo[kPluginManifestKey] isKindOfClass:[NSDictionary class]] ? pluginInfo[kPluginManifestKey] : nil;
    return manifest ?: @{};
}

static BOOL PluginHasInstallableContent(NSDictionary *pluginInfo) {
    NSDictionary *manifest = PluginManifestDictionary(pluginInfo);
    NSNumber *value = NumberOrNil(manifest[kPluginHasInstallableContentKey]);
    return value ? value.boolValue : YES;
}

static NSURL *PluginBundlesURL(void) {
    NSURL *pluginsURL = [NSBundle mainBundle].builtInPlugInsURL;
    if (pluginsURL) {
        return pluginsURL;
    }
    return [[NSBundle mainBundle].bundleURL URLByAppendingPathComponent:@"PlugIns" isDirectory:YES];
}

static NSArray<NSURL *> *PluginBundleURLs(void) {
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:PluginBundlesURL() includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableArray<NSURL *> *bundles = [NSMutableArray array];
    for (NSURL *url in contents ?: @[]) {
        if ([[url.pathExtension lowercaseString] isEqualToString:@"wffix"]) {
            [bundles addObject:url];
        }
    }
    return [bundles sortedArrayUsingComparator:^NSComparisonResult(NSURL *lhs, NSURL *rhs) {
        return [lhs.lastPathComponent localizedCaseInsensitiveCompare:rhs.lastPathComponent];
    }];
}

static NSURL *PluginBundleURLNamed(NSString *pluginName) {
    for (NSURL *bundleURL in PluginBundleURLs()) {
        if ([[[bundleURL.lastPathComponent stringByDeletingPathExtension] lowercaseString] isEqualToString:pluginName.lowercaseString]) {
            return bundleURL;
        }
    }
    return nil;
}

static NSDictionary *PluginInfoForURL(NSURL *bundleURL) {
    return [NSDictionary dictionaryWithContentsOfURL:[bundleURL URLByAppendingPathComponent:@"Info.plist"]];
}

static NSBundle *PluginBundleNamed(NSString *pluginName) {
    NSURL *bundleURL = PluginBundleURLNamed(pluginName);
    if (!bundleURL) {
        return nil;
    }
    return [NSBundle bundleWithURL:bundleURL];
}

static NSString *PluginLocalizationKey(NSString *pluginName, NSString *suffix) {
    if (pluginName.length == 0 || suffix.length == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"plugin.%@.%@", pluginName, suffix];
}

static NSString *LocalizedPluginStringNamed(NSString *pluginName, NSString *key, NSString *fallback) {
    if (key.length == 0) {
        return fallback ?: @"";
    }

    NSBundle *pluginBundle = PluginBundleNamed(pluginName);
    NSString *localized = [pluginBundle localizedStringForKey:key value:nil table:nil];
    if (localized.length > 0 && ![localized isEqualToString:key]) {
        return localized;
    }

    NSString *englishLocalizationPath = [pluginBundle pathForResource:@"en" ofType:@"lproj"];
    if (englishLocalizationPath.length > 0) {
        NSBundle *englishBundle = [NSBundle bundleWithPath:englishLocalizationPath];
        localized = [englishBundle localizedStringForKey:key value:nil table:nil];
        if (localized.length > 0 && ![localized isEqualToString:key]) {
            return localized;
        }
    }

    return fallback ?: key;
}

@interface WFPluginConfigurationContext ()

@property (nonatomic, readwrite, copy) NSString *pluginIdentifier;
@property (nonatomic, readwrite, copy) NSString *pluginTitle;
@property (nonatomic, readwrite, copy) NSString *pluginDetail;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, id> *pluginManifest;
@property (nonatomic, readwrite, assign, getter=isPluginInstalled) BOOL pluginInstalled;

- (instancetype)initWithPluginIdentifier:(NSString *)pluginIdentifier pluginInfo:(NSDictionary *)pluginInfo;

@end

@implementation WFPluginConfigurationContext

- (instancetype)initWithPluginIdentifier:(NSString *)pluginIdentifier pluginInfo:(NSDictionary *)pluginInfo {
    self = [super init];
    if (!self) {
        return nil;
    }

    NSDictionary *manifest = PluginManifestDictionary(pluginInfo);
    _pluginIdentifier = [pluginIdentifier copy] ?: @"";
    NSString *titleFallback = StringOrNil(manifest[@"WFPluginName"]) ?: _pluginIdentifier;
    NSString *detailFallback = StringOrNil(manifest[@"WFPluginDescription"]) ?: @"";
    _pluginTitle = [LocalizedPluginStringNamed(_pluginIdentifier, PluginLocalizationKey(_pluginIdentifier, @"title"), titleFallback) copy];
    _pluginDetail = [LocalizedPluginStringNamed(_pluginIdentifier, PluginLocalizationKey(_pluginIdentifier, @"detail"), detailFallback) copy];
    _pluginManifest = [manifest copy] ?: @{};
    _pluginInstalled = [DirectInstalledPluginStates()[_pluginIdentifier] boolValue];
    return self;
}

- (NSDictionary<NSString *,id> *)pluginConfiguration {
    return DirectPluginConfigurationNamed(self.pluginIdentifier);
}

- (NSNumber *)numberValueForConfigurationKey:(NSString *)key {
    if (key.length == 0) {
        return nil;
    }
    return NumberOrNil(self.pluginConfiguration[key]);
}

- (NSString *)localizedStringForKey:(NSString *)key fallback:(NSString *)fallback {
    return LocalizedPluginStringNamed(self.pluginIdentifier, key, fallback);
}

- (BOOL)saveConfiguration:(NSDictionary<NSString *,id> *)configuration error:(NSError *__autoreleasing  _Nullable *)error {
    return [WFPluginBridge saveConfiguration:configuration ?: @{} forPluginNamed:self.pluginIdentifier error:error];
}

- (BOOL)installPlugin:(NSError *__autoreleasing  _Nullable *)error {
    BOOL installed = [WFPluginBridge installPluginNamed:self.pluginIdentifier error:error];
    if (installed) {
        self.pluginInstalled = YES;
    }
    return installed;
}

- (BOOL)removePlugin:(NSError *__autoreleasing  _Nullable *)error {
    BOOL removed = [WFPluginBridge removePluginNamed:self.pluginIdentifier error:error];
    if (removed) {
        self.pluginInstalled = NO;
    }
    return removed;
}

- (BOOL)installUsingDefaultImplementation:(NSError *__autoreleasing  _Nullable *)error {
    BOOL installed = ApplyDefaultPluginNamed(self.pluginIdentifier, YES, error);
    if (installed) {
        self.pluginInstalled = YES;
    }
    return installed;
}

- (BOOL)removeUsingDefaultImplementation:(NSError *__autoreleasing  _Nullable *)error {
    BOOL removed = ApplyDefaultPluginNamed(self.pluginIdentifier, NO, error);
    if (removed) {
        self.pluginInstalled = NO;
    }
    return removed;
}

@end

static WFPluginConfigurationContext *PluginConfigurationContextForPluginNamed(NSString *pluginName, NSDictionary **pluginInfoOut, NSError **error) {
    if (pluginName.length == 0) {
        if (error) {
            *error = BridgeError(42, @"Missing plugin name");
        }
        return nil;
    }

    NSURL *bundleURL = PluginBundleURLNamed(pluginName);
    NSDictionary *pluginInfo = bundleURL ? PluginInfoForURL(bundleURL) : nil;
    if (!bundleURL || !pluginInfo) {
        if (error) {
            *error = BridgeError(38, [NSString stringWithFormat:@"Missing packaged plugin '%@'", pluginName ?: @""]);
        }
        return nil;
    }

    if (pluginInfoOut) {
        *pluginInfoOut = pluginInfo;
    }
    return [[WFPluginConfigurationContext alloc] initWithPluginIdentifier:pluginName pluginInfo:pluginInfo];
}

static Class PluginConfigurationProviderClass(NSString *pluginName, NSDictionary *pluginInfo) {
    NSDictionary *manifest = PluginManifestDictionary(pluginInfo);
    NSString *className = StringOrNil(manifest[kPluginConfigurationClassKey]);
    if (className.length == 0) {
        return Nil;
    }

    Class providerClass = NSClassFromString(className);
    if (!providerClass) {
        WFBridgeLog(@"Plugin %@ declares configuration class %@ but it is not registered", pluginName ?: @"", className);
        return Nil;
    }

    return providerClass;
}

static NSString *InstalledTargetName(NSString *destination, NSString *target) {
    if ([destination isEqualToString:kDynamicLibrariesRelativePath] && ![target hasPrefix:kPluginPrefix]) {
        return [kPluginPrefix stringByAppendingString:target];
    }
    return target;
}

static NSDictionary *DynamicLibraryArtifact(NSDictionary *pluginInfo) {
    NSArray<NSDictionary *> *artifacts = [pluginInfo[kInstallArtifactsKey] isKindOfClass:[NSArray class]] ? pluginInfo[kInstallArtifactsKey] : nil;
    for (NSDictionary *artifact in artifacts ?: @[]) {
        NSString *target = StringOrNil(DictionaryValueForKey(artifact, @"target"));
        NSString *destination = StringOrNil(DictionaryValueForKey(artifact, @"destination"));
        if (target.length == 0 || destination.length == 0) {
            continue;
        }
        if ([destination isEqualToString:kDynamicLibrariesRelativePath] && [target.pathExtension.lowercaseString isEqualToString:@"dylib"]) {
            return artifact;
        }
    }
    return nil;
}

static BOOL PluginRequiresGeneratedFilterPlist(NSDictionary *pluginInfo) {
    return DynamicLibraryArtifact(pluginInfo) != nil;
}

static NSURL *GeneratedFilterDestinationURLForPluginNamed(NSString *pluginName) {
    NSString *targetName = InstalledTargetName(kDynamicLibrariesRelativePath, [pluginName stringByAppendingPathExtension:@"plist"]);
    NSURL *destinationRootURL = [NSURL fileURLWithPath:JBRootPath(kDynamicLibrariesRelativePath) isDirectory:YES];
    return [destinationRootURL URLByAppendingPathComponent:targetName];
}

static BOOL CopyItem(NSURL *sourceURL, NSURL *destinationURL, NSString *type, NSNumber *modeNumber, NSError **error);

static NSDictionary *GeneratedFilterPayload(NSDictionary *pluginInfo) {
    NSDictionary *manifest = PluginManifestDictionary(pluginInfo);
    NSDictionary *injectionTargets = [manifest[@"WFPluginInjectionTargets"] isKindOfClass:[NSDictionary class]] ? manifest[@"WFPluginInjectionTargets"] : @{};
    NSArray *bundleTargets = [injectionTargets[@"Bundles"] isKindOfClass:[NSArray class]] ? injectionTargets[@"Bundles"] : @[];
    NSArray *executableTargets = [injectionTargets[@"Executables"] isKindOfClass:[NSArray class]] ? injectionTargets[@"Executables"] : @[];

    NSMutableOrderedSet<NSString *> *bundleSet = [NSMutableOrderedSet orderedSet];
    for (id value in bundleTargets) {
        NSString *stringValue = StringOrNil(value);
        if (stringValue.length > 0) {
            [bundleSet addObject:stringValue];
        }
    }

    NSMutableOrderedSet<NSString *> *executableSet = [NSMutableOrderedSet orderedSet];
    for (id value in executableTargets) {
        NSString *stringValue = StringOrNil(value);
        if (stringValue.length > 0) {
            [executableSet addObject:stringValue];
        }
    }

    NSMutableDictionary *filter = [NSMutableDictionary dictionary];
    if (bundleSet.count > 0) {
        filter[@"Bundles"] = bundleSet.array;
    }
    if (executableSet.count > 0) {
        filter[@"Executables"] = executableSet.array;
    }
    if (filter.count == 0) {
        return @{};
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObject:filter forKey:@"Filter"];
    NSString *pluginVersion = StringOrNil(pluginInfo[kPluginVersionKey]);
    if (pluginVersion.length > 0) {
        payload[kPluginVersionKey] = pluginVersion;
    }
    NSString *pluginBuildVersion = StringOrNil(pluginInfo[kPluginBuildVersionKey]);
    if (pluginBuildVersion.length > 0) {
        payload[kPluginBuildVersionKey] = pluginBuildVersion;
    }
    return payload;
}

static NSString *CommandString(NSString *launchPath, NSArray<NSString *> *arguments) {
    NSMutableArray<NSString *> *components = [NSMutableArray array];
    if (launchPath.length > 0) {
        [components addObject:launchPath];
    }
    for (NSString *argument in arguments ?: @[]) {
        if (argument.length > 0) {
            [components addObject:argument];
        }
    }
    return [components componentsJoinedByString:@" "];
}

static BOOL RunRootCommand(NSString *launchPath, NSArray<NSString *> *arguments, NSInteger errorCode, NSString *fallbackDescription, NSError **error) {
    if (launchPath.length == 0) {
        if (error) {
            *error = BridgeError(errorCode, fallbackDescription ?: @"Unable to run root command");
        }
        return NO;
    }

    NSString *resolvedLaunchPath = JBRootPath(launchPath);
    if (resolvedLaunchPath.length == 0) {
        resolvedLaunchPath = launchPath;
    }

    NSString *command = CommandString(resolvedLaunchPath, arguments);
    posix_spawnattr_t attributes = NULL;
    int attributeStatus = posix_spawnattr_init(&attributes);
    if (attributeStatus != 0) {
        if (error) {
            *error = BridgeError(errorCode, [NSString stringWithFormat:@"%@ (%@): %s", fallbackDescription ?: @"Unable to configure root command", command, strerror(attributeStatus)]);
        }
        return NO;
    }

    int personaStatus = posix_spawnattr_set_persona_np(&attributes, kRootPersonaID, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    if (personaStatus == 0) {
        personaStatus = posix_spawnattr_set_persona_uid_np(&attributes, 0);
    }
    if (personaStatus == 0) {
        personaStatus = posix_spawnattr_set_persona_gid_np(&attributes, 0);
    }
    if (personaStatus != 0) {
        posix_spawnattr_destroy(&attributes);
        if (error) {
            *error = BridgeError(errorCode, [NSString stringWithFormat:@"%@ (%@): %s", fallbackDescription ?: @"Unable to configure root command", command, strerror(personaStatus)]);
        }
        return NO;
    }

    size_t argumentCount = arguments.count + 2;
    char **argv = (char **)calloc(argumentCount, sizeof(char *));
    if (!argv) {
        posix_spawnattr_destroy(&attributes);
        if (error) {
            *error = BridgeError(errorCode, [NSString stringWithFormat:@"%@ (%@): out of memory", fallbackDescription ?: @"Unable to run root command", command]);
        }
        return NO;
    }

    argv[0] = (char *)resolvedLaunchPath.UTF8String;
    for (NSUInteger index = 0; index < arguments.count; index++) {
        argv[index + 1] = (char *)[(NSString *)arguments[index] UTF8String];
    }
    argv[argumentCount - 1] = NULL;

    pid_t pid = 0;
    int spawnStatus = posix_spawn(&pid, resolvedLaunchPath.fileSystemRepresentation, NULL, &attributes, argv, environ);
    free(argv);
    posix_spawnattr_destroy(&attributes);
    if (spawnStatus != 0) {
        if (error) {
            *error = BridgeError(errorCode, [NSString stringWithFormat:@"%@ (%@): %s", fallbackDescription ?: @"Unable to run root command", command, strerror(spawnStatus)]);
        }
        WFBridgeLog(@"Failed to spawn root command %@, status=%d", command, spawnStatus);
        return NO;
    }

    int waitStatus = 0;
    pid_t waitResult = waitpid(pid, &waitStatus, 0);
    if (waitResult != pid) {
        int waitError = errno;
        if (error) {
            *error = BridgeError(errorCode, [NSString stringWithFormat:@"%@ (%@): %s", fallbackDescription ?: @"Unable to wait for root command", command, strerror(waitError)]);
        }
        WFBridgeLog(@"waitpid failed for root command %@, result=%d errno=%d", command, waitResult, waitError);
        return NO;
    }

    if (!WIFEXITED(waitStatus) || WEXITSTATUS(waitStatus) != 0) {
        NSString *statusDescription = @"terminated unexpectedly";
        if (WIFSIGNALED(waitStatus)) {
            statusDescription = [NSString stringWithFormat:@"terminated by signal %d", WTERMSIG(waitStatus)];
        } else if (WIFEXITED(waitStatus)) {
            statusDescription = [NSString stringWithFormat:@"exit status %d", WEXITSTATUS(waitStatus)];
        }
        if (error) {
            *error = BridgeError(errorCode, [NSString stringWithFormat:@"%@ (%@): %@", fallbackDescription ?: @"Root command failed", command, statusDescription]);
        }
        WFBridgeLog(@"Root command failed %@, %@", command, statusDescription);
        return NO;
    }

    return YES;
}

static BOOL RemoveItemAsRoot(NSURL *url, NSInteger errorCode, NSString *fallbackDescription, NSError **error) {
    NSString *path = url.path;
    if (path.length == 0) {
        return YES;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return YES;
    }
    return RunRootCommand(@"/bin/rm", @[@"-rf", path], errorCode, fallbackDescription, error);
}

static BOOL EnsureDirectoryAtURL(NSURL *url, NSError **error) {
    NSString *path = url.path;
    if (path.length == 0) {
        return YES;
    }
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
        if (isDirectory) {
            return YES;
        }
        *error = BridgeError(32, [NSString stringWithFormat:@"Expected directory at path '%@' but found a file", path]);
        return NO;
    }
    return RunRootCommand(@"/bin/mkdir", @[@"-p", path], 32, @"Unable to create directory", error);
}

static BOOL WriteGeneratedFilterPlist(NSURL *destinationURL, NSDictionary *pluginInfo, NSError **error) {
    NSDictionary *payload = GeneratedFilterPayload(pluginInfo);
    if (payload.count == 0) {
        if (error) {
            *error = BridgeError(33, @"Manifest does not describe any bundle or executable targets");
        }
        return NO;
    }

    NSError *plistError = nil;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:payload format:NSPropertyListXMLFormat_v1_0 options:0 error:&plistError];
    if (!plistData) {
        if (error) {
            *error = BridgeError(34, plistError.localizedDescription ?: @"Unable to encode generated filter plist");
        }
        return NO;
    }

    NSString *temporaryDirectory = NSTemporaryDirectory();
    if (temporaryDirectory.length == 0) {
        if (error) {
            *error = BridgeError(35, @"Unable to determine temporary directory for generated filter plist");
        }
        return NO;
    }

    NSURL *temporaryURL = [NSURL fileURLWithPath:[temporaryDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"WatchFix-%@.plist", NSUUID.UUID.UUIDString]]];
    if (![plistData writeToURL:temporaryURL options:NSDataWritingAtomic error:&plistError]) {
        if (error) {
            *error = BridgeError(35, plistError.localizedDescription ?: @"Unable to write temporary generated filter plist");
        }
        return NO;
    }

    BOOL copied = CopyItem(temporaryURL, destinationURL, @"file", @0644, error);
    [[NSFileManager defaultManager] removeItemAtURL:temporaryURL error:nil];
    return copied;
}

static NSURL *InstalledArtifactURL(NSDictionary *artifact) {
    NSString *target = StringOrNil(DictionaryValueForKey(artifact, @"target"));
    NSString *destination = StringOrNil(DictionaryValueForKey(artifact, @"destination"));
    NSString *type = StringOrNil(DictionaryValueForKey(artifact, @"type")) ?: @"file";
    if (target.length == 0 || destination.length == 0) {
        return nil;
    }

    NSString *installedTarget = InstalledTargetName(destination, target);
    NSURL *destinationRootURL = [NSURL fileURLWithPath:JBRootPath(destination) isDirectory:YES];
    return [destinationRootURL URLByAppendingPathComponent:installedTarget isDirectory:[[type lowercaseString] isEqualToString:@"directory"]];
}

static BOOL CopyItem(NSURL *sourceURL, NSURL *destinationURL, NSString *type, NSNumber *modeNumber, NSError **error) {
    NSString *normalizedType = type.lowercaseString ?: @"file";

    if (!RemoveItemAsRoot(destinationURL, 36, @"Unable to remove existing install artifact", error)) {
        WFBridgeLog(@"Failed to remove existing item at destination URL: %@", destinationURL.path);
        return NO;
    }

    if (!EnsureDirectoryAtURL([destinationURL URLByDeletingLastPathComponent], error)) {
        WFBridgeLog(@"Failed to create directory for destination URL: %@", destinationURL.path);
        return NO;
    }

    NSArray<NSString *> *copyArguments = [normalizedType isEqualToString:@"directory"]
        ? @[@"-Rf", sourceURL.path, destinationURL.path]
        : @[@"-f", sourceURL.path, destinationURL.path];
    if (!RunRootCommand(@"/bin/cp", copyArguments, 37, @"Unable to copy install artifact", error)) {
        WFBridgeLog(@"Failed to copy artifact from %@ to %@", sourceURL.path, destinationURL.path);
        return NO;
    }

    return YES;
}

static BOOL WritePluginState(NSString *pluginName, BOOL enabled, NSError **error) {
    NSMutableDictionary *state = MutableStateDictionary();
    NSMutableDictionary *pluginStates = [[state[kPluginStatesKey] isKindOfClass:[NSDictionary class]] ? state[kPluginStatesKey] : @{} mutableCopy];
    pluginStates[pluginName] = @(enabled);
    state[kPluginStatesKey] = pluginStates;
    return WriteStateDictionary(state, error);
}

static NSDictionary<NSString *, NSString *> *VersionMetadataFromPropertyList(NSDictionary *plist) {
    if (![plist isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    NSString *pluginVersion = StringOrNil(plist[kPluginVersionKey]) ?: StringOrNil(plist[@"CFBundleShortVersionString"]);
    NSString *pluginBuildVersion = StringOrNil(plist[kPluginBuildVersionKey]) ?: StringOrNil(plist[@"CFBundleVersion"]);

    NSMutableDictionary<NSString *, NSString *> *metadata = [NSMutableDictionary dictionary];
    if (pluginVersion.length > 0) {
        metadata[@"version"] = pluginVersion;
    }
    if (pluginBuildVersion.length > 0) {
        metadata[@"buildVersion"] = pluginBuildVersion;
    }
    return metadata;
}

static BOOL PluginIsInstalledNamed(NSString *pluginName, NSDictionary *pluginInfo) {
    if (!PluginHasInstallableContent(pluginInfo)) {
        return YES;
    }

    NSArray<NSDictionary *> *artifacts = [pluginInfo[kInstallArtifactsKey] isKindOfClass:[NSArray class]] ? pluginInfo[kInstallArtifactsKey] : nil;
    if (artifacts.count == 0) {
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSDictionary *artifact in artifacts) {
        NSURL *installedURL = InstalledArtifactURL(artifact);
        if (!installedURL || ![fileManager fileExistsAtPath:installedURL.path]) {
            return NO;
        }
    }

    if (PluginRequiresGeneratedFilterPlist(pluginInfo)) {
        NSString *generatedFilterPath = GeneratedFilterDestinationURLForPluginNamed(pluginName).path;
        if (![fileManager fileExistsAtPath:generatedFilterPath]) {
            return NO;
        }
    }
    return YES;
}

static NSDictionary<NSString *, NSString *> *InstalledVersionMetadataForPluginNamed(NSString *pluginName, NSDictionary *pluginInfo) {
    if (!PluginIsInstalledNamed(pluginName, pluginInfo)) {
        return @{};
    }

    if (PluginRequiresGeneratedFilterPlist(pluginInfo)) {
        NSDictionary *generatedPlist = [NSDictionary dictionaryWithContentsOfURL:GeneratedFilterDestinationURLForPluginNamed(pluginName)];
        NSDictionary<NSString *, NSString *> *metadata = VersionMetadataFromPropertyList(generatedPlist);
        if (metadata.count > 0) {
            return metadata;
        }
    }

    NSArray<NSDictionary *> *artifacts = [pluginInfo[kInstallArtifactsKey] isKindOfClass:[NSArray class]] ? pluginInfo[kInstallArtifactsKey] : nil;
    for (NSDictionary *artifact in artifacts ?: @[]) {
        NSString *type = StringOrNil(DictionaryValueForKey(artifact, @"type")) ?: @"file";
        if (![[type lowercaseString] isEqualToString:@"directory"]) {
            continue;
        }

        NSURL *installedURL = InstalledArtifactURL(artifact);
        if (!installedURL) {
            continue;
        }

        NSDictionary *installedInfo = [NSDictionary dictionaryWithContentsOfURL:[installedURL URLByAppendingPathComponent:@"Info.plist"]];
        NSDictionary<NSString *, NSString *> *metadata = VersionMetadataFromPropertyList(installedInfo);
        if (metadata.count > 0) {
            return metadata;
        }
    }

    return VersionMetadataFromPropertyList(pluginInfo);
}

static BOOL EffectivePluginStateForName(NSString *pluginName, NSDictionary *pluginInfo, NSDictionary *storedStates) {
    if (!PluginHasInstallableContent(pluginInfo)) {
        NSNumber *enabledValue = NumberOrNil(storedStates[pluginName]);
        return enabledValue ? enabledValue.boolValue : YES;
    }

    return PluginIsInstalledNamed(pluginName, pluginInfo);
}

static NSDictionary<NSString *, NSNumber *> *DefaultPairingSettings(void) {
    return @{
        kPairingMinKey: @0,
        kPairingMaxKey: @36,
        kHelloThresholdKey: @0,
    };
}

static NSDictionary<NSString *, NSNumber *> *NormalizePairingSettings(NSDictionary<NSString *, id> *settings) {
    NSInteger minValue = MAX(0, MIN(64, [settings[kPairingMinKey] integerValue]));
    NSInteger maxValue = MAX(minValue, MIN(64, [settings[kPairingMaxKey] integerValue]));
    NSInteger thresholdValue = MAX(0, MIN(64, [settings[kHelloThresholdKey] integerValue]));
    return @{
        kPairingMinKey: @(minValue),
        kPairingMaxKey: @(maxValue),
        kHelloThresholdKey: @(thresholdValue),
    };
}

static NSDictionary<NSString *, id> *DirectPluginConfigurationNamed(NSString *pluginName) {
    if (pluginName.length == 0) {
        return @{};
    }

    NSDictionary *state = DirectStateDictionary();
    NSDictionary *configurations = [state[kPluginConfigurationsKey] isKindOfClass:[NSDictionary class]] ? state[kPluginConfigurationsKey] : @{};
    NSDictionary *configuration = [configurations[pluginName] isKindOfClass:[NSDictionary class]] ? configurations[pluginName] : nil;
    return configuration ?: @{};
}

static BOOL SavePluginConfigurationNamed(NSString *pluginName, NSDictionary<NSString *, id> *configuration, NSError **error) {
    if (pluginName.length == 0) {
        if (error) {
            *error = BridgeError(52, @"Missing plugin name");
        }
        return NO;
    }

    NSMutableDictionary *state = MutableStateDictionary();
    NSMutableDictionary *configurations = [[state[kPluginConfigurationsKey] isKindOfClass:[NSDictionary class]] ? state[kPluginConfigurationsKey] : @{} mutableCopy];
    configurations[pluginName] = configuration ?: @{};
    state[kPluginConfigurationsKey] = configurations;
    return WriteStateDictionary(state, error);
}

static NSDictionary<NSString *, NSNumber *> *DirectPairingSettings(void) {
    NSDictionary *settings = DirectPluginConfigurationNamed(kPairingConfigurationKey);
    if (settings.count == 0) {
        return @{};
    }
    return NormalizePairingSettings(settings);
}

static NSURL *LogDirectoryURL(NSString *path) {
    return [NSURL fileURLWithPath:path isDirectory:YES];
}

static BOOL DirectoryExistsAtPath(NSString *path) {
    if (path.length == 0) {
        return NO;
    }

    BOOL isDirectory = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory;
}

static NSString *GetLogPath(void) {
    static NSString *cachedPath = nil;
    if (cachedPath) {
        return cachedPath;
    }
    cachedPath = jbroot(LOG_PATH);
    return cachedPath;
}

static BOOL DirectPluginLoggingEnabled(void) {
    return DirectoryExistsAtPath(GetLogPath());
}

static NSArray<NSURL *> *PluginLogFileURLsAtPath(NSString *directoryPath) {
    NSURL *directoryURL = LogDirectoryURL(directoryPath);
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:directoryURL
      includingPropertiesForKeys:nil
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:nil];

    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    for (NSURL *candidateURL in contents ?: @[]) {
        if ([[candidateURL.pathExtension lowercaseString] isEqualToString:@"log"]) {
            [files addObject:candidateURL];
        }
    }

    return [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *lhs, NSURL *rhs) {
        return [lhs.lastPathComponent localizedCaseInsensitiveCompare:rhs.lastPathComponent];
    }];
}

static NSArray<NSString *> *LogLinesForFileURL(NSURL *fileURL) {
    NSData *data = [NSData dataWithContentsOfURL:fileURL options:0 error:nil];
    if (data.length == 0) {
        return @[];
    }

    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!content) {
        content = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    if (content.length == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [content enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        if (line.length > 0) {
            [lines addObject:line];
        }
    }];
    return lines;
}

static NSDictionary<NSString *, id> *DirectPluginLogSnapshot(void) {
    NSMutableArray<NSString *> *logs = [NSMutableArray array];
    for (NSURL *fileURL in PluginLogFileURLsAtPath(GetLogPath())) {
        [logs addObjectsFromArray:LogLinesForFileURL(fileURL)];
    }

    [logs sortUsingComparator:^NSComparisonResult(NSString *lhs, NSString *rhs) {
        return [lhs compare:rhs options:NSLiteralSearch];
    }];

    return @{
        @"logs": logs,
        @"enabled": @(DirectPluginLoggingEnabled()),
    };
}

static void AppendLog(NSString *message) {
    if (message.length == 0) {
        return;
    }

    Log(@"%@", message);
}

static BOOL SetPluginLoggingEnabledState(BOOL enabled, NSError **error) {
    NSURL *activeURL = LogDirectoryURL(GetLogPath());

    if (enabled) {
        if (DirectoryExistsAtPath(GetLogPath())) {
            return YES;
        }
        return EnsureDirectoryAtURL(activeURL, error);
    }

    if (!DirectoryExistsAtPath(GetLogPath())) {
        return YES;
    }
    return RemoveItemAsRoot(activeURL, 50, @"Unable to disable plugin logging", error);
}

static BOOL ClearPluginLogsPreservingState(NSError **error) {
    BOOL loggingEnabled = DirectPluginLoggingEnabled();
    NSURL *activeURL = LogDirectoryURL(GetLogPath());

    if (!RemoveItemAsRoot(activeURL, 51, @"Unable to remove plugin logs", error)) {
        return NO;
    }
    if (!loggingEnabled) {
        return YES;
    }
    return EnsureDirectoryAtURL(activeURL, error);
}

static BOOL ApplyDefaultPluginNamed(NSString *pluginName, BOOL enabled, NSError **error) {
    WFBridgeLog(@"Applying plugin %@ enabled=%d", pluginName ?: @"", enabled);

    NSURL *bundleURL = PluginBundleURLNamed(pluginName);
    NSDictionary *pluginInfo = bundleURL ? PluginInfoForURL(bundleURL) : nil;
    NSArray<NSDictionary *> *artifacts = [pluginInfo[kInstallArtifactsKey] isKindOfClass:[NSArray class]] ? pluginInfo[kInstallArtifactsKey] : nil;
    if (!bundleURL || !pluginInfo) {
        if (error) {
            *error = BridgeError(38, [NSString stringWithFormat:@"Missing packaged plugin '%@'", pluginName ?: @""]);
        }
        return NO;
    }

    if (!PluginHasInstallableContent(pluginInfo)) {
        return WritePluginState(pluginName, enabled, error);
    }

    if (artifacts.count == 0) {
        if (error) {
            *error = BridgeError(39, [NSString stringWithFormat:@"Missing packaged plugin '%@'", pluginName ?: @""]);
        }
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSDictionary *artifact in artifacts) {
        NSString *source = StringOrNil(DictionaryValueForKey(artifact, @"source"));
        NSString *target = StringOrNil(DictionaryValueForKey(artifact, @"target"));
        NSString *destination = StringOrNil(DictionaryValueForKey(artifact, @"destination"));
        NSString *type = StringOrNil(DictionaryValueForKey(artifact, @"type")) ?: @"file";
        NSNumber *mode = NumberOrNil(DictionaryValueForKey(artifact, @"mode"));
        if (source.length == 0 || target.length == 0 || destination.length == 0) {
            continue;
        }

        NSURL *sourceURL = [bundleURL URLByAppendingPathComponent:source];
        NSURL *destinationURL = InstalledArtifactURL(artifact);
        if (!destinationURL) {
            continue;
        }

        WFBridgeLog(@"Processing artifact for %@: source=%@ destination=%@ type=%@", pluginName ?: @"", sourceURL.path, destinationURL.path, type);

        if (enabled) {
            if (![fileManager fileExistsAtPath:sourceURL.path]) {
                if (error) {
                    *error = BridgeError(40, [NSString stringWithFormat:@"Missing payload artifact %@", source]);
                }
                WFBridgeLog(@"Source artifact does not exist at expected path: %@", sourceURL.path);
                return NO;
            }
            if (!CopyItem(sourceURL, destinationURL, type, mode, error)) {
                WFBridgeLog(@"Failed to copy artifact from %@ to %@", sourceURL.path, destinationURL.path);
                return NO;
            }
            WFBridgeLog(@"Successfully installed artifact to %@", destinationURL.path);
        } else {
            if (!RemoveItemAsRoot(destinationURL, 41, @"Unable to remove installed artifact", error)) {
                WFBridgeLog(@"Failed to remove installed artifact at %@", destinationURL.path);
                return NO;
            }
        }
    }

    if (PluginRequiresGeneratedFilterPlist(pluginInfo)) {
        NSURL *generatedFilterURL = GeneratedFilterDestinationURLForPluginNamed(pluginName);
        if (enabled) {
            if (!WriteGeneratedFilterPlist(generatedFilterURL, pluginInfo, error)) {
                return NO;
            }
        } else {
            if (!RemoveItemAsRoot(generatedFilterURL, 35, @"Unable to remove generated filter plist", error)) {
                return NO;
            }
        }
    }

    return WritePluginState(pluginName, enabled, error);
}

static BOOL ApplyPluginNamed(NSString *pluginName, BOOL enabled, NSError **error) {
    NSDictionary *pluginInfo = nil;
    WFPluginConfigurationContext *context = PluginConfigurationContextForPluginNamed(pluginName, &pluginInfo, nil);
    Class providerClass = context ? PluginConfigurationProviderClass(pluginName, pluginInfo) : Nil;
    SEL selector = enabled ? @selector(installPluginWithContext:error:) : @selector(removePluginWithContext:error:);
    if (!providerClass || ![providerClass respondsToSelector:selector]) {
        return ApplyDefaultPluginNamed(pluginName, enabled, error);
    }

    WFBridgeLog(@"Applying plugin %@ through configuration provider %@", pluginName ?: @"", NSStringFromClass(providerClass));
    typedef BOOL (*PluginActionIMP)(id, SEL, WFPluginConfigurationContext *, NSError **);
    PluginActionIMP implementation = (PluginActionIMP)[providerClass methodForSelector:selector];
    return implementation(providerClass, selector, context, error);
}

static NSDictionary<NSString *, NSNumber *> *DirectInstalledPluginStates(void) {
    NSDictionary *state = DirectStateDictionary();
    NSDictionary *storedStates = [state[kPluginStatesKey] isKindOfClass:[NSDictionary class]] ? state[kPluginStatesKey] : @{};
    NSMutableDictionary<NSString *, NSNumber *> *result = [NSMutableDictionary dictionary];

    for (NSURL *bundleURL in PluginBundleURLs()) {
        NSString *pluginName = [bundleURL.lastPathComponent stringByDeletingPathExtension];
        NSDictionary *pluginInfo = PluginInfoForURL(bundleURL);
        if (pluginName.length == 0 || !pluginInfo) {
            continue;
        }
        result[pluginName] = @(EffectivePluginStateForName(pluginName, pluginInfo, storedStates));
    }

    return result;
}

static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *DirectInstalledPluginVersions(void) {
    NSDictionary *state = DirectStateDictionary();
    NSDictionary *storedStates = [state[kPluginStatesKey] isKindOfClass:[NSDictionary class]] ? state[kPluginStatesKey] : @{};
    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *result = [NSMutableDictionary dictionary];

    for (NSURL *bundleURL in PluginBundleURLs()) {
        NSString *pluginName = [bundleURL.lastPathComponent stringByDeletingPathExtension];
        NSDictionary *pluginInfo = PluginInfoForURL(bundleURL);
        if (pluginName.length == 0 || !pluginInfo || !EffectivePluginStateForName(pluginName, pluginInfo, storedStates)) {
            continue;
        }

        NSDictionary<NSString *, NSString *> *metadata = InstalledVersionMetadataForPluginNamed(pluginName, pluginInfo);
        if (metadata.count > 0) {
            result[pluginName] = metadata;
        }
    }

    return result;
}

static NSArray<NSNumber *> *RunningProcessIdentifiersNamed(NSString *processName, NSError **error) {
    if (processName.length == 0) {
        return @[];
    }

    VMUProcList *procList = [VMUProcList new];
    if (!procList) {
        if (error) {
            *error = BridgeError(46, @"Unable to create VMUProcList");
        }
        return nil;
    }

    NSArray<VMUProcInfo *> *procInfos = [procList allProcInfos];
    NSMutableOrderedSet<NSNumber *> *matches = [NSMutableOrderedSet orderedSet];
    for (VMUProcInfo *procInfo in procInfos ?: @[]) {
        NSString *candidateName = procInfo.name;
        if (![candidateName isEqualToString:processName]) {
            continue;
        }

        pid_t pid = (pid_t)procInfo.pid;
        if (pid > 0) {
            [matches addObject:@(pid)];
        }
    }

    return matches.array;
}

static BOOL IsNonFatalTerminateError(NSError *error) {
    return error && [error.domain isEqualToString:RBSRequestErrorDomain] && error.code == 3;
}

static BOOL ExecuteTerminateRequestForProcessIdentifier(pid_t pid, NSString *processName, NSError **error) {
    if (pid <= 0) {
        if (error) {
            *error = BridgeError(47, [NSString stringWithFormat:@"Invalid pid for %@", processName ?: @"target"]);
        }
        return NO;
    }

    RBSProcessIdentifier *identifier = [RBSProcessIdentifier identifierWithPid:(int)pid];
    RBSProcessPredicate *predicate = identifier ? [RBSProcessPredicate predicateMatchingIdentifier:identifier] : nil;
    NSString *explanation = [NSString stringWithFormat:@"WatchFix restart request for %@", processName ?: @"process"];
    RBSTerminateContext *context = [RBSTerminateContext defaultContextWithExplanation:explanation];
    RBSTerminateRequest *request = (predicate && context) ? [[RBSTerminateRequest alloc] initWithPredicate:predicate context:context] : nil;
    if (!request) {
        if (error) {
            *error = BridgeError(48, [NSString stringWithFormat:@"Unable to create RBSTerminateRequest for %@ (%d)", processName ?: @"process", pid]);
        }
        return NO;
    }

    NSError *requestError = nil;
    BOOL executed = [request execute:&requestError];
    if (!executed) {
        if (IsNonFatalTerminateError(requestError)) {
            AppendLog([NSString stringWithFormat:@"Process %@ (%d) already exited before RunningBoard terminate completed", processName ?: @"process", pid]);
            return YES;
        }

        if (error) {
            NSString *message = requestError.localizedDescription ?: @"Unknown RunningBoardServices error";
            *error = BridgeError(49, [NSString stringWithFormat:@"RBSTerminateRequest %@ (%d) failed: %@", processName ?: @"process", pid, message]);
        }
        return NO;
    }

    AppendLog([NSString stringWithFormat:@"Terminated %@ (%d) via RunningBoardServices", processName ?: @"process", pid]);
    return YES;
}

static BOOL RestartWatchServices(NSError **error) {
    NSDictionary *state = DirectStateDictionary();
    NSDictionary *storedStates = [state[kPluginStatesKey] isKindOfClass:[NSDictionary class]] ? state[kPluginStatesKey] : @{};
    NSMutableOrderedSet<NSString *> *targets = [NSMutableOrderedSet orderedSet];
    for (NSURL *bundleURL in PluginBundleURLs()) {
        NSDictionary *pluginInfo = PluginInfoForURL(bundleURL);
        NSString *pluginName = [bundleURL.lastPathComponent stringByDeletingPathExtension];
        if (pluginName.length == 0 || !pluginInfo || !EffectivePluginStateForName(pluginName, pluginInfo, storedStates)) {
            continue;
        }

        NSDictionary *pluginManifest = PluginManifestDictionary(pluginInfo);
        NSArray *executables = [pluginManifest[kPluginRestartExecutablesKey] isKindOfClass:[NSArray class]] ? pluginManifest[kPluginRestartExecutablesKey] : @[];
        for (id value in executables) {
            NSString *name = StringOrNil(value);
            if (name.length > 0) {
                [targets addObject:name];
            }
        }

        AppendLog([NSString stringWithFormat:@"Restart request includes plugin %@", pluginName]);
    }

    for (NSString *target in targets) {
        NSError *lookupError = nil;
        NSArray<NSNumber *> *pids = RunningProcessIdentifiersNamed(target, &lookupError);
        if (!pids) {
            if (error) {
                *error = lookupError ?: BridgeError(41, [NSString stringWithFormat:@"Unable to enumerate running instances for %@", target]);
            }
            return NO;
        }

        if (pids.count == 0) {
            AppendLog([NSString stringWithFormat:@"Restart target %@ is not currently running", target]);
            continue;
        }

        for (NSNumber *pidValue in pids) {
            NSError *terminateError = nil;
            if (!ExecuteTerminateRequestForProcessIdentifier(pidValue.intValue, target, &terminateError)) {
                if (error) {
                    *error = terminateError ?: BridgeError(41, [NSString stringWithFormat:@"Unable to terminate %@", target]);
                }
                return NO;
            }
        }
    }

    return YES;
}

@implementation WFPluginBridge

+ (NSDictionary<NSString *,NSNumber *> *)pluginStates {
    NSDictionary<NSString *, NSNumber *> *states = DirectInstalledPluginStates();
    WFBridgeLog(@"Direct plugin states: %@", states);
    return states;
}

+ (NSDictionary<NSString *,NSDictionary<NSString *,NSString *> *> *)installedPluginVersions {
    return DirectInstalledPluginVersions();
}

+ (NSDictionary<NSString *,NSNumber *> *)pairingCompatibilitySettings {
    NSDictionary<NSString *, NSNumber *> *directSettings = DirectPairingSettings();
    if (directSettings.count > 0) {
        return directSettings;
    }
    return DefaultPairingSettings();
}

+ (NSDictionary<NSString *,id> *)configurationForPluginNamed:(NSString *)pluginName {
    return DirectPluginConfigurationNamed(pluginName);
}

+ (BOOL)pluginHasConfigurationInterfaceNamed:(NSString *)pluginName {
    NSDictionary *pluginInfo = nil;
    WFPluginConfigurationContext *context = PluginConfigurationContextForPluginNamed(pluginName, &pluginInfo, nil);
    if (!context || !pluginInfo) {
        return NO;
    }
    return ProviderClassImplementsConfigurationInterface(pluginName, pluginInfo);
}

+ (UIViewController *)configurationViewControllerForPluginNamed:(NSString *)pluginName error:(NSError * _Nullable __autoreleasing *)error {
    NSDictionary *pluginInfo = nil;
    WFPluginConfigurationContext *context = PluginConfigurationContextForPluginNamed(pluginName, &pluginInfo, error);
    if (!context) {
        return nil;
    }

    Class providerClass = PluginConfigurationProviderClass(pluginName, pluginInfo);
    SEL selector = @selector(configurationViewControllerWithContext:);
    if (!providerClass || ![providerClass respondsToSelector:selector]) {
        return nil;
    }

    typedef UIViewController *(*ViewControllerIMP)(id, SEL, WFPluginConfigurationContext *);
    ViewControllerIMP implementation = (ViewControllerIMP)[providerClass methodForSelector:selector];
    UIViewController *controller = implementation(providerClass, selector, context);
    if (!controller) {
        return nil;
    }
    if (![controller isKindOfClass:[UIViewController class]]) {
        if (error) {
            *error = BridgeError(54, [NSString stringWithFormat:@"Plugin '%@' returned an invalid configuration controller", pluginName ?: @""]);
        }
        return nil;
    }
    return controller;
}

+ (NSDictionary<NSString *,id> *)configurationPageForPluginNamed:(NSString *)pluginName error:(NSError * _Nullable __autoreleasing *)error {
    NSDictionary *pluginInfo = nil;
    WFPluginConfigurationContext *context = PluginConfigurationContextForPluginNamed(pluginName, &pluginInfo, error);
    if (!context) {
        return @{};
    }

    Class providerClass = PluginConfigurationProviderClass(pluginName, pluginInfo);
    SEL selector = @selector(configurationPageWithContext:);
    if (!providerClass || ![providerClass respondsToSelector:selector]) {
        return @{};
    }

    typedef NSDictionary<NSString *, id> *(*PageIMP)(id, SEL, WFPluginConfigurationContext *);
    PageIMP implementation = (PageIMP)[providerClass methodForSelector:selector];
    NSDictionary *page = implementation(providerClass, selector, context);
    if (![page isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    return page;
}

+ (BOOL)setPluginNamed:(NSString *)pluginName enabled:(BOOL)enabled error:(NSError * _Nullable __autoreleasing *)error {
    WFBridgeLog(@"Requesting plugin state change: %@ -> %d", pluginName ?: @"", enabled);
    if (pluginName.length == 0) {
        if (error) {
            *error = BridgeError(42, @"Missing plugin name");
        }
        return NO;
    }

    NSError *applyError = nil;
    BOOL success = ApplyPluginNamed(pluginName, enabled, &applyError);
    if (!success) {
        if (error) {
            *error = applyError ?: BridgeError(42, @"Unable to update plugin state");
        }
        return NO;
    }

    NSURL *bundleURL = PluginBundleURLNamed(pluginName);
    NSDictionary *pluginInfo = bundleURL ? PluginInfoForURL(bundleURL) : nil;
    BOOL hasInstallableContent = PluginHasInstallableContent(pluginInfo ?: @{});
    NSString *action = hasInstallableContent
        ? (enabled ? @"Installed" : @"Removed")
        : (enabled ? @"Enabled" : @"Disabled");
    AppendLog([NSString stringWithFormat:@"%@ %@", action, pluginName ?: @""]);
    PostPluginBridgeDidChangeNotification();
    return YES;
}

+ (BOOL)installPluginNamed:(NSString *)pluginName error:(NSError * _Nullable __autoreleasing *)error {
    return [self setPluginNamed:pluginName enabled:YES error:error];
}

+ (BOOL)removePluginNamed:(NSString *)pluginName error:(NSError * _Nullable __autoreleasing *)error {
    return [self setPluginNamed:pluginName enabled:NO error:error];
}

+ (BOOL)saveConfiguration:(NSDictionary<NSString *,id> *)configuration forPluginNamed:(NSString *)pluginName error:(NSError * _Nullable __autoreleasing *)error {
    NSDictionary *pluginInfo = nil;
    WFPluginConfigurationContext *context = PluginConfigurationContextForPluginNamed(pluginName, &pluginInfo, error);
    if (!context) {
        return NO;
    }

    NSDictionary<NSString *, id> *normalizedConfiguration = configuration ?: @{};
    Class providerClass = PluginConfigurationProviderClass(pluginName, pluginInfo);
    SEL normalizeSelector = @selector(normalizedConfiguration:context:);
    if (providerClass && [providerClass respondsToSelector:normalizeSelector]) {
        typedef NSDictionary<NSString *, id> *(*NormalizeIMP)(id, SEL, NSDictionary<NSString *, id> *, WFPluginConfigurationContext *);
        NormalizeIMP implementation = (NormalizeIMP)[providerClass methodForSelector:normalizeSelector];
        NSDictionary *providerConfiguration = implementation(providerClass, normalizeSelector, normalizedConfiguration, context);
        if (![providerConfiguration isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = BridgeError(53, [NSString stringWithFormat:@"Plugin '%@' returned an invalid configuration", pluginName ?: @""]);
            }
            return NO;
        }
        normalizedConfiguration = providerConfiguration;
    }

    if (!SavePluginConfigurationNamed(pluginName, normalizedConfiguration, error)) {
        return NO;
    }

    SEL didSaveSelector = @selector(didSaveConfigurationWithContext:error:);
    if (providerClass && [providerClass respondsToSelector:didSaveSelector]) {
        typedef BOOL (*DidSaveIMP)(id, SEL, WFPluginConfigurationContext *, NSError **);
        DidSaveIMP implementation = (DidSaveIMP)[providerClass methodForSelector:didSaveSelector];
        if (!implementation(providerClass, didSaveSelector, context, error)) {
            return NO;
        }
    }

    AppendLog([NSString stringWithFormat:@"Updated %@ settings", pluginName ?: @"plugin"]);
    PostPluginBridgeDidChangeNotification();
    return YES;
}

+ (BOOL)savePairingCompatibilitySettings:(NSDictionary<NSString *,NSNumber *> *)settings error:(NSError * _Nullable __autoreleasing *)error {
    NSDictionary<NSString *, NSNumber *> *normalizedSettings = NormalizePairingSettings(settings ?: @{});
    BOOL success = SavePluginConfigurationNamed(kPairingConfigurationKey, normalizedSettings, error);
    if (success) {
        AppendLog(@"Updated pairing compatibility settings");
        PostPluginBridgeDidChangeNotification();
    }
    return success;
}

+ (NSDictionary<NSString *,id> *)pluginLogSnapshot {
    return DirectPluginLogSnapshot();
}

+ (BOOL)setPluginLoggingEnabled:(BOOL)enabled error:(NSError * _Nullable __autoreleasing *)error {
    BOOL wasEnabled = DirectPluginLoggingEnabled();
    BOOL success = SetPluginLoggingEnabledState(enabled, error);
    if (success && enabled && !wasEnabled) {
        AppendLog(@"Plugin logging enabled");
    }
    return success;
}

+ (BOOL)clearPluginLogs:(NSError * _Nullable __autoreleasing *)error {
    return ClearPluginLogsPreservingState(error);
}

+ (BOOL)restartWatchServices:(NSError * _Nullable __autoreleasing *)error {
    NSError *restartError = nil;
    BOOL success = RestartWatchServices(&restartError);
    if (!success) {
        if (error) {
            *error = restartError ?: BridgeError(43, @"Unable to restart watch services");
        }
        return NO;
    }

    AppendLog(@"Restarted watch-related services");
    return YES;
}

+ (UIImage *)pluginIconForScopeIdentifier:(NSString *)scopeIdentifier {
    if (scopeIdentifier.length == 0) {
        return nil;
    }

    CGFloat scale = UIScreen.mainScreen.scale > 0 ? UIScreen.mainScreen.scale : 2.0;
    NSInteger roundedScale = MAX(2, MIN(3, (NSInteger)round(scale)));

    static NSString *const kWFPrefix = @"cn.fkj233.watchfix.";
    if ([scopeIdentifier hasPrefix:kWFPrefix]) {
        NSString *remainder = [scopeIdentifier substringFromIndex:kWFPrefix.length];
        NSArray<NSString *> *parts = [remainder componentsSeparatedByString:@"."];
        if (parts.count >= 2) {
            NSString *pluginName = parts[0];
            NSString *iconName = parts[1];
            NSURL *pluginsURL = [NSBundle mainBundle].builtInPlugInsURL;
            NSString *bundlePath = [[[[pluginsURL
                URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.wffix", pluginName]]
                URLByAppendingPathComponent:@"Payload"]
                URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.bundle", pluginName]] path];
            NSArray<NSString *> *suffixes = @[
                [NSString stringWithFormat:@"@%ldx", (long)roundedScale],
                @"@3x", @"@2x", @""
            ];
            NSMutableSet *seen = [NSMutableSet set];
            for (NSString *suffix in suffixes) {
                if ([seen containsObject:suffix]) continue;
                [seen addObject:suffix];
                NSString *filePath = [bundlePath stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@%@.png", iconName, suffix]];
                UIImage *img = [UIImage imageWithContentsOfFile:filePath];
                if (img) {
                    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
                }
            }
        }
    } else {
        for (NSNumber *formatValue in @[@2, @0]) {
            UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:scopeIdentifier
                                                                       format:formatValue.integerValue
                                                                        scale:scale];
            if (icon) {
                return [icon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            }
        }
    }

    // 统一回退：显示主程序图标
    for (NSNumber *formatValue in @[@2, @0]) {
        UIImage *appIcon = [UIImage _applicationIconImageForBundleIdentifier:@"cn.fkj233.watchfix.app"
                                                                      format:formatValue.integerValue
                                                                       scale:scale];
        if (appIcon) {
            return [appIcon imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    }

    return nil;
}

+ (void)showWarningBannerWithMessage:(NSString *)message delay:(NSTimeInterval)delay {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = ((UIWindowScene *)scene).windows.firstObject;
                break;
            }
        }
        if (!keyWindow) { return; }

        UIView *banner = [[UIView alloc] initWithFrame:CGRectZero];
        banner.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.92];
        banner.layer.cornerRadius = 14;
        banner.layer.cornerCurve = kCACornerCurveContinuous;
        banner.layer.shadowColor = UIColor.blackColor.CGColor;
        banner.layer.shadowOpacity = 0.18;
        banner.layer.shadowOffset = CGSizeMake(0, 4);
        banner.layer.shadowRadius = 8;
        banner.translatesAutoresizingMaskIntoConstraints = NO;
        banner.alpha = 0;

        UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill"]];
        iconView.tintColor = UIColor.whiteColor;
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [iconView.widthAnchor constraintEqualToConstant:20].active = YES;
        [iconView.heightAnchor constraintEqualToConstant:20].active = YES;

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = message;
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        label.textColor = UIColor.whiteColor;
        label.numberOfLines = 0;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[iconView, label]];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.alignment = UIStackViewAlignmentTop;
        stack.spacing = 10;
        stack.translatesAutoresizingMaskIntoConstraints = NO;

        [banner addSubview:stack];
        [keyWindow addSubview:banner];

        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:banner.topAnchor constant:14],
            [stack.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:14],
            [stack.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-14],
            [stack.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor constant:-14],
            [banner.leadingAnchor constraintEqualToAnchor:keyWindow.leadingAnchor constant:16],
            [banner.trailingAnchor constraintEqualToAnchor:keyWindow.trailingAnchor constant:-16],
            [banner.topAnchor constraintEqualToAnchor:keyWindow.safeAreaLayoutGuide.topAnchor constant:8],
        ]];

        banner.transform = CGAffineTransformMakeTranslation(0, -20);
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            banner.alpha = 1;
            banner.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.3 animations:^{ banner.alpha = 0; } completion:^(BOOL f) {
                    [banner removeFromSuperview];
                }];
            });
        }];
    });
}

@end
