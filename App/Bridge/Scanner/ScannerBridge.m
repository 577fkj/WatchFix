#import "ScannerBridge.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>

@interface VPScannerView : UIView
- (void)_initCommon;
- (void)setScannedCodeHandler:(id)handler;
- (void)start;
- (void)stop;
@end

extern id PBBridgeMagicCodeDecoder(id value);

static NSString *WFScannerStringFromObject(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }

    if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    }

    return nil;
}

static NSNumber *WFScannerNumberFromObject(id value) {
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

static id WFSafeScannerValueForKey(id object, NSString *key) {
    if (!object || key.length == 0) {
        return nil;
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        return [(NSDictionary *)object objectForKey:key];
    }

    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *WFFormattedScannerWatchOSVersion(id value) {
    NSString *stringValue = WFScannerStringFromObject(value);
    if (stringValue.length > 0 && [stringValue rangeOfString:@"."].location != NSNotFound) {
        return stringValue;
    }

    NSNumber *numberValue = WFScannerNumberFromObject(value);
    if (!numberValue) {
        return stringValue;
    }

    unsigned int encodedVersion = [numberValue unsignedIntValue];
    NSInteger major = (encodedVersion >> 16) & 0xFF;
    NSInteger minor = (encodedVersion >> 8) & 0xFF;
    NSInteger patch = encodedVersion & 0xFF;

    if (major == 0 && minor == 0 && patch == 0) {
        return nil;
    }
    if (patch > 0) {
        return [NSString stringWithFormat:@"%ld.%ld.%ld", (long)major, (long)minor, (long)patch];
    }
    if (major > 0 || minor > 0) {
        return [NSString stringWithFormat:@"%ld.%ld", (long)major, (long)minor];
    }
    return stringValue;
}

static NSString *WFScannerRegexCapture(NSString *description, NSString *pattern) {
    if (description.length == 0) {
        return nil;
    }

    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match = [expression firstMatchInString:description options:0 range:NSMakeRange(0, description.length)];
    if (!match || match.numberOfRanges < 2) {
        return nil;
    }

    return [description substringWithRange:[match rangeAtIndex:1]];
}

static NSString *WFScannerFirstString(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        NSString *stringValue = WFScannerStringFromObject(WFSafeScannerValueForKey(object, key));
        if (stringValue.length > 0) {
            return stringValue;
        }
    }
    return nil;
}

static NSNumber *WFScannerFirstNumber(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        NSNumber *numberValue = WFScannerNumberFromObject(WFSafeScannerValueForKey(object, key));
        if (numberValue) {
            return numberValue;
        }
    }
    return nil;
}

static NSDictionary<NSString *, id> *WFNormalizedScanResult(id rawValue) {
    id decodedValue = rawValue;
    id candidate = PBBridgeMagicCodeDecoder(rawValue);
    if (candidate) {
        decodedValue = candidate;
    }

    NSString *description = [decodedValue description];
    NSString *watchOSVersion = WFFormattedScannerWatchOSVersion(WFScannerFirstString(decodedValue, @[@"watchOSVersion", @"productVersion", @"softwareVersion", @"version"]));
    if (watchOSVersion.length == 0) {
        watchOSVersion = WFScannerRegexCapture(description, @"(?:watchOSVersion|productVersion|softwareVersion|version)\\s*[=:]\\s*([0-9]+(?:\\.[0-9]+){0,2})");
    }

    NSString *chipID = WFScannerFirstString(decodedValue, @[@"chipID", @"chipId"]);
    if (chipID.length == 0) {
        chipID = WFScannerRegexCapture(description, @"(?:chipID|chipId)\\s*[=:]\\s*([0-9A-Fa-fx]+)");
    }

    NSNumber *pairingCompatibilityVersion = WFScannerFirstNumber(decodedValue, @[@"pairingCompatibilityVersion", @"maxPairingCompatibilityVersion", @"maximumPairingCompatibilityVersion", @"maxCompatibilityVersion", @"compatibilityVersion"]);
    if (!pairingCompatibilityVersion) {
        NSString *captured = WFScannerRegexCapture(description, @"(?:pairingCompatibilityVersion|maxPairingCompatibilityVersion|maximumPairingCompatibilityVersion|maxCompatibilityVersion|compatibilityVersion)\\s*[=:]\\s*([0-9]+)");
        pairingCompatibilityVersion = WFScannerNumberFromObject(captured);
    }

    NSString *productType = WFScannerFirstString(decodedValue, @[@"productType", @"productName", @"deviceClass", @"deviceName"]);
    if (productType.length == 0) {
        productType = WFScannerRegexCapture(description, @"(?:productType|productName|deviceClass|deviceName)\\s*[=:]\\s*([A-Za-z0-9,_-]+)");
    }

    NSString *watchName = WFScannerFirstString(decodedValue, @[@"watchName", @"name", @"targetDeviceName"]);

    NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
    result[@"source"] = @"magiccode";
    result[@"rawDescription"] = description ?: @"";

    if (watchOSVersion.length > 0) {
        result[@"watchOSVersion"] = watchOSVersion;
    }
    if (chipID.length > 0) {
        result[@"chipID"] = chipID;
    }
    if (pairingCompatibilityVersion) {
        result[@"pairingCompatibilityVersion"] = pairingCompatibilityVersion;
    }
    if (productType.length > 0) {
        result[@"productType"] = productType;
    }
    if (watchName.length > 0) {
        result[@"watchName"] = watchName;
    }

    return result;
}

