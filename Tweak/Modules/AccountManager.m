//
//  AccountManager.m
//  GhostKit
//

#import "AccountManager.h"
#import "SystemManager.h"
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <Security/Security.h>

extern char **environ;

static NSString *const kAccountListPlist = @"/var/mobile/Library/GhostKit/appstore_accounts.plist";
static NSString *const kAccountListDir   = @"/var/mobile/Library/GhostKit";

// App Store preferences path.
static NSString *const kAppStorePrefsPath =
    @"/var/mobile/Library/Preferences/com.apple.AppStore.plist";

// Account store preferences path.
static NSString *const kAccountStorePrefsPath =
    @"/var/mobile/Library/Preferences/com.apple.accounts.plist";

@implementation AppStoreAccount

- (NSDictionary *)toDictionary {
    return @{
        @"appleID":      self.appleID ?: @"",
        @"password":     self.password ?: @"",
        @"countryCode":  self.countryCode ?: @"",
        @"displayName":  self.displayName ?: @"",
    };
}

@end

@implementation AccountManager

+ (instancetype)sharedInstance {
    static AccountManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AccountManager alloc] init];
    });
    return instance;
}

#pragma mark - Plist I/O

- (NSMutableArray<NSDictionary *> *)loadAccountsArray {
    NSArray *array = [NSArray arrayWithContentsOfFile:kAccountListPlist];
    if (!array) {
        return [NSMutableArray array];
    }
    return [NSMutableArray arrayWithArray:array];
}

- (BOOL)saveAccountsArray:(NSArray *)array {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:kAccountListDir
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
    return [array writeToFile:kAccountListPlist atomically:YES];
}

#pragma mark - Get account list

- (NSArray<AppStoreAccount *> *)getAccountList {
    NSArray *rawArray = [self loadAccountsArray];
    NSMutableArray *result = [NSMutableArray array];

    for (NSDictionary *dict in rawArray) {
        AppStoreAccount *account = [[AppStoreAccount alloc] init];
        account.appleID      = dict[@"appleID"];
        account.password     = dict[@"password"];
        account.countryCode  = dict[@"countryCode"];
        account.displayName  = dict[@"displayName"];
        [result addObject:account];
    }

    return result;
}

#pragma mark - Add account

- (BOOL)addAccount:(AppStoreAccount *)account {
    if (!account.appleID || account.appleID.length == 0) {
        return NO;
    }

    NSMutableArray *accounts = [self loadAccountsArray];

    // Remove existing entry with the same Apple ID (update).
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *dict in accounts) {
        NSString *existingID = dict[@"appleID"];
        if (![existingID isEqualToString:account.appleID]) {
            [filtered addObject:dict];
        }
    }

    [filtered addObject:[account toDictionary]];
    BOOL ok = [self saveAccountsArray:filtered];

    NSLog(@"[GhostKit] addAccount:%@ -> %@", account.appleID, ok ? @"YES" : @"NO");
    return ok;
}

#pragma mark - Delete account

- (BOOL)deleteAccount:(NSString *)appleID {
    if (!appleID || appleID.length == 0) {
        return NO;
    }

    NSMutableArray *accounts = [self loadAccountsArray];
    NSMutableArray *filtered = [NSMutableArray array];
    BOOL found = NO;

    for (NSDictionary *dict in accounts) {
        if ([dict[@"appleID"] isEqualToString:appleID]) {
            found = YES;
        } else {
            [filtered addObject:dict];
        }
    }

    if (!found) {
        NSLog(@"[GhostKit] deleteAccount: %@ not found", appleID);
        return NO;
    }

    BOOL ok = [self saveAccountsArray:filtered];
    NSLog(@"[GhostKit] deleteAccount:%@ -> %@", appleID, ok ? @"YES" : @"NO");
    return ok;
}

#pragma mark - Get current account (FIXED for iOS 16+)

