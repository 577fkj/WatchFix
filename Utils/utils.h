#include <stdarg.h>
#include <syslog.h>

#define LOG_PREFIX "[WatchFix][%s] "

void CLog(const char *file, const char *format, ...);
const char *CStringOrPlaceholder(NSString *value);
id CopyObjectIvarValueByName(id object, const char *name, Class expectedClass);
BOOL HookInstanceMethod(Class cls, SEL originalSelector, SEL replacementSelector);
bool is_equal(const char *s1, const char *s2);
bool starts_with(const char *pre, const char *str);
bool is_empty(const char *str);
bool isOSVersionAtLeast(int major, int minor, int patch);

#define Log(format, ...) CLog(__FILE__, format, ##__VA_ARGS__)

