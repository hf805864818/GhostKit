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
#import <sqlite3.h>

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
    NSArray *accessGroups = @[
        @"com.apple.adid",
        @"com.apple.identifieradvertising",
    ];
    for (NSString *group in accessGroups) {
        [[KeychainManager sharedInstance] cleanKeychainForBundleID:group];
    }

    // 2. Direct DB deletion for the known access groups.
    for (NSString *group in accessGroups) {
        [[KeychainManager sharedInstance] deepCleanKeychainForBundleID:group];
    }

    // 3. Also delete by the well-known service name used by older iOS versions.
    sqlite3 *db = NULL;
    if (sqlite3_open_v2("/var/Keychains/keychain-2.db", &db,
                        SQLITE_OPEN_READWRITE, NULL) == SQLITE_OK) {

        const char *services[] = {
            "com.apple.adid",
            "adid",
            "com.apple.identifieradvertising",
            NULL,
        };

        NSArray *tables = @[@"genp", @"inet"];
        for (NSString *table in tables) {
            for (int i = 0; services[i] != NULL; i++) {
                NSString *sql = [NSString stringWithFormat:
                    @"DELETE FROM %@ WHERE srv = ? OR agrp = ?;", table];
                sqlite3_stmt *stmt = NULL;
                if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
                    sqlite3_bind_text(stmt, 1, services[i], -1, SQLITE_TRANSIENT);
                    sqlite3_bind_text(stmt, 2, services[i], -1, SQLITE_TRANSIENT);
                    sqlite3_step(stmt);
                    sqlite3_finalize(stmt);
                }
            }
        }

        sqlite3_close(db);
    }

    // 4. Clear the advertising identifier cache plist.
    NSString *cachePlist = @"/var/mobile/Library/Preferences/com.apple.adid.plist";
    [[NSFileManager defaultManager] removeItemAtPath:cachePlist error:nil];

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