- (AppStoreAccount *)getCurrentAccount {
    // Method 1: Try Keychain first (most reliable on iOS 16+)
    AppStoreAccount *result = [[AppStoreAccount alloc] init];
    
    // Query iTunes Store account from Keychain
    NSDictionary *itunesQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"com.apple.iTunesStore",
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
        (__bridge id)kSecReturnAttributes: @YES,
    };
    
    CFTypeRef resultRef = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)itunesQuery, &resultRef);
    
    if (status == errSecSuccess && resultRef) {
        NSDictionary *item = (__bridge NSDictionary *)resultRef;
        NSString *appleID = item[(__bridge id)kSecAttrAccount];
        if (appleID && appleID.length > 0) {
            result.appleID = appleID;
            result.displayName = appleID;
            NSLog(@"[GhostKit] getCurrentAccount from Keychain: %@", appleID);
            
            // Look up stored account for password/country
            for (AppStoreAccount *stored in [self getAccountList]) {
                if ([stored.appleID isEqualToString:appleID]) {
                    result.password = stored.password;
                    result.countryCode = stored.countryCode;
                    if (stored.displayName.length > 0) {
                        result.displayName = stored.displayName;
                    }
                    break;
                }
            }
            return result;
        }
        CFRelease(resultRef);
    }
    
    // Method 2: Try AppStore plist
    NSDictionary *appStorePrefs = [NSDictionary dictionaryWithContentsOfFile:kAppStorePrefsPath];
    NSString *appleID = appStorePrefs[@"AppleID"];
    NSString *displayName = appStorePrefs[@"AccountDisplayString"];
    
    if (!appleID || appleID.length == 0) {
        appleID = appStorePrefs[@"SignedInAppleID"];
    }
    
    if (!appleID || appleID.length == 0) {
        // Method 3: Try accounts plist
        NSDictionary *accountsPrefs = [NSDictionary dictionaryWithContentsOfFile:kAccountStorePrefsPath];
        NSDictionary *accountInfo = accountsPrefs[@"Accounts"];
        if (accountInfo) {
            for (NSString *key in accountInfo) {
                NSDictionary *info = accountInfo[key];
                if ([info[@"AccountType"] isEqualToString:@"iTunesStore"] ||
                    [info[@"AccountType"] containsString:@"AppleID"]) {
                    appleID = info[@"AccountID"] ?: info[@"AppleID"];
                    displayName = info[@"DisplayName"];
                    break;
                }
            }
        }
    }
    
    if (!appleID || appleID.length == 0) {
        return nil;
    }
    
    result.appleID = appleID;
    result.displayName = displayName ?: appleID;
    
    // Look up stored account for password/country
    for (AppStoreAccount *stored in [self getAccountList]) {
        if ([stored.appleID isEqualToString:appleID]) {
            result.password = stored.password;
            result.countryCode = stored.countryCode;
            if (stored.displayName.length > 0) {
                result.displayName = stored.displayName;
            }
            break;
        }
    }
    
    return result;
}

#pragma mark - Switch account (FIXED for iOS 16+)

- (BOOL)switchAccount:(AppStoreAccount *)account {
    if (!account.appleID || account.appleID.length == 0) {
        return NO;
    }

    // 1. Update the App Store preferences.
    NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:kAppStorePrefsPath];
    if (existing) {
        [prefs addEntriesFromDictionary:existing];
    }

    prefs[@"AppleID"]              = account.appleID;
    prefs[@"AccountDisplayString"] = account.displayName ?: account.appleID;
    if (account.countryCode.length > 0) {
        prefs[@"StoreFront"]       = account.countryCode;
    }
    prefs[@"SignedInAppleID"]      = account.appleID;

    BOOL ok = [prefs writeToFile:kAppStorePrefsPath atomically:YES];

    // 2. Also update the account store preferences if possible.
    NSMutableDictionary *accountStorePrefs = [NSMutableDictionary dictionary];
    NSDictionary *existingStore = [NSDictionary dictionaryWithContentsOfFile:kAccountStorePrefsPath];
    if (existingStore) {
        [accountStorePrefs addEntriesFromDictionary:existingStore];
    }

    NSMutableDictionary *accounts = [NSMutableDictionary dictionary];
    if (accountStorePrefs[@"Accounts"]) {
        [accounts addEntriesFromDictionary:accountStorePrefs[@"Accounts"]];
    }
    accounts[account.appleID] = @{
        @"AppleID":      account.appleID,
        @"DisplayName":  account.displayName ?: account.appleID,
        @"AccountType":  @"iTunesStore",
    };
    accountStorePrefs[@"Accounts"] = accounts;
    [accountStorePrefs writeToFile:kAccountStorePrefsPath atomically:YES];

    // 3. CRITICAL: Clear the Keychain Apple ID entry so AppStore re-authenticates
    // This is the key fix for iOS 16+ where plist changes are ignored
    NSDictionary *deleteQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"com.apple.iTunesStore",
    };
    SecItemDelete((__bridge CFDictionaryRef)deleteQuery);
    
    // Also delete any AppleID-specific entries
    NSDictionary *deleteQuery2 = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"com.apple.account.AppleID",
    };
    SecItemDelete((__bridge CFDictionaryRef)deleteQuery2);

    // 4. Clear AppStore cache to force re-authentication
    NSString *cachePath = @"/var/mobile/Library/Caches/com.apple.appstore";
    [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
    
    NSString *adCachePath = @"/var/mobile/Library/Caches/adid.plist";
    [[NSFileManager defaultManager] removeItemAtPath:adCachePath error:nil];

    // 5. Kill the App Store process so it reloads preferences.
    pid_t pid = 0;
    char *argv1[] = { "killall", "AppStore", NULL };
    posix_spawnp(&pid, "killall", NULL, NULL, argv1, environ);

    // Give it a moment, then force kill if still running
    usleep(500000); // 0.5 seconds
    char *argv2[] = { "killall", "-9", "AppStore", NULL };
    posix_spawnp(&pid, "killall", NULL, NULL, argv2, environ);

    NSLog(@"[GhostKit] switchAccount to %@ -> Keychain cleared + AppStore killed", account.appleID);
    return ok;
}

@end
