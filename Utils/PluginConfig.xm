#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <roothide.h>
#include "PluginConfig.h"

static NSString *const kWFStateRelativePath = @"/var/mobile/Library/Preferences/cn.fkj233.watchfix.plist";
static NSString *const kWFPluginConfigurationsKey = @"PluginConfigurations";
static NSString *const kWFPluginPrefix = @"WatchFix_";

static NSString *WFJBRootPath(NSString *path) {
    const char *resolved = jbroot(path.fileSystemRepresentation);
    if (resolved) {
        NSString *stringValue = [NSString stringWithUTF8String:resolved];
        if (stringValue.length > 0) {
            return stringValue;
        }
    }
    return path;
}

static NSArray<NSString *> *WFStatePathCandidates(void) {
    NSString *jbrootPath = WFJBRootPath(kWFStateRelativePath);
    if ([jbrootPath isEqualToString:kWFStateRelativePath]) {
        return @[kWFStateRelativePath];
    }
    return @[kWFStateRelativePath, jbrootPath];
}

static NSDictionary *WFStateDictionary(void) {
    for (NSString *candidate in WFStatePathCandidates()) {
        NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:candidate];
        if ([stored isKindOfClass:[NSDictionary class]]) {
            return stored;
        }
    }
    return @{};
}

static NSNumber *WFNumberOrNil(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return value;
    }

    if ([value isKindOfClass:[NSString class]]) {
        NSString *stringValue = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (stringValue.length == 0) {
            return nil;
        }
        return @([stringValue longLongValue]);
    }

    return nil;
}

static BOOL WFBoolValueOrFallback(id value, BOOL fallbackValue) {
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

static NSString *WFPluginIdentifierFromFileName(NSString *fileName) {
    if (fileName.length == 0 || ![fileName hasPrefix:kWFPluginPrefix]) {
        return nil;
    }

    NSString *identifier = [fileName substringFromIndex:kWFPluginPrefix.length];
    for (NSString *suffix in @[@".plist", @".dylib"]) {
        if ([identifier hasSuffix:suffix]) {
            identifier = [identifier substringToIndex:identifier.length - suffix.length];
            break;
        }
    }

    return identifier.length > 0 ? identifier : nil;
}

static NSString *WFPluginIdentifierFromImagePath(NSString *imagePath) {
    if (imagePath.length == 0) {
        return nil;
    }

    NSString *fileNameIdentifier = WFPluginIdentifierFromFileName(imagePath.lastPathComponent);
    if (fileNameIdentifier.length > 0) {
        return fileNameIdentifier;
    }

    for (NSString *component in imagePath.pathComponents.reverseObjectEnumerator) {
        NSString *extension = component.pathExtension.lowercaseString;
        if ([extension isEqualToString:@"bundle"] || [extension isEqualToString:@"wffix"]) {
            NSString *identifier = component.stringByDeletingPathExtension;
            if (identifier.length > 0) {
                return identifier;
            }
        }
    }

    return nil;
}

static NSString *WFCurrentPluginIdentifier(void) {
    Dl_info info = {};
    if (dladdr((const void *)&WFCurrentPluginIdentifier, &info) == 0 || !info.dli_fname) {
        return nil;
    }

    NSString *imagePath = [NSString stringWithUTF8String:info.dli_fname];
    return WFPluginIdentifierFromImagePath(imagePath);
}

NSDictionary *WFCurrentPluginConfiguration(void) {
    NSString *pluginIdentifier = WFCurrentPluginIdentifier();
    if (pluginIdentifier.length == 0) {
        return @{};
    }

    NSDictionary *state = WFStateDictionary();
    NSDictionary *configurations = [state[kWFPluginConfigurationsKey] isKindOfClass:[NSDictionary class]] ? state[kWFPluginConfigurationsKey] : @{};
    NSDictionary *configuration = [configurations[pluginIdentifier] isKindOfClass:[NSDictionary class]] ? configurations[pluginIdentifier] : nil;
    return configuration ?: @{};
}

NSNumber *WFCurrentPluginConfigurationNumberValue(NSString *key) {
    if (key.length == 0) {
        return nil;
    }

    NSDictionary *configuration = WFCurrentPluginConfiguration();
    return WFNumberOrNil(configuration[key]);
}

NSInteger WFCurrentPluginIntegerConfigurationValue(NSString *key, NSInteger fallbackValue) {
    NSNumber *value = WFCurrentPluginConfigurationNumberValue(key);
    return value ? value.integerValue : fallbackValue;
}

BOOL WFCurrentPluginBooleanConfigurationValue(NSString *key, BOOL fallbackValue) {
    if (key.length == 0) {
        return fallbackValue;
    }

    NSDictionary *configuration = WFCurrentPluginConfiguration();
    return WFBoolValueOrFallback(configuration[key], fallbackValue);
}

NSString *WFCurrentPluginStringConfigurationValue(NSString *key, NSString *fallbackValue) {
    if (key.length == 0) {
        return fallbackValue;
    }
    NSDictionary *configuration = WFCurrentPluginConfiguration();
    id value = configuration[key];
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return fallbackValue;
}
