//
//  Tweak.x
//  GhostKit
//
//  Logos Hook entry point. Hooks UIApplication to register
//  Darwin notification observers for all GhostKit commands.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "Modules/KeychainManager.h"
#import "Modules/IdentifierManager.h"
#import "Modules/DeviceResetManager.h"
#import "Modules/CacheCleaner.h"
#import "Modules/AppListManager.h"
#import "Modules/AccountManager.h"
#import "Modules/PermissionManager.h"
#import "Modules/SystemManager.h"
#import "Modules/InjectionManager.h"
#import "Modules/GraphicsConfigManager.h"

// ---------------------------------------------------------------------------
// Notification name constants
// ---------------------------------------------------------------------------

#define kGhostKitNotificationPrefix @"GhostKit"

static NSString *const kNotifCleanKeychain          = @"GhostKitCleanKeychain";
static NSString *const kNotifDeepCleanKeychain      = @"GhostKitDeepCleanKeychain";
static NSString *const kNotifDeleteAllKeychains     = @"GhostKitDeleteAllKeychains";
static NSString *const kNotifBackupKeychain         = @"GhostKitBackupKeychain";
static NSString *const kNotifRestoreKeychain        = @"GhostKitRestoreKeychain";
static NSString *const kNotifListKeychain           = @"GhostKitListKeychain";

static NSString *const kNotifRefreshIDFA            = @"GhostKitRefreshIDFA";
static NSString *const kNotifChangeIdentifier       = @"GhostKitChangeIdentifier";
static NSString *const kNotifGetCurrentIdentifiers  = @"GhostKitGetCurrentIdentifiers";

static NSString *const kNotifResetDevice            = @"GhostKitResetDevice";
static NSString *const kNotifGetDeviceInfo          = @"GhostKitGetDeviceInfo";

static NSString *const kNotifCleanSystemResidue     = @"GhostKitCleanSystemResidue";
static NSString *const kNotifCleanDatabaseCache     = @"GhostKitCleanDatabaseCache";
static NSString *const kNotifCleanDataDirectory     = @"GhostKitCleanDataDirectory";
static NSString *const kNotifCleanCookies           = @"GhostKitCleanCookies";
static NSString *const kNotifCleanPasteboard        = @"GhostKitCleanPasteboard";
static NSString *const kNotifGetAppSize             = @"GhostKitGetAppSize";

static NSString *const kNotifGetAllApps             = @"GhostKitGetAllApps";
static NSString *const kNotifSearchApps             = @"GhostKitSearchApps";
static NSString *const kNotifUninstallApp           = @"GhostKitUninstallApp";
static NSString *const kNotifGetAppInfo             = @"GhostKitGetAppInfo";

static NSString *const kNotifGetAccountList        = @"GhostKitGetAccountList";
static NSString *const kNotifAddAccount            = @"GhostKitAddAccount";
static NSString *const kNotifDeleteAccount         = @"GhostKitDeleteAccount";
static NSString *const kNotifGetCurrentAccount     = @"GhostKitGetCurrentAccount";
static NSString *const kNotifSwitchAccount          = @"GhostKitSwitchAccount";

static NSString *const kNotifAllowPasteForAll      = @"GhostKitAllowPasteForAll";
static NSString *const kNotifIsPasteAllowed        = @"GhostKitIsPasteAllowed";

static NSString *const kNotifSafeExit              = @"GhostKitSafeExit";
static NSString *const kNotifRespring               = @"GhostKitRespring";
static NSString *const kNotifLdrestart              = @"GhostKitLdrestart";

static NSString *const kNotifInjectDylib           = @"GhostKitInjectDylib";
static NSString *const kNotifRemoveDylib           = @"GhostKitRemoveDylib";
static NSString *const kNotifGetInjectedDylibs     = @"GhostKitGetInjectedDylibs";

static NSString *const kNotifApplyGraphicsConfig   = @"GhostKitApplyGraphicsConfig";
static NSString *const kNotifGetAvailablePresets   = @"GhostKitGetAvailablePresets";
static NSString *const kNotifGetCurrentGraphics    = @"GhostKitGetCurrentGraphics";
static NSString *const kNotifRestoreDefaultGraphics = @"GhostKitRestoreDefaultGraphics";

