#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#include <errno.h>
#include <spawn.h>
#include <string.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <unistd.h>
#include "utils.h"

#ifdef __cplusplus
extern "C" {
#endif
extern char **environ;
#ifdef __cplusplus
}
#endif

typedef const char *(*WFSafeJBRootFunction)(const char *);

static NSString *const kWFSafeJBRootDefaultPrefix = @"/var/jb";
static NSString *const kWFSafeJBRootLibraryRelativePath = @".jbroot/usr/lib/libroothide.dylib";

static NSString *WFDefaultJBRootPrefix(void) {
#if defined(THEOS_PACKAGE_SCHEME_ROOTLESS) && THEOS_PACKAGE_SCHEME_ROOTLESS
    return kWFSafeJBRootDefaultPrefix;
#else
    return @"";
#endif
}

static BOOL WFSafeJBRootWantsPrefix(NSString *path) {
    return path.length == 0 || [path isEqualToString:@"/"];
}

static NSString *WFTrimmedPathOutput(NSString *value) {
    NSString *trimmedValue = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while (trimmedValue.length > 1 && [trimmedValue hasSuffix:@"/"]) {
        trimmedValue = [trimmedValue substringToIndex:trimmedValue.length - 1];
    }
    return trimmedValue;
}

static NSString *WFRequestedJBRootPath(NSString *path) {
    return WFSafeJBRootWantsPrefix(path) ? @"/" : path;
}

static NSString *WFLoaderPathRootHideLibraryPath(void) {
    Dl_info info = {};
    if (dladdr((const void *)&safe_jbroot, &info) == 0 || !info.dli_fname) {
        return nil;
    }

    NSString *imagePath = [NSString stringWithUTF8String:info.dli_fname];
    if (imagePath.length == 0) {
        return nil;
    }

    NSString *loaderPath = [imagePath stringByDeletingLastPathComponent];
    return [loaderPath stringByAppendingPathComponent:kWFSafeJBRootLibraryRelativePath];
}

static WFSafeJBRootFunction WFLoaderPathJBRootFunction(void) {
    static dispatch_once_t onceToken;
    static WFSafeJBRootFunction jbrootFunction = NULL;

    dispatch_once(&onceToken, ^{
        NSString *libraryPath = WFLoaderPathRootHideLibraryPath();
        if (libraryPath.length == 0) {
            return;
        }

        if (![[NSFileManager defaultManager] fileExistsAtPath:libraryPath]) {
            return;
        }

        void *handle = dlopen(libraryPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (!handle) {
            return;
        }

        jbrootFunction = (WFSafeJBRootFunction)dlsym(handle, "jbroot");
    });

    return jbrootFunction;
}

static NSString *WFJBRootPrefixFromCommandLine(void) {
    static dispatch_once_t onceToken;
    static NSString *cachedPrefix = nil;

    dispatch_once(&onceToken, ^{
#if defined(THEOS_PACKAGE_SCHEME_ROOTLESS) && THEOS_PACKAGE_SCHEME_ROOTLESS
        cachedPrefix = kWFSafeJBRootDefaultPrefix;
        return;
#endif

        int outputPipe[2] = {-1, -1};
        if (pipe(outputPipe) != 0) {
            cachedPrefix = WFDefaultJBRootPrefix();
            return;
        }

        posix_spawn_file_actions_t fileActions;
        if (posix_spawn_file_actions_init(&fileActions) != 0) {
            close(outputPipe[0]);
            close(outputPipe[1]);
            cachedPrefix = WFDefaultJBRootPrefix();
            return;
        }

        posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], STDOUT_FILENO);
        posix_spawn_file_actions_addclose(&fileActions, outputPipe[0]);
        posix_spawn_file_actions_addclose(&fileActions, outputPipe[1]);

        char command[] = "jbroot";
        char rootPath[] = "/";
        char *const argv[] = {command, rootPath, NULL};
        pid_t pid = 0;
        int spawnStatus = posix_spawnp(&pid, command, &fileActions, NULL, argv, environ);

        posix_spawn_file_actions_destroy(&fileActions);
        close(outputPipe[1]);

        if (spawnStatus != 0) {
            close(outputPipe[0]);
            cachedPrefix = WFDefaultJBRootPrefix();
            return;
        }

        NSMutableData *outputData = [NSMutableData data];
        uint8_t buffer[256];
        ssize_t bytesRead = 0;
        while ((bytesRead = read(outputPipe[0], buffer, sizeof(buffer))) > 0) {
            [outputData appendBytes:buffer length:(NSUInteger)bytesRead];
        }
        close(outputPipe[0]);

        int waitStatus = 0;
        while (waitpid(pid, &waitStatus, 0) == -1 && errno == EINTR) {
        }

        NSString *outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
        NSString *resolvedPrefix = WFTrimmedPathOutput(outputString ?: @"");
        if (resolvedPrefix.length > 0 && WIFEXITED(waitStatus) && WEXITSTATUS(waitStatus) == 0) {
            cachedPrefix = resolvedPrefix;
            return;
        }

        cachedPrefix = WFDefaultJBRootPrefix();
    });

    return cachedPrefix ?: WFDefaultJBRootPrefix();
}

