#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <syslog.h>
#import "Logging.h"
#import "utils.h"

static BOOL WFLogEnabled(void)
{
    static NSString *logPath = nil;
    if (logPath == nil) {
        logPath = safe_jbroot(LOG_PATH);
        syslog(LOG_NOTICE, "[WatchFix] Logging to file: %s", logPath.UTF8String);
    }

    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:logPath isDirectory:&isDir];

    return exists && isDir;
}

static NSString *WFModuleName(void)
{
    Dl_info info;
    if (!dladdr(__builtin_return_address(0), &info) || !info.dli_fname) {
        return @"Unknown";
    }

    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    NSString *name = [path lastPathComponent];

    // Remove prefix "WatchFix_" and suffix ".dylib"
    if ([name hasPrefix:@"WatchFix_"]) {
        name = [name substringFromIndex:9];
    }

    if ([name hasSuffix:@".dylib"]) {
        name = [name substringToIndex:name.length - 6];
    }

    return name;
}

void WFLog(const char *file, NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *sourceFile = [[[NSString stringWithUTF8String:file] lastPathComponent] stringByDeletingPathExtension];
    NSString *line = [NSString stringWithFormat:LOG_PREFIX, sourceFile, message];
    NSString *syslogLine = [line stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    const NSUInteger kSyslogChunkChars = 800;
    if (syslogLine.length <= kSyslogChunkChars) {
        syslog(LOG_NOTICE, "%s", syslogLine.UTF8String ?: "<invalid UTF-8>");
    } else {
        NSUInteger total = syslogLine.length;
        NSUInteger offset = 0;
        NSUInteger partIndex = 1;
        NSUInteger totalParts = (total + kSyslogChunkChars - 1) / kSyslogChunkChars;
        while (offset < total) {
            NSUInteger len = MIN(kSyslogChunkChars, total - offset);
            NSString *chunk = [syslogLine substringWithRange:NSMakeRange(offset, len)];
            syslog(LOG_NOTICE, "[%lu/%lu] %s", (unsigned long)partIndex, (unsigned long)totalParts, chunk.UTF8String ?: "");
            offset += len;
            partIndex++;
        }
    }

    if (!WFLogEnabled()) {
        return;
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *timeString = [formatter stringFromDate:[NSDate date]];

    NSString *processName = [[NSProcessInfo processInfo] processName];
    NSString *moduleName = WFModuleName();

    NSString *fileLine = [NSString stringWithFormat:@"%@ %@(%@): %@\n",
                          timeString,
                          processName,
                          moduleName,
                          line];

    if (moduleName == nil || [moduleName isEqualToString:@"Unknown"]) {
        moduleName = processName;
    }

    static NSString *logPath = nil;
    if (logPath == nil) {
        logPath = safe_jbroot([LOG_PATH stringByAppendingPathComponent:[moduleName stringByAppendingString:@".log"]]);
        syslog(LOG_NOTICE, "[WatchFix] Logging to file: %s", logPath.UTF8String);
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath]; // TODO: The program did not create and write permission
    if (!fileHandle) {
        [[NSFileManager defaultManager] createFileAtPath:logPath
                                                contents:nil
                                              attributes:nil];
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    }

    [fileHandle seekToEndOfFile];
    [fileHandle writeData:[fileLine dataUsingEncoding:NSUTF8StringEncoding]];
    [fileHandle closeFile];
}

void WFLogSwift(NSString *sourceFile, NSString *message)
{
    const char *file = sourceFile.length > 0 ? sourceFile.UTF8String : "Swift";
    WFLog(file, @"%@", message ?: @"");
}
