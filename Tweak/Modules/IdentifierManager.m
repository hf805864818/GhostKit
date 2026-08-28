//
//  IdentifierManager.m
//  GhostKit
//
//  Uses ASIdentifierManager for IDFA, UIDevice for IDFV,
//  and libMobileGestalt for UDID.
//

#import "IdentifierManager.h"
#import "KeychainManager.h"
#import <AdSupport/AdSupport.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

@implementation IdentifierManager

+ (instancetype)sharedInstance {
    static IdentifierManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[IdentifierManager alloc] init];
    });
    return instance;
}

#pragma mark - IDFA

- (NSString *)getCurrentIDFA {
    NSUUID *idfa = [[ASIdentifierManager sharedManager] advertisingIdentifier];
    return idfa ? [idfa UUIDString] : @"";
}

#pragma mark - Refresh IDFA

- (BOOL)refreshIDFA {
    // The system caches the IDFA in the keychain under the "com.apple.adid"
    // access group.  Deleting those records forces the system to generate
    // a new IDFA on next read.

    // 1. Security framework deletion by access group.
    //    All keychain operations use the Security framework (SecItemDelete)
    //    instead of direct SQLite access to keychain-2.db, which fails on
    //    rootless jailbreaks / TrollStore.
    NSArray *accessGroups = @[
        @"com.apple.adid",
        @"com.apple.identifieradvertising",
    ];
    for (NSString *group in accessGroups) {
        [[KeychainManager sharedInstance] cleanKeychainForBundleID:group];
    }

    // 2. Also delete by the well-known service names used by iOS.
    //    Some IDFA items use these as the service attribute.
    NSArray *serviceNames = @[
        @"com.apple.adid",
        @"adid",
        @"com.apple.identifieradvertising",
    ];
    NSArray *secClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
    ];

    for (id secClass in secClasses) {
        for (NSString *service in serviceNames) {
            NSDictionary *query = @{
                (__bridge id)kSecClass:       secClass,
                (__bridge id)kSecAttrService:  service,
                (__bridge id)kSecMatchLimit:  (__bridge id)kSecMatchLimitAll,
            };
            SecItemDelete((__bridge CFDictionaryRef)query);
        }

        // Also try deleting by account attribute.
        for (NSString *acct in serviceNames) {
            NSDictionary *query = @{
                (__bridge id)kSecClass:       secClass,
                (__bridge id)kSecAttrAccount:  acct,
                (__bridge id)kSecMatchLimit:  (__bridge id)kSecMatchLimitAll,
            };
            SecItemDelete((__bridge CFDictionaryRef)query);
        }
    }

    // 3. Clear the advertising identifier cache plist.
    //    On iOS, delete the plist file directly — iOS will regenerate it
    //    with default values on next access.
    NSString *cachePlist = @"/var/mobile/Library/Preferences/com.apple.adid.plist";
    [[NSFileManager defaultManager] removeItemAtPath:cachePlist error:nil];

    // 4. Also clear the advertisingIdentifier preferences plist.
    NSString *adPrefs = @"/var/mobile/Library/Preferences/com.apple.advertisingIdentifier.plist";
    [[NSFileManager defaultManager] removeItemAtPath:adPrefs error:nil];

    NSLog(@"[GhostKit] refreshIDFA completed");
    return YES;
}

#pragma mark - Change identifier

- (BOOL)changeIdentifier {
    // Refresh IDFA.
    [self refreshIDFA];

    // Reset IDFV preferences.  The identifierForVendor is cached per-app;
    // clearing the preferences domain can force a re-generation on next launch.
    NSString *vendorPrefs = @"/var/mobile/Library/Preferences/com.apple.identifierforvendor.plist";
    [[NSFileManager defaultManager] removeItemAtPath:vendorPrefs error:nil];

    // Remove persistent domain for vendor identifier in NSUserDefaults.
    [[NSUserDefaults standardUserDefaults]
        removePersistentDomainForName:@"com.apple.identifierforvendor"];

    // Also wipe the general ad tracking preference.
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"NSUserTrackingAlertShown"];

    NSLog(@"[GhostKit] changeIdentifier completed");
    return YES;
}

#pragma mark - Current identifiers

- (NSString *)getUDID {
    // Use libMobileGestalt to read UniqueDeviceID.
    void *lib = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (lib) {
        CFStringRef (*MGCopyAnswer)(CFStringRef) =
            (CFStringRef (*)(CFStringRef))dlsym(lib, "MGCopyAnswer");
        if (MGCopyAnswer) {
            CFStringRef udid = MGCopyAnswer(CFSTR("UniqueDeviceID"));
            if (udid) {
                return (__bridge_transfer NSString *)udid;
            }
        }
    }
    return @"";
}

- (NSDictionary *)getCurrentIdentifiers {
    NSString *idfa = [self getCurrentIDFA];

    NSUUID *idfv = [[UIDevice currentDevice] identifierForVendor];
    NSString *idfvStr = idfv ? [idfv UUIDString] : @"";

    NSString *udid = [self getUDID];
    NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
    NSString *deviceModel = [[UIDevice currentDevice] model];
    NSString *deviceName = [[UIDevice currentDevice] name];

    return @{
        @"IDFA":          idfa ?: @"",
        @"IDFV":          idfvStr ?: @"",
        @"UDID":          udid ?: @"",
        @"systemVersion": systemVersion ?: @"",
        @"deviceModel":   deviceModel ?: @"",
        @"deviceName":    deviceName ?: @"",
    };
}

@end
