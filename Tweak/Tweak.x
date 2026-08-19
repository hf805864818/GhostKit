//
//  Tweak.x
//  GhostKit
//
//  Logos Hook entry point. Hooks UIApplication to register
//  Darwin notification observers for all GhostKit commands.
//
//  Uses CFNotificationCenterGetDarwinNotifyCenter() for cross-process
//  communication.  Darwin notifications cannot carry userInfo, so
//  command parameters are passed via a shared plist file and results
//  are written back to another shared file.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

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
// Shared file paths for cross-process parameter / result passing
// ---------------------------------------------------------------------------

static NSString *const kGhostKitDir       = @"/var/mobile/Library/GhostKit";
static NSString *const kCommandFilePath  = @"/var/mobile/Library/GhostKit/command.plist";
static NSString *const kResultFilePath    = @"/var/mobile/Library/GhostKit/result.plist";

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
// GhostKitObserver - receives Darwin notifications and dispatches to handlers
// ---------------------------------------------------------------------------

@interface GhostKitObserver : NSObject

+ (instancetype)sharedInstance;
- (void)registerObservers;
- (void)postResult:(id)result forCommand:(NSString *)command;

@end

// ---------------------------------------------------------------------------
// C callback for Darwin notification center.
// Darwin notifications cannot carry userInfo, so we read command parameters
// from a shared plist file, create a synthetic NSNotification, and dispatch
// to the appropriate ObjC handler method.
// ---------------------------------------------------------------------------

