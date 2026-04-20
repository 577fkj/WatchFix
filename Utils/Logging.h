#import <Foundation/Foundation.h>

#define LOG_PATH @"/var/tmp/WatchFix"
#define LOG_PREFIX @"[WatchFix][%@] %@"

FOUNDATION_EXPORT void WFLog(const char *file, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
FOUNDATION_EXPORT void WFLogSwift(NSString *sourceFile, NSString *message);

#define Log(format, ...) WFLog(__FILE__, format, ##__VA_ARGS__)
