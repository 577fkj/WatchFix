#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "WatchUtils_internal.h"

// ---------------------------------------------------------------------------
// COSSoftwareUpdateController — alert for unsupported companion update (iOS 16.4+)
// ---------------------------------------------------------------------------

%group WatchAppSupportSoftwareUpdateControllerHooks

%hook WFSoftwareUpdateControllerClass

- (void)presentAlertForUpdatingCompanion {
    if (!IOSVersionAtLeast(16, 4, 0)) {
        %orig;
        return;
    }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Update Unsupported"
                                            message:WatchFixUnsupportedUpdateMessage()
                                     preferredStyle:UIAlertControllerStyleAlert];

    NSString *cancelTitle =
        [[NSBundle mainBundle] localizedStringForKey:@"CANCEL"
                                               value:@""
                                               table:nil];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:cancelTitle
                                 style:UIAlertActionStyleCancel
                               handler:^(__unused UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
        [[self navigationController] popViewControllerAnimated:YES];
    }];

    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

%end

%end

// ---------------------------------------------------------------------------
// COSSoftwareUpdateTableView — attributed text update message (pre-iOS 16.4)
// ---------------------------------------------------------------------------

%group WatchAppSupportSoftwareUpdateTableHooks

%hook WFSoftwareUpdateTableViewClass

- (void)informUserOfCompanionUpdate {
    %orig;

    if (IOSVersionAtLeast(16, 4, 0)) {
        return;
    }

    NSMutableAttributedString *message =
        [[NSMutableAttributedString alloc] initWithString:WatchFixUnsupportedUpdateMessage()];
    NSRange fullRange = NSMakeRange(0, [message length]);

    [message addAttribute:NSFontAttributeName
                    value:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]
                    range:fullRange];
    [message addAttribute:NSForegroundColorAttributeName
                    value:(BPSTextColor() ?: [UIColor blackColor])
                    range:fullRange];

    UITextView *textView = [(WatchFixSoftwareUpdateTableView *)self updateCompanionTextView];
    [textView setAttributedText:message];
}

%end

%end

// ---------------------------------------------------------------------------
// COSSetupController — pairing-not-possible alert
// ---------------------------------------------------------------------------

%group WatchAppSupportSetupControllerHooks

%hook WFSetupControllerClass

- (void)displayCompanionTooOldPairingFailureAlertWithDismissalHandler:(void (^)(void))dismissalHandler {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Pairing Not Possible"
                                            message:WatchFixPairingNotPossibleMessage()
                                     preferredStyle:UIAlertControllerStyleAlert];

    NSString *cancelTitle =
        [[NSBundle mainBundle] localizedStringForKey:@"CANCEL_PAIRING"
                                               value:@""
                                               table:nil];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:cancelTitle
                                 style:UIAlertActionStyleCancel
                               handler:^(__unused UIAlertAction *action) {
        if (dismissalHandler) {
            dismissalHandler();
        }
    }];

    [alert addAction:cancelAction];

    UIViewController *presenter = [[self navigationController] topViewController];
    if (!presenter) {
        presenter = self;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

%end

%end

// ---------------------------------------------------------------------------
// Module init — called from InitWatchAppSupportHooks() in WatchAppSupport.xm
// ---------------------------------------------------------------------------
void InitWatchAlertPatchHooks(void) {
    Class softwareUpdateControllerClass = objc_lookUpClass("COSSoftwareUpdateController");
    if (softwareUpdateControllerClass) {
        %init(WatchAppSupportSoftwareUpdateControllerHooks,
            WFSoftwareUpdateControllerClass=softwareUpdateControllerClass);
    }

    Class softwareUpdateTableViewClass = objc_lookUpClass("COSSoftwareUpdateTableView");
    if (softwareUpdateTableViewClass) {
        %init(WatchAppSupportSoftwareUpdateTableHooks,
            WFSoftwareUpdateTableViewClass=softwareUpdateTableViewClass);
    }

    Class setupControllerClass = objc_lookUpClass("COSSetupController");
    if (setupControllerClass) {
        %init(WatchAppSupportSetupControllerHooks, WFSetupControllerClass=setupControllerClass);
    }
}
