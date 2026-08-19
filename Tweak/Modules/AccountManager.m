//
//  AccountManager.m
//  GhostKit
//

#import "AccountManager.h"
#import "SystemManager.h"
#import <UIKit/UIKit.h>
#import <stdlib.h>

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

#pragma mark - Get current account

- (AppStoreAccount *)getCurrentAccount {
    NSDictionary *appStorePrefs = [NSDictionary dictionaryWithContentsOfFile:kAppStorePrefsPath];

    NSString *appleID = appStorePrefs[@"AppleID"];
    NSString *displayName = appStorePrefs[@"AccountDisplayString"];

    if (!appleID || appleID.length == 0) {
        // Try the accounts plist.
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

    // Try to match with stored account to get password.
    AppStoreAccount *result = [[AppStoreAccount alloc] init];
    result.appleID     = appleID;
    result.displayName = displayName ?: appleID;

    // Look up stored account for password / country code.
    for (AppStoreAccount *stored in [self getAccountList]) {
        if ([stored.appleID isEqualToString:appleID]) {
            result.password    = stored.password;
            result.countryCode  = stored.countryCode;
            if (stored.displayName.length > 0) {
                result.displayName = stored.displayName;
            }
            break;
        }
    }

    return result;
}

#pragma mark - Switch account

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
    // Force the App Store to show the sign-in prompt with the new Apple ID.
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

    // 3. Clear the keychain Apple ID entry so the App Store re-authenticates.
    //    (This is handled by the keychain manager separately.)

    // 4. Kill the App Store process so it reloads preferences.
    system("killall AppStore 2>/dev/null");
    system("killall -9 AppStore 2>/dev/null");

    NSLog(@"[GhostKit] switchAccount to %@ -> %@", account.appleID, ok ? @"YES" : @"NO");
    return ok;
}

@end
