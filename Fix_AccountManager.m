//
//  AccountManager_fix.m
//  修复 App Store 账号切换逻辑
//  兼容 iOS 16+：清除 Keychain token 使 AppStore 重新登录
//

#import "AccountManager.h"
#import "SystemManager.h"
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <Security/Security.h>

extern char **environ;

static NSString *const kAccountListPlist = @"/var/mobile/Library/GhostKit/appstore_accounts.plist";
static NSString *const kAccountListDir   = @"/var/mobile/Library/GhostKit";

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
    if (!array) return [NSMutableArray array];
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
    if (!account.appleID || account.appleID.length == 0) return NO;
    NSMutableArray *accounts = [self loadAccountsArray];
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSDictionary *dict in accounts) {
        if (![[dict[@"appleID"] ?? @""] isEqualToString:account.appleID]) {
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
    if (!appleID || appleID.length == 0) return NO;
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
    // iOS 16+: 从 Keychain 读取当前 App Store 账号
    NSString *appleID = nil;
    NSString *displayName = nil;

    // 查询 com.apple.iTunesStore Keychain 条目
    CFDictionaryRef query = CFDictionaryCreate(NULL,
        (const void *[3]){kSecClass, kSecAttrService, kSecMatchLimit},
        (const void *[3]){kSecClassGenericPassword,
                          (__bridge CFStringRef)"com.apple.iTunesStore",
                          kSecMatchLimitOne},
        3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFTypeRef result = NULL;
    if (SecItemCopyMatching(query, &result) == errSecSuccess) {
        CFDictionaryRef dict = (__bridge CFDictionaryRef)result;
        appleID = CFBridgingRelease(CFDictionaryGetValue(dict, kSecAttrAccount));
        displayName = CFBridgingRelease(CFDictionaryGetValue(dict, kSecAttrService));
        CFRelease(result);
    }
    CFRelease(query);

    if (!appleID || ((NSString *)appleID).length == 0) {
        // Fallback: 读 plist（iOS 15 及以下）
        NSDictionary *appStorePrefs = [NSDictionary dictionaryWithContentsOfFile:
            @"/var/mobile/Library/Preferences/com.apple.AppStore.plist"];
        appleID = appStorePrefs[@"AppleID"];
        if (!appleID) appleID = appStorePrefs[@"SignedInAppleID"];
        displayName = appStorePrefs[@"AccountDisplayString"];
    }

    if (!appleID || ((NSString *)appleID).length == 0) return nil;

    AppStoreAccount *result = [[AppStoreAccount alloc] init];
    result.appleID     = appleID;
    result.displayName = displayName ?: appleID;

    for (AppStoreAccount *stored in [self getAccountList]) {
        if ([stored.appleID isEqualToString:appleID]) {
            result.password    = stored.password;
            result.countryCode  = stored.countryCode;
            break;
        }
    }
    return result;
}

#pragma mark - Switch account (iOS 16+ compatible)

- (BOOL)switchAccount:(AppStoreAccount *)account {
    if (!account.appleID || account.appleID.length == 0) return NO;

    // 1. 更新 plist（兼容 iOS 15 及以下）
    NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/com.apple.AppStore.plist"];
    if (existing) [prefs addEntriesFromDictionary:existing];
    prefs[@"AppleID"] = account.appleID;
    prefs[@"AccountDisplayString"] = account.displayName ?: account.appleID;
    if (account.countryCode.length > 0) prefs[@"StoreFront"] = account.countryCode;
    prefs[@"SignedInAppleID"] = account.appleID;
    BOOL ok = [prefs writeToFile:@"/var/mobile/Library/Preferences/com.apple.AppStore.plist"
                          atomically:YES];

    // 2. iOS 16+ 关键：清除 AppStore Keychain token
    //    删除 com.apple.iTunesStore 相关条目，让 AppStore 重新弹登录框
    NSArray *services = @[
        @"com.apple.iTunesStore",
        @"com.apple.account.AppleID",
        @"com.apple.appstore",
    ];
    for (NSString *service in services) {
        CFDictionaryRef query = CFDictionaryCreate(NULL,
            (const void *[3]){kSecClass, kSecAttrService, kSecMatchLimit},
            (const void *[3]){kSecClassGenericPassword,
                              (__bridge CFStringRef)service,
                              kSecMatchLimitAll},
            3, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        SecItemDelete(query);
        CFRelease(query);
    }

    // 3. 也删除 AppStore 的 preference 缓存（强制重新认证）
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:@"/var/mobile/Library/Caches/com.apple.appstore" error:nil];
    [fm removeItemAtPath:@"/var/mobile/Library/Caches/com.apple.itunescloudd" error:nil];

    // 4. kill AppStore 强制重启
    {
        pid_t pid;
        char *argv1[] = { "killall", "AppStore", NULL };
        posix_spawnp(&pid, "killall", NULL, NULL, argv1, environ);
        usleep(500000);
        char *argv2[] = { "killall", "-9", "AppStore", NULL };
        posix_spawnp(&pid, "killall", NULL, NULL, argv2, environ);
    }

    NSLog(@"[GhostKit] switchAccount to %@ -> %@", account.appleID, ok ? @"YES" : @"NO");
    return ok;
}

@end