static NSString *WFPathByApplyingJBRootPrefix(NSString *prefix, NSString *path) {
    if (prefix.length == 0) {
        return WFSafeJBRootWantsPrefix(path) ? @"/" : path;
    }

    if (WFSafeJBRootWantsPrefix(path)) {
        return prefix;
    }

    if ([path isEqualToString:prefix] || [path hasPrefix:[prefix stringByAppendingString:@"/"]]) {
        return path;
    }

    if ([path hasPrefix:@"/"]) {
        return [prefix stringByAppendingString:path];
    }

    return [prefix stringByAppendingPathComponent:path];
}

NSString *StringFromCString(const char *value) {
    if (!value) {
        return @"<nil>";
    }

    NSString *stringValue = [NSString stringWithUTF8String:value];
    return stringValue ?: @"<invalid UTF-8>";
}

NSString *BoolString(BOOL value) {
    return value ? @"YES" : @"NO";
}

NSString *safe_jbroot(NSString *path) {
    NSString *requestedPath = WFRequestedJBRootPath(path);
    WFSafeJBRootFunction jbrootFunction = WFLoaderPathJBRootFunction();
    if (jbrootFunction) {
        const char *resolvedPath = jbrootFunction(requestedPath.fileSystemRepresentation);
        if (resolvedPath) {
            NSString *stringValue = [NSString stringWithUTF8String:resolvedPath];
            NSString *trimmedValue = WFTrimmedPathOutput(stringValue ?: @"");
            if (trimmedValue.length > 0) {
                return trimmedValue;
            }
        }
    }

    return WFPathByApplyingJBRootPrefix(WFJBRootPrefixFromCommandLine(), requestedPath);
}

id CopyObjectIvarValueByName(id object, const char *name, Class expectedClass) {
    if (!object || !name) {
        return nil;
    }

    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar) {
        return nil;
    }

    id value = object_getIvar(object, ivar);
    if (!value || (expectedClass && ![value isKindOfClass:expectedClass])) {
        return nil;
    }

    return value;
}

bool is_equal(const char *s1, const char *s2) {
    if (!s1 || !s2) return false;
    return strcmp(s1, s2) == 0;
}

bool starts_with(const char *pre, const char *str) {
    if (!pre || !str) return false;
    return strncmp(pre, str, strlen(pre)) == 0;
}

bool is_empty(const char *str) {
    return !str || str[0] == '\0';
}


static NSInteger cachedMajor = -1, cachedMinor = -1, cachedPatch = -1;
static void ParseSysctlIOSVersion() {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        char buf[32] = {0};
        size_t len = sizeof(buf);
        if (sysctlbyname("kern.osproductversion", buf, &len, NULL, 0) != 0) {
            Log(@"sysctlbyname failed: %s", strerror(errno));
            cachedMajor = 0;
            cachedMinor = 0;
            cachedPatch = 0;
            return;
        }
        NSInteger major = 0, minor = 0, patch = 0;
        sscanf(buf, "%ld.%ld.%ld", &major, &minor, &patch);
        cachedMajor = major;
        cachedMinor = minor;
        cachedPatch = patch;
    });
}

BOOL IOSVersionAtLeast(NSInteger major, NSInteger minor, NSInteger patch) {
    ParseSysctlIOSVersion();
    if (cachedMajor != major) { return cachedMajor > major; }
    if (cachedMinor != minor) { return cachedMinor > minor; }
    return cachedPatch >= patch;
}

NSInteger IOSMajorVersion(void) {
    ParseSysctlIOSVersion();
    return cachedMajor;
}

NSInteger IOSMinorVersion(void) {
    ParseSysctlIOSVersion();
    return cachedMinor;
}

NSInteger IOSPatchVersion(void) {
    ParseSysctlIOSVersion();
    return cachedPatch;
}
