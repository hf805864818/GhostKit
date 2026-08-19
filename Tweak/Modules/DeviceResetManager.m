//
//  DeviceResetManager.m
//  GhostKit
//

#import "DeviceResetManager.h"
#import "KeychainManager.h"
#import "IdentifierManager.h"
#import "CacheCleaner.h"
#import "SystemManager.h"
#import <UIKit/UIKit.h>

@implementation DeviceResetManager

+ (instancetype)sharedInstance {
    static DeviceResetManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DeviceResetManager alloc] init];
    });
    return instance;
}

#pragma mark - Reset

- (BOOL)resetDevice {
    NSLog(@"[GhostKit] resetDevice started");

    // 1. Clean all keychains.
    [[KeychainManager sharedInstance] deleteAllKeychains];

    // 2. Refresh IDFA.
    [[IdentifierManager sharedInstance] refreshIDFA];

    // 3. Clean system temporary files.
    [[CacheCleaner sharedInstance] cleanSystemResidue];

    // 4. Reset IDFV preferences + refresh IDFA again.
    [[IdentifierManager sharedInstance] changeIdentifier];

    // 5. Clean system-wide cookies.
    [[CacheCleaner sharedInstance] cleanCookiesForBundleID:nil];

    // 6. Clean pasteboard.
    [[CacheCleaner sharedInstance] cleanPasteboard];

    // 7. Clean notification data.
    [self cleanNotificationData];

    // 8. Clean WebKit data.
    [self cleanWebKitData];

    NSLog(@"[GhostKit] resetDevice cleanup complete, respringing...");

    // 9. Respring to apply changes.
    [[SystemManager sharedInstance] respring];

    return YES;
}

- (void)cleanNotificationData {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *paths = @[
        @"/var/mobile/Library/RemoteNotification",
        @"/var/mobile/Library/Caches/com.apple.notificationcenter",
        @"/var/mobile/Library/Preferences/com.apple.notificationcenter.plist",
        @"/var/mobile/Library/SpringBoard/activeNotifications.plist",
        @"/var/mobile/Library/SpringBoard/CSLSubstituteNotifications.plist",
    ];

    for (NSString *path in paths) {
        if ([fm fileExistsAtPath:path]) {
            NSError *error = nil;
            [fm removeItemAtPath:path error:&error];
            if (error) {
                NSLog(@"[GhostKit] Failed to remove %@: %@", path, error);
            }
        }
    }
}

- (void)cleanWebKitData {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *paths = @[
        @"/var/mobile/Library/Caches/WebKit",
        @"/var/mobile/Library/WebKit",
        @"/var/mobile/Library/Caches/com.apple.WebKit.WebContent",
        @"/var/mobile/Library/Caches/com.apple.WebKit.Networking",
    ];

    for (NSString *path in paths) {
        if ([fm fileExistsAtPath:path]) {
            [fm removeItemAtPath:path error:nil];
        }
    }
}

#pragma mark - Device info

- (NSDictionary *)getDeviceInfo {
    UIDevice *device = [UIDevice currentDevice];

    NSUUID *idfv = device.identifierForVendor;

    return @{
        @"name":                device.name ?: @"",
        @"model":               device.model ?: @"",
        @"systemName":          device.systemName ?: @"",
        @"systemVersion":       device.systemVersion ?: @"",
        @"identifierForVendor": idfv ? [idfv UUIDString] : @"",
        @"bundleIdentifier":    [[NSBundle mainBundle] bundleIdentifier] ?: @"",
    };
}

@end
