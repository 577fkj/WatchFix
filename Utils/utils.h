#import <Foundation/Foundation.h>
#import "Logging.h"

NSString *StringFromCString(const char *value);
NSString *BoolString(BOOL value);
NSString *safe_jbroot(NSString *path);
id CopyObjectIvarValueByName(id object, const char *name, Class expectedClass);
bool is_equal(const char *s1, const char *s2);
bool starts_with(const char *pre, const char *str);
bool is_empty(const char *str);

// Real iOS version check via sysctl — bypasses any NSProcessInfo hook.
// Returns YES if the actual running iOS version is >= major.minor.patch.
BOOL IOSVersionAtLeast(NSInteger major, NSInteger minor, NSInteger patch);
NSInteger IOSMajorVersion();
NSInteger IOSMinorVersion();
NSInteger IOSPatchVersion();