static void ghostkit_darwin_callback(CFNotificationCenterRef center,
                                      const void *observer,
                                      CFStringRef name,
                                      const void *object,
                                      CFDictionaryRef userInfo)
{
    if (!observer || !name) return;

    GhostKitObserver *obs = (__bridge GhostKitObserver *)observer;
    NSString *notifName = (__bridge NSString *)name;

    // Read command parameters from the shared file.
    NSDictionary *params = [NSDictionary dictionaryWithContentsOfFile:kCommandFilePath];

    // Build a synthetic NSNotification so existing handlers work unchanged.
    NSNotification *note = [NSNotification notificationWithName:notifName
                                                          object:nil
                                                        userInfo:params];

    // Map notification name → handler selector.
    static NSDictionary<NSString *, NSString *> *handlerMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handlerMap = @{
            kNotifCleanKeychain:           NSStringFromSelector(@selector(handleCleanKeychain:)),
            kNotifDeepCleanKeychain:       NSStringFromSelector(@selector(handleDeepCleanKeychain:)),
            kNotifDeleteAllKeychains:      NSStringFromSelector(@selector(handleDeleteAllKeychains:)),
            kNotifBackupKeychain:          NSStringFromSelector(@selector(handleBackupKeychain:)),
            kNotifRestoreKeychain:         NSStringFromSelector(@selector(handleRestoreKeychain:)),
            kNotifListKeychain:            NSStringFromSelector(@selector(handleListKeychain:)),

            kNotifRefreshIDFA:             NSStringFromSelector(@selector(handleRefreshIDFA:)),
            kNotifChangeIdentifier:        NSStringFromSelector(@selector(handleChangeIdentifier:)),
            kNotifGetCurrentIdentifiers:   NSStringFromSelector(@selector(handleGetCurrentIdentifiers:)),

            kNotifResetDevice:             NSStringFromSelector(@selector(handleResetDevice:)),
            kNotifGetDeviceInfo:           NSStringFromSelector(@selector(handleGetDeviceInfo:)),

            kNotifCleanSystemResidue:      NSStringFromSelector(@selector(handleCleanSystemResidue:)),
            kNotifCleanDatabaseCache:      NSStringFromSelector(@selector(handleCleanDatabaseCache:)),
            kNotifCleanDataDirectory:      NSStringFromSelector(@selector(handleCleanDataDirectory:)),
            kNotifCleanCookies:            NSStringFromSelector(@selector(handleCleanCookies:)),
            kNotifCleanPasteboard:         NSStringFromSelector(@selector(handleCleanPasteboard:)),
            kNotifGetAppSize:              NSStringFromSelector(@selector(handleGetAppSize:)),

            kNotifGetAllApps:              NSStringFromSelector(@selector(handleGetAllApps:)),
            kNotifSearchApps:              NSStringFromSelector(@selector(handleSearchApps:)),
            kNotifUninstallApp:            NSStringFromSelector(@selector(handleUninstallApp:)),
            kNotifGetAppInfo:              NSStringFromSelector(@selector(handleGetAppInfo:)),

            kNotifGetAccountList:          NSStringFromSelector(@selector(handleGetAccountList:)),
            kNotifAddAccount:              NSStringFromSelector(@selector(handleAddAccount:)),
            kNotifDeleteAccount:           NSStringFromSelector(@selector(handleDeleteAccount:)),
            kNotifGetCurrentAccount:       NSStringFromSelector(@selector(handleGetCurrentAccount:)),
            kNotifSwitchAccount:           NSStringFromSelector(@selector(handleSwitchAccount:)),

            kNotifAllowPasteForAll:        NSStringFromSelector(@selector(handleAllowPasteForAll:)),
            kNotifIsPasteAllowed:          NSStringFromSelector(@selector(handleIsPasteAllowed:)),

            kNotifSafeExit:                NSStringFromSelector(@selector(handleSafeExit:)),
            kNotifRespring:                NSStringFromSelector(@selector(handleRespring:)),
            kNotifLdrestart:               NSStringFromSelector(@selector(handleLdrestart:)),

            kNotifInjectDylib:             NSStringFromSelector(@selector(handleInjectDylib:)),
            kNotifRemoveDylib:             NSStringFromSelector(@selector(handleRemoveDylib:)),
            kNotifGetInjectedDylibs:       NSStringFromSelector(@selector(handleGetInjectedDylibs:)),

            kNotifApplyGraphicsConfig:     NSStringFromSelector(@selector(handleApplyGraphicsConfig:)),
            kNotifGetAvailablePresets:     NSStringFromSelector(@selector(handleGetAvailablePresets:)),
            kNotifGetCurrentGraphics:      NSStringFromSelector(@selector(handleGetCurrentGraphics:)),
            kNotifRestoreDefaultGraphics:  NSStringFromSelector(@selector(handleRestoreDefaultGraphics:)),
        };
    });

    NSString *selStr = handlerMap[notifName];
    if (selStr) {
        SEL sel = NSSelectorFromString(selStr);
        if ([obs respondsToSelector:sel]) {
            ((void(*)(id, SEL, id))objc_msgSend)(obs, sel, note);
        }
    }
}

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
    /*
     * Write the result to a shared plist file so the App process can
     * read it.  Non-plist-serializable objects (AppInfo, AppStoreAccount)
     * are converted to dictionaries before writing.
     */
    NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
    resultDict[@"command"] = command;
    resultDict[@"timestamp"] = [NSDate date].description;

    if (result && result != [NSNull null]) {
        id serializable = result;

        // Convert AppInfo to dictionary.
        if ([result isKindOfClass:[AppInfo class]]) {
            AppInfo *info = (AppInfo *)result;
            serializable = @{
                @"bundleID":   info.bundleID ?: @"",
                @"name":       info.name ?: @"",
                @"version":    info.version ?: @"",
                @"iconPath":   info.iconPath ?: @"",
                @"dataPath":   info.dataPath ?: @"",
                @"bundlePath": info.bundlePath ?: @"",
            };
        }
        // Convert AppStoreAccount to dictionary.
        else if ([result isKindOfClass:[AppStoreAccount class]]) {
            serializable = [result toDictionary];
        }
        // Arrays may contain AppInfo/AppStoreAccount objects.
        else if ([result isKindOfClass:[NSArray class]]) {
            NSMutableArray *arr = [NSMutableArray array];
            for (id item in (NSArray *)result) {
                if ([item isKindOfClass:[AppInfo class]]) {
                    AppInfo *info = (AppInfo *)item;
                    [arr addObject:@{
                        @"bundleID":   info.bundleID ?: @"",
                        @"name":       info.name ?: @"",
                        @"version":    info.version ?: @"",
                        @"iconPath":   info.iconPath ?: @"",
                        @"dataPath":   info.dataPath ?: @"",
                        @"bundlePath": info.bundlePath ?: @"",
                    }];
                } else if ([item isKindOfClass:[AppStoreAccount class]]) {
                    [arr addObject:[item toDictionary]];
                } else if ([item isKindOfClass:[NSNumber class]] ||
                           [item isKindOfClass:[NSString class]] ||
                           [item isKindOfClass:[NSDictionary class]]) {
                    [arr addObject:item];
                }
            }
            serializable = arr;
        }

        // Only write if the object is plist-serializable.
        if ([serializable isKindOfClass:[NSNumber class]] ||
            [serializable isKindOfClass:[NSString class]] ||
            [serializable isKindOfClass:[NSArray class]] ||
            [serializable isKindOfClass:[NSDictionary class]] ||
            [serializable isKindOfClass:[NSData class]]) {
            resultDict[@"result"] = serializable;
        } else {
            resultDict[@"result"] = [NSString stringWithFormat:@"%@", serializable];
        }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:kGhostKitDir
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
    [resultDict writeToFile:kResultFilePath atomically:YES];
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

#pragma mark - Registration (Darwin notification center)

- (void)registerObservers {
    /*
     * Use CFNotificationCenterGetDarwinNotifyCenter() for cross-process
     * communication.  Darwin notifications work between the GhostKit App
     * process and any process into which the Tweak is injected.
     *
     * Parameters are passed via a shared plist file because Darwin
     * notifications cannot carry userInfo dictionaries.
     */
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();

    NSArray<NSString *> *allNames = @[
        // Keychain
        kNotifCleanKeychain, kNotifDeepCleanKeychain, kNotifDeleteAllKeychains,
        kNotifBackupKeychain, kNotifRestoreKeychain, kNotifListKeychain,
        // Identifier
        kNotifRefreshIDFA, kNotifChangeIdentifier, kNotifGetCurrentIdentifiers,
        // Device reset
        kNotifResetDevice, kNotifGetDeviceInfo,
        // Cache cleaner
        kNotifCleanSystemResidue, kNotifCleanDatabaseCache, kNotifCleanDataDirectory,
        kNotifCleanCookies, kNotifCleanPasteboard, kNotifGetAppSize,
        // App list
        kNotifGetAllApps, kNotifSearchApps, kNotifUninstallApp, kNotifGetAppInfo,
        // Account
        kNotifGetAccountList, kNotifAddAccount, kNotifDeleteAccount,
        kNotifGetCurrentAccount, kNotifSwitchAccount,
        // Permission
        kNotifAllowPasteForAll, kNotifIsPasteAllowed,
        // System
        kNotifSafeExit, kNotifRespring, kNotifLdrestart,
        // Injection
        kNotifInjectDylib, kNotifRemoveDylib, kNotifGetInjectedDylibs,
        // Graphics
        kNotifApplyGraphicsConfig, kNotifGetAvailablePresets,
        kNotifGetCurrentGraphics, kNotifRestoreDefaultGraphics,
    ];

    for (NSString *name in allNames) {
        CFNotificationCenterAddObserver(center,
            (__bridge const void *)self,
            ghostkit_darwin_callback,
            (__bridge CFStringRef)name,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }

    NSLog(@"[GhostKit] All Darwin notification observers registered (%lu)",
          (unsigned long)allNames.count);
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