// MARK: - WFVPScannerView

@interface WFVPScannerView : VPScannerView {
    CAShapeLayer *_viewfinderBorder;
    CAShapeLayer *_revealLayer;
    UILabel *_watchFixHintLabel;
}

@end

@implementation WFVPScannerView

- (void)_initCommon {
    [super _initCommon];

    _revealLayer = [self valueForKey:@"_viewfinderRevealLayer"];
    _viewfinderBorder = [self valueForKey:@"_viewfinderBorderLayer"];
    _viewfinderBorder.strokeColor = [UIColor systemYellowColor].CGColor;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    label.text = NSLocalizedString(@"scanner.viewfinder.hint", nil);
    label.layer.zPosition = CGFLOAT_MAX;
    label.layer.hidden = YES;
    _watchFixHintLabel = label;
    [self addSubview:label];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat W = self.bounds.size.width;
    CGFloat H = self.bounds.size.height;
    CGFloat vfWidth      = W * 0.46;
    CGFloat vfHeight     = vfWidth / 0.865;
    CGFloat vfX          = (W - vfWidth) * 0.5;
    CGFloat vfY          = (H - vfHeight) * 0.5;
    CGFloat cornerRadius = vfWidth * 0.20;
    CGRect  viewfinderRect = CGRectMake(vfX, vfY, vfWidth, vfHeight);

    UIBezierPath *borderPath =
        [UIBezierPath bezierPathWithRoundedRect:viewfinderRect
                                   cornerRadius:cornerRadius];
    _viewfinderBorder.path = borderPath.CGPath;

    CGMutablePathRef maskPath = CGPathCreateMutable();
    CGPathAddPath(maskPath, NULL, borderPath.CGPath);
    CGPathAddRect(maskPath, NULL, self.bounds);
    _revealLayer.path = maskPath;
    CGPathRelease(maskPath);

    CGFloat labelWidth  = W - 40.0;
    CGFloat labelHeight = vfY - 16.0;
    _watchFixHintLabel.frame = CGRectMake(20.0, 8.0, labelWidth, labelHeight);
}

- (void)start {
    [super start];
    _watchFixHintLabel.layer.hidden = NO;
    AVCaptureVideoPreviewLayer *previewLayer = [self valueForKey:@"_avPreviewLayer"];
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
}

- (void)stop {
    [super stop];
    _watchFixHintLabel.layer.hidden = YES;
}

@end

// MARK: - WFVisualPairingScannerView

@interface WFVisualPairingScannerView ()

@property(nonatomic, strong, nullable) WFVPScannerView *scannerView;

@end

@implementation WFVisualPairingScannerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.clipsToBounds = YES;
    self.layer.cornerRadius = 18.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self attachScannerIfNeeded];
        [self startScanning];
    } else {
        [self stopScanning];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scannerView.frame = self.bounds;
}

- (void)attachScannerIfNeeded {
    if (self.scannerView) {
        return;
    }

    WFVPScannerView *scanner = [[WFVPScannerView alloc] initWithFrame:self.bounds];
    scanner.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak typeof(self) weakSelf = self;
    [scanner setScannedCodeHandler:^(id rawValue) {
        NSDictionary<NSString *, id> *result = WFNormalizedScanResult(rawValue);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf.scanHandler) {
                strongSelf.scanHandler(result);
            }
        });
    }];

    [self addSubview:scanner];
    self.scannerView = scanner;
}

- (void)startScanning {
    [self attachScannerIfNeeded];
    [self.scannerView start];
}

- (void)stopScanning {
    [self.scannerView stop];
}

@end