// ---------------------------------------------------------------------------
// GhostKitObserver - receives NSNotification posted from control UI
// ---------------------------------------------------------------------------

@interface GhostKitObserver : NSObject

+ (instancetype)sharedInstance;
- (void)registerObservers;
- (void)postResult:(id)result forCommand:(NSString *)command;

@end

@implementation GhostKitObserver

+ (instancetype)sharedInstance {
    static GhostKitObserver *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GhostKitObserver alloc] init];
    });
    return instance;
}

- (void)postResult:(id)result forCommand:(NSString *)command {
    NSDictionary *userInfo = result ? @{ @"result": result, @"command": command }
                                    : @{ @"command": command };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"GhostKitResult"
                                                        object:nil
                                                      userInfo:userInfo];
}

#pragma mark - Keychain handlers

- (void)handleCleanKeychain:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    BOOL ok = [[KeychainManager sharedInstance] cleanKeychainForBundleID:bundleID];
    [self postResult:@(ok) forCommand:kNotifCleanKeychain];
}

- (void)handleDeepCleanKeychain:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    BOOL ok = [[KeychainManager sharedInstance] deepCleanKeychainForBundleID:bundleID];
    [self postResult:@(ok) forCommand:kNotifDeepCleanKeychain];
}

- (void)handleDeleteAllKeychains:(NSNotification *)note {
    BOOL ok = [[KeychainManager sharedInstance] deleteAllKeychains];
    [self postResult:@(ok) forCommand:kNotifDeleteAllKeychains];
}

- (void)handleBackupKeychain:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    NSString *path = [[KeychainManager sharedInstance] backupKeychainForBundleID:bundleID];
    [self postResult:path ?: @"" forCommand:kNotifBackupKeychain];
}

- (void)handleRestoreKeychain:(NSNotification *)note {
    NSString *backupPath = note.userInfo[@"backupPath"];
    BOOL ok = [[KeychainManager sharedInstance] restoreKeychainFromBackup:backupPath];
    [self postResult:@(ok) forCommand:kNotifRestoreKeychain];
}

- (void)handleListKeychain:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    NSArray *items = [[KeychainManager sharedInstance] listKeychainItemsForBundleID:bundleID];
    [self postResult:items ?: @[] forCommand:kNotifListKeychain];
}

#pragma mark - Identifier handlers

- (void)handleRefreshIDFA:(NSNotification *)note {
    BOOL ok = [[IdentifierManager sharedInstance] refreshIDFA];
    [self postResult:@(ok) forCommand:kNotifRefreshIDFA];
}

- (void)handleChangeIdentifier:(NSNotification *)note {
    BOOL ok = [[IdentifierManager sharedInstance] changeIdentifier];
    [self postResult:@(ok) forCommand:kNotifChangeIdentifier];
}

- (void)handleGetCurrentIdentifiers:(NSNotification *)note {
    NSDictionary *ids = [[IdentifierManager sharedInstance] getCurrentIdentifiers];
    [self postResult:ids ?: @{} forCommand:kNotifGetCurrentIdentifiers];
}

#pragma mark - Device reset handlers

- (void)handleResetDevice:(NSNotification *)note {
    BOOL ok = [[DeviceResetManager sharedInstance] resetDevice];
    [self postResult:@(ok) forCommand:kNotifResetDevice];
}

- (void)handleGetDeviceInfo:(NSNotification *)note {
    NSDictionary *info = [[DeviceResetManager sharedInstance] getDeviceInfo];
    [self postResult:info ?: @{} forCommand:kNotifGetDeviceInfo];
}

#pragma mark - Cache cleaner handlers

- (void)handleCleanSystemResidue:(NSNotification *)note {
    BOOL ok = [[CacheCleaner sharedInstance] cleanSystemResidue];
    [self postResult:@(ok) forCommand:kNotifCleanSystemResidue];
}

- (void)handleCleanDatabaseCache:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    BOOL ok = [[CacheCleaner sharedInstance] cleanDatabaseCacheForBundleID:bundleID];
    [self postResult:@(ok) forCommand:kNotifCleanDatabaseCache];
}

- (void)handleCleanDataDirectory:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    BOOL ok = [[CacheCleaner sharedInstance] cleanDataDirectoryForBundleID:bundleID];
    [self postResult:@(ok) forCommand:kNotifCleanDataDirectory];
}

- (void)handleCleanCookies:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    BOOL ok = [[CacheCleaner sharedInstance] cleanCookiesForBundleID:bundleID];
    [self postResult:@(ok) forCommand:kNotifCleanCookies];
}

- (void)handleCleanPasteboard:(NSNotification *)note {
    BOOL ok = [[CacheCleaner sharedInstance] cleanPasteboard];
    [self postResult:@(ok) forCommand:kNotifCleanPasteboard];
}

- (void)handleGetAppSize:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    NSDictionary *size = [[CacheCleaner sharedInstance] getAppSizeForBundleID:bundleID];
    [self postResult:size ?: @{} forCommand:kNotifGetAppSize];
}

#pragma mark - App list handlers

- (void)handleGetAllApps:(NSNotification *)note {
    NSArray *apps = [[AppListManager sharedInstance] getAllInstalledApps];
    [self postResult:apps ?: @[] forCommand:kNotifGetAllApps];
}

- (void)handleSearchApps:(NSNotification *)note {
    NSString *keyword = note.userInfo[@"keyword"];
    NSArray *apps = [[AppListManager sharedInstance] searchApps:keyword];
    [self postResult:apps ?: @[] forCommand:kNotifSearchApps];
}

- (void)handleUninstallApp:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    BOOL ok = [[AppListManager sharedInstance] uninstallApp:bundleID];
    [self postResult:@(ok) forCommand:kNotifUninstallApp];
}

- (void)handleGetAppInfo:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    AppInfo *info = [[AppListManager sharedInstance] getAppInfoWithBundleID:bundleID];
    [self postResult:info ?: [NSNull null] forCommand:kNotifGetAppInfo];
}

#pragma mark - Account handlers

- (void)handleGetAccountList:(NSNotification *)note {
    NSArray *accounts = [[AccountManager sharedInstance] getAccountList];
    [self postResult:accounts ?: @[] forCommand:kNotifGetAccountList];
}

- (void)handleAddAccount:(NSNotification *)note {
    NSDictionary *dict = note.userInfo[@"account"];
    AppStoreAccount *account = [[AppStoreAccount alloc] init];
    account.appleID      = dict[@"appleID"];
    account.password     = dict[@"password"];
    account.countryCode  = dict[@"countryCode"];
    account.displayName  = dict[@"displayName"];
    BOOL ok = [[AccountManager sharedInstance] addAccount:account];
    [self postResult:@(ok) forCommand:kNotifAddAccount];
}

- (void)handleDeleteAccount:(NSNotification *)note {
    NSString *appleID = note.userInfo[@"appleID"];
    BOOL ok = [[AccountManager sharedInstance] deleteAccount:appleID];
    [self postResult:@(ok) forCommand:kNotifDeleteAccount];
}

- (void)handleGetCurrentAccount:(NSNotification *)note {
    AppStoreAccount *account = [[AccountManager sharedInstance] getCurrentAccount];
    [self postResult:account ?: [NSNull null] forCommand:kNotifGetCurrentAccount];
}

- (void)handleSwitchAccount:(NSNotification *)note {
    NSDictionary *dict = note.userInfo[@"account"];
    AppStoreAccount *account = [[AppStoreAccount alloc] init];
    account.appleID      = dict[@"appleID"];
    account.password     = dict[@"password"];
    account.countryCode  = dict[@"countryCode"];
    account.displayName  = dict[@"displayName"];
    BOOL ok = [[AccountManager sharedInstance] switchAccount:account];
    [self postResult:@(ok) forCommand:kNotifSwitchAccount];
}

#pragma mark - Permission handlers

- (void)handleAllowPasteForAll:(NSNotification *)note {
    BOOL ok = [[PermissionManager sharedInstance] allowPasteForAllApps];
    [self postResult:@(ok) forCommand:kNotifAllowPasteForAll];
}

- (void)handleIsPasteAllowed:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    BOOL ok = [[PermissionManager sharedInstance] isPasteAllowedForBundleID:bundleID];
    [self postResult:@(ok) forCommand:kNotifIsPasteAllowed];
}

#pragma mark - System handlers

- (void)handleSafeExit:(NSNotification *)note {
    [self postResult:@(YES) forCommand:kNotifSafeExit];
    [[SystemManager sharedInstance] safeExit];
}

- (void)handleRespring:(NSNotification *)note {
    [self postResult:@(YES) forCommand:kNotifRespring];
    [[SystemManager sharedInstance] respring];
}

- (void)handleLdrestart:(NSNotification *)note {
    [self postResult:@(YES) forCommand:kNotifLdrestart];
    [[SystemManager sharedInstance] ldrestart];
}

#pragma mark - Injection handlers

- (void)handleInjectDylib:(NSNotification *)note {
    NSString *dylibPath = note.userInfo[@"dylibPath"];
    NSString *bundleID  = note.userInfo[@"bundleID"];
    BOOL ok = [[InjectionManager sharedInstance] injectDylib:dylibPath forBundleID:bundleID];
    [self postResult:@(ok) forCommand:kNotifInjectDylib];
}

- (void)handleRemoveDylib:(NSNotification *)note {
    NSString *dylibPath = note.userInfo[@"dylibPath"];
    NSString *bundleID  = note.userInfo[@"bundleID"];
    BOOL ok = [[InjectionManager sharedInstance] removeDylib:dylibPath forBundleID:bundleID];
    [self postResult:@(ok) forCommand:kNotifRemoveDylib];
}

- (void)handleGetInjectedDylibs:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    NSArray *dylibs = [[InjectionManager sharedInstance] getInjectedDylibsForBundleID:bundleID];
    [self postResult:dylibs ?: @[] forCommand:kNotifGetInjectedDylibs];
}

#pragma mark - Graphics config handlers

- (void)handleApplyGraphicsConfig:(NSNotification *)note {
    NSString *preset   = note.userInfo[@"preset"];
    NSString *bundleID = note.userInfo[@"bundleID"];
    BOOL ok = [[GraphicsConfigManager sharedInstance] applyGraphicsConfig:preset forBundleID:bundleID];
    [self postResult:@(ok) forCommand:kNotifApplyGraphicsConfig];
}

- (void)handleGetAvailablePresets:(NSNotification *)note {
    NSArray *presets = [[GraphicsConfigManager sharedInstance] getAvailablePresets];
    [self postResult:presets ?: @[] forCommand:kNotifGetAvailablePresets];
}

- (void)handleGetCurrentGraphics:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    NSString *config = [[GraphicsConfigManager sharedInstance] getCurrentConfigForBundleID:bundleID];
    [self postResult:config ?: @"" forCommand:kNotifGetCurrentGraphics];
}

- (void)handleRestoreDefaultGraphics:(NSNotification *)note {
    NSString *bundleID = note.userInfo[@"bundleID"];
    BOOL ok = [[GraphicsConfigManager sharedInstance] restoreDefaultForBundleID:bundleID];
    [self postResult:@(ok) forCommand:kNotifRestoreDefaultGraphics];
}

#pragma mark - Registration

