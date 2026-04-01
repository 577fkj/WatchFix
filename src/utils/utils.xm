#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdarg.h>
#include <syslog.h>
#include "utils.h"

void CLog(const char *file, const char *format, ...) {
    const char *fileName = strrchr(file, '/');
    fileName = (fileName) ? (fileName + 1) : file;

    char new_format[512]; 
    snprintf(new_format, sizeof(new_format), LOG_PREFIX "%s", fileName, format);

    va_list args;
    va_start(args, format);
    vsyslog(LOG_NOTICE, new_format, args);
    va_end(args);
}

const char *CStringOrPlaceholder(NSString *value) {
    return value ? value.UTF8String : "<nil>";
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