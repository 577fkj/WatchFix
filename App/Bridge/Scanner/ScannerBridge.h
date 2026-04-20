#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WFVisualPairingScannerView : UIView

@property(nonatomic, copy, nullable) void (^scanHandler)(NSDictionary<NSString *, id> *result);

- (void)startScanning;
- (void)stopScanning;

@end

NS_ASSUME_NONNULL_END