- (void)registerObservers {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    // Keychain
    [center addObserver:self selector:@selector(handleCleanKeychain:)         name:kNotifCleanKeychain       object:nil];
    [center addObserver:self selector:@selector(handleDeepCleanKeychain:)     name:kNotifDeepCleanKeychain   object:nil];
    [center addObserver:self selector:@selector(handleDeleteAllKeychains:)    name:kNotifDeleteAllKeychains  object:nil];
    [center addObserver:self selector:@selector(handleBackupKeychain:)       name:kNotifBackupKeychain      object:nil];
    [center addObserver:self selector:@selector(handleRestoreKeychain:)       name:kNotifRestoreKeychain     object:nil];
    [center addObserver:self selector:@selector(handleListKeychain:)          name:kNotifListKeychain        object:nil];

    // Identifier
    [center addObserver:self selector:@selector(handleRefreshIDFA:)           name:kNotifRefreshIDFA          object:nil];
    [center addObserver:self selector:@selector(handleChangeIdentifier:)      name:kNotifChangeIdentifier     object:nil];
    [center addObserver:self selector:@selector(handleGetCurrentIdentifiers:) name:kNotifGetCurrentIdentifiers object:nil];

    // Device reset
    [center addObserver:self selector:@selector(handleResetDevice:)           name:kNotifResetDevice         object:nil];
    [center addObserver:self selector:@selector(handleGetDeviceInfo:)         name:kNotifGetDeviceInfo       object:nil];

    // Cache cleaner
    [center addObserver:self selector:@selector(handleCleanSystemResidue:)    name:kNotifCleanSystemResidue  object:nil];
    [center addObserver:self selector:@selector(handleCleanDatabaseCache:)    name:kNotifCleanDatabaseCache  object:nil];
    [center addObserver:self selector:@selector(handleCleanDataDirectory:)    name:kNotifCleanDataDirectory  object:nil];
    [center addObserver:self selector:@selector(handleCleanCookies:)          name:kNotifCleanCookies        object:nil];
    [center addObserver:self selector:@selector(handleCleanPasteboard:)       name:kNotifCleanPasteboard     object:nil];
    [center addObserver:self selector:@selector(handleGetAppSize:)             name:kNotifGetAppSize          object:nil];

    // App list
    [center addObserver:self selector:@selector(handleGetAllApps:)            name:kNotifGetAllApps          object:nil];
    [center addObserver:self selector:@selector(handleSearchApps:)            name:kNotifSearchApps          object:nil];
    [center addObserver:self selector:@selector(handleUninstallApp:)           name:kNotifUninstallApp        object:nil];
    [center addObserver:self selector:@selector(handleGetAppInfo:)            name:kNotifGetAppInfo          object:nil];

    // Account
    [center addObserver:self selector:@selector(handleGetAccountList:)         name:kNotifGetAccountList      object:nil];
    [center addObserver:self selector:@selector(handleAddAccount:)            name:kNotifAddAccount          object:nil];
    [center addObserver:self selector:@selector(handleDeleteAccount:)         name:kNotifDeleteAccount       object:nil];
    [center addObserver:self selector:@selector(handleGetCurrentAccount:)     name:kNotifGetCurrentAccount   object:nil];
    [center addObserver:self selector:@selector(handleSwitchAccount:)          name:kNotifSwitchAccount        object:nil];

    // Permission
    [center addObserver:self selector:@selector(handleAllowPasteForAll:)      name:kNotifAllowPasteForAll    object:nil];
    [center addObserver:self selector:@selector(handleIsPasteAllowed:)        name:kNotifIsPasteAllowed      object:nil];

    // System
    [center addObserver:self selector:@selector(handleSafeExit:)               name:kNotifSafeExit            object:nil];
    [center addObserver:self selector:@selector(handleRespring:)              name:kNotifRespring             object:nil];
    [center addObserver:self selector:@selector(handleLdrestart:)             name:kNotifLdrestart           object:nil];

    // Injection
    [center addObserver:self selector:@selector(handleInjectDylib:)           name:kNotifInjectDylib         object:nil];
    [center addObserver:self selector:@selector(handleRemoveDylib:)           name:kNotifRemoveDylib         object:nil];
    [center addObserver:self selector:@selector(handleGetInjectedDylibs:)     name:kNotifGetInjectedDylibs   object:nil];

    // Graphics
    [center addObserver:self selector:@selector(handleApplyGraphicsConfig:)     name:kNotifApplyGraphicsConfig  object:nil];
    [center addObserver:self selector:@selector(handleGetAvailablePresets:)   name:kNotifGetAvailablePresets  object:nil];
    [center addObserver:self selector:@selector(handleGetCurrentGraphics:)    name:kNotifGetCurrentGraphics  object:nil];
    [center addObserver:self selector:@selector(handleRestoreDefaultGraphics:) name:kNotifRestoreDefaultGraphics object:nil];

    NSLog(@"[GhostKit] All notification observers registered");
}

@end

// ---------------------------------------------------------------------------
// Hook UIApplication - register observers on launch
// ---------------------------------------------------------------------------

%hook UIApplication

- (instancetype)init {
    self = %orig;
    if (self) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [[GhostKitObserver sharedInstance] registerObservers];
            NSLog(@"[GhostKit] Loaded into process: %@", [[NSBundle mainBundle] bundleIdentifier]);
        });
    }
    return self;
}

%end
