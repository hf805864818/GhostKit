//
//  GSKPreferencesController.m
//  GhostKit Preference Bundle
//
//  Loads preference specifiers from GhostKitPrefs.plist.
//  Handles system action buttons (respring, ldrestart).
//

#import "GSKPreferencesController.h"
#import <CoreFoundation/CoreFoundation.h>

// Preference keys (must match Tweak.x).
static NSString *const kPrefEnabled           = @"GhostKitEnabled";
static NSString *const kPrefGestureEnabled    = @"GhostKitGestureEnabled";
static NSString *const kPrefKeychainEnabled   = @"GhostKitKeychainCleanEnabled";
static NSString *const kPrefIDFAEnabled        = @"GhostKitIDFARefreshEnabled";
static NSString *const kPrefCacheEnabled       = @"GhostKitCacheCleanEnabled";

@implementation GSKPreferencesController

- (id)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"GhostKitPrefs" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"GhostKit";
}

#pragma mark - Button actions

/// Respring button — post a Darwin notification to trigger respring.
- (void)respringButtonTapped {
    // Show confirmation alert.
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"确认注销"
                         message:@"设备将立即注销 (Respring)，确定继续？"
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"取消"
                  style:UIAlertActionStyleCancel
                handler:nil]];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"确定"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
        // Post Darwin notification to trigger respring.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge CFStringRef)@"GhostKitRespring",
            NULL,
            NULL,
            TRUE);
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

/// ldrestart button — post a Darwin notification to trigger ldrestart.
- (void)ldrestartButtonTapped {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"确认软重启"
                         message:@"系统守护进程将重启 (ldrestart)，可能需要几秒钟，确定继续？"
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"取消"
                  style:UIAlertActionStyleCancel
                handler:nil]];

    [alert addAction:[UIAlertAction
        actionWithTitle:@"确定"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
        // Post Darwin notification to trigger ldrestart.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge CFStringRef)@"GhostKitLdrestart",
            NULL,
            NULL,
            TRUE);
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
