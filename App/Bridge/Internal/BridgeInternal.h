#pragma once

#import <Foundation/Foundation.h>

static NSString *const kBridgeDomain  = @"cn.fkj233.watchfix.app";
static NSString *const kPairingMinKey = @"PairingCompatibilityMinVersion";
static NSString *const kPairingMaxKey = @"PairingCompatibilityMaxVersion";
static NSString *const kHelloThresholdKey = @"PairingCompatibilityHelloThreshold";

static NSTimeInterval const kSoftwareUpdateScanTimeout   = 20.0;
static NSTimeInterval const kRegistryRetryInterval       = 0.35;
static NSUInteger const kRegistryRetryCount              = 6;

static NSError *BridgeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:kBridgeDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

static NSNumber *NumberFromObject(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return value;
    }

    if ([value isKindOfClass:[NSString class]]) {
        NSString *stringValue = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (stringValue.length == 0) {
            return nil;
        }

        NSScanner *scanner = [NSScanner scannerWithString:stringValue];
        unsigned long long hexValue = 0;
        if ([stringValue hasPrefix:@"0x"] || [stringValue hasPrefix:@"0X"]) {
            if ([scanner scanHexLongLong:&hexValue]) {
                return @(hexValue);
            }
        }

        return @([stringValue longLongValue]);
    }

    return nil;
}
