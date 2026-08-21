//
//  DarwinNotifyManager.m
//  GhostKit Tweak
//

#import "DarwinNotifyManager.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *const kGhostKitDir      = @"/var/mobile/Library/GhostKit";
static NSString *const kCommandFilePath  = @"/var/mobile/Library/GhostKit/command.plist";
static NSString *const kResultFilePath   = @"/var/mobile/Library/GhostKit/result.plist";

@implementation DarwinNotifyManager

+ (instancetype)sharedInstance {
    static DarwinNotifyManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DarwinNotifyManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSFileManager defaultManager] createDirectoryAtPath:kGhostKitDir
                      withIntermediateDirectories:YES
                                       attributes:nil
                                            error:nil];
    }
    return self;
}

#pragma mark - Send command (App → Tweak path)

- (nullable NSDictionary *)sendCommand:(DarwinCommand)command
                              params:(nullable NSDictionary *)params
                             timeout:(NSTimeInterval)timeout {
    // Remove stale result
    [[NSFileManager defaultManager] removeItemAtPath:kResultFilePath error:nil];

    // Write command
    NSMutableDictionary *cmd = [@{ @"command": @(command) } mutableCopy];
    if (params.count) cmd[@"params"] = params;
    [cmd writeToFile:kCommandFilePath atomically:YES];

    // Post Darwin notification
    NSString *notifName = [DarwinNotifyManager notificationNameForCommand:command];
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(center,
        (__bridge CFNotificationName)notifName, nil, nil, true);

    // Poll for result
    NSTimeInterval deadline = [[NSDate date] timeIntervalSinceReferenceDate] + timeout;
    while ([[NSDate date] timeIntervalSinceReferenceDate] < deadline) {
        NSDictionary *result = [NSDictionary dictionaryWithContentsOfFile:kResultFilePath];
        if (result) {
            NSNumber *rc = result[@"command"];
            if (rc && rc.integerValue == command) return result;
        }
        usleep(50000); // 50ms
    }
    NSLog(@"[GhostKit] Darwin notify timeout for command %ld", (long)command);
    return nil; // NSDictionary return type is OK
}

- (void)postNotification:(DarwinCommand)command params:(nullable NSDictionary *)params {
    NSMutableDictionary *cmd = [@{ @"command": @(command) } mutableCopy];
    if (params.count) cmd[@"params"] = params;
    [cmd writeToFile:kCommandFilePath atomically:YES];
    NSString *notifName = [DarwinNotifyManager notificationNameForCommand:command];
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterPostNotification(center,
        (__bridge CFNotificationName)notifName, nil, nil, true);
}

#pragma mark - Helpers

+ (DarwinCommand)commandFromString:(NSString *)name {
    if ([name isEqualToString:@"GhostKitCleanKeychain"])            return DarwinCommandCleanKeychain;
    if ([name isEqualToString:@"GhostKitDeepCleanKeychain"])        return DarwinCommandDeepCleanKeychain;
    if ([name isEqualToString:@"GhostKitDeleteAllKeychains"])       return DarwinCommandDeleteAllKeychains;
    if ([name isEqualToString:@"GhostKitBackupKeychain"])           return DarwinCommandBackupKeychain;
    if ([name isEqualToString:@"GhostKitRestoreKeychain"])          return DarwinCommandRestoreKeychain;
    if ([name isEqualToString:@"GhostKitListKeychain"])             return DarwinCommandListKeychain;
    if ([name isEqualToString:@"GhostKitRefreshIDFA"])              return DarwinCommandRefreshIDFA;
    if ([name isEqualToString:@"GhostKitChangeIdentifier"])         return DarwinCommandChangeIdentifier;
    if ([name isEqualToString:@"GhostKitGetCurrentIdentifiers"])    return DarwinCommandGetCurrentIdentifiers;
    if ([name isEqualToString:@"GhostKitResetDevice"])              return DarwinCommandResetDevice;
    if ([name isEqualToString:@"GhostKitGetDeviceInfo"])            return DarwinCommandGetDeviceInfo;
    if ([name isEqualToString:@"GhostKitCleanSystemResidue"])       return DarwinCommandCleanSystemResidue;
    if ([name isEqualToString:@"GhostKitCleanDatabaseCache"])       return DarwinCommandCleanDatabaseCache;
    if ([name isEqualToString:@"GhostKitCleanDataDirectory"])       return DarwinCommandCleanDataDirectory;
    if ([name isEqualToString:@"GhostKitCleanCookies"])             return DarwinCommandCleanCookies;
    if ([name isEqualToString:@"GhostKitCleanPasteboard"])          return DarwinCommandCleanPasteboard;
    if ([name isEqualToString:@"GhostKitGetAppSize"])               return DarwinCommandGetAppSize;
    if ([name isEqualToString:@"GhostKitGetAllApps"])               return DarwinCommandGetAllApps;
    if ([name isEqualToString:@"GhostKitSearchApps"])               return DarwinCommandSearchApps;
    if ([name isEqualToString:@"GhostKitUninstallApp"])             return DarwinCommandUninstallApp;
    if ([name isEqualToString:@"GhostKitGetAppInfo"])               return DarwinCommandGetAppInfo;
    if ([name isEqualToString:@"GhostKitGetAccountList"])           return DarwinCommandGetAccountList;
    if ([name isEqualToString:@"GhostKitAddAccount"])               return DarwinCommandAddAccount;
    if ([name isEqualToString:@"GhostKitDeleteAccount"])            return DarwinCommandDeleteAccount;
    if ([name isEqualToString:@"GhostKitGetCurrentAccount"])        return DarwinCommandGetCurrentAccount;
    if ([name isEqualToString:@"GhostKitSwitchAccount"])            return DarwinCommandSwitchAccount;
    if ([name isEqualToString:@"GhostKitAllowPasteForAll"])         return DarwinCommandAllowPasteForAll;
    if ([name isEqualToString:@"GhostKitIsPasteAllowed"])           return DarwinCommandIsPasteAllowed;
    if ([name isEqualToString:@"GhostKitSafeExit"])                 return DarwinCommandSafeExit;
    if ([name isEqualToString:@"GhostKitRespring"])                 return DarwinCommandRespring;
    if ([name isEqualToString:@"GhostKitLdrestart"])                return DarwinCommandLdrestart;
    if ([name isEqualToString:@"GhostKitInjectDylib"])              return DarwinCommandInjectDylib;
    if ([name isEqualToString:@"GhostKitRemoveDylib"])              return DarwinCommandRemoveDylib;
    if ([name isEqualToString:@"GhostKitGetInjectedDylibs"])        return DarwinCommandGetInjectedDylibs;
    if ([name isEqualToString:@"GhostKitApplyGraphicsConfig"])      return DarwinCommandApplyGraphicsConfig;
    if ([name isEqualToString:@"GhostKitGetAvailablePresets"])      return DarwinCommandGetAvailablePresets;
    if ([name isEqualToString:@"GhostKitGetCurrentGraphics"])       return DarwinCommandGetCurrentGraphics;
    if ([name isEqualToString:@"GhostKitRestoreDefaultGraphics"])   return DarwinCommandRestoreDefaultGraphics;
    if ([name isEqualToString:@"GhostKitShowSettings"])             return DarwinCommandShowSettings;
    return DarwinCommandUnknown;
}

+ (NSString *)notificationNameForCommand:(DarwinCommand)command {
    switch (command) {
        case DarwinCommandCleanKeychain:            return @"GhostKitCleanKeychain";
        case DarwinCommandDeepCleanKeychain:        return @"GhostKitDeepCleanKeychain";
        case DarwinCommandDeleteAllKeychains:       return @"GhostKitDeleteAllKeychains";
        case DarwinCommandBackupKeychain:           return @"GhostKitBackupKeychain";
        case DarwinCommandRestoreKeychain:          return @"GhostKitRestoreKeychain";
        case DarwinCommandListKeychain:             return @"GhostKitListKeychain";
        case DarwinCommandRefreshIDFA:              return @"GhostKitRefreshIDFA";
        case DarwinCommandChangeIdentifier:         return @"GhostKitChangeIdentifier";
        case DarwinCommandGetCurrentIdentifiers:    return @"GhostKitGetCurrentIdentifiers";
        case DarwinCommandResetDevice:              return @"GhostKitResetDevice";
        case DarwinCommandGetDeviceInfo:            return @"GhostKitGetDeviceInfo";
        case DarwinCommandCleanSystemResidue:       return @"GhostKitCleanSystemResidue";
        case DarwinCommandCleanDatabaseCache:       return @"GhostKitCleanDatabaseCache";
        case DarwinCommandCleanDataDirectory:       return @"GhostKitCleanDataDirectory";
        case DarwinCommandCleanCookies:             return @"GhostKitCleanCookies";
        case DarwinCommandCleanPasteboard:          return @"GhostKitCleanPasteboard";
        case DarwinCommandGetAppSize:               return @"GhostKitGetAppSize";
        case DarwinCommandGetAllApps:               return @"GhostKitGetAllApps";
        case DarwinCommandSearchApps:               return @"GhostKitSearchApps";
        case DarwinCommandUninstallApp:             return @"GhostKitUninstallApp";
        case DarwinCommandGetAppInfo:               return @"GhostKitGetAppInfo";
        case DarwinCommandGetAccountList:           return @"GhostKitGetAccountList";
        case DarwinCommandAddAccount:               return @"GhostKitAddAccount";
        case DarwinCommandDeleteAccount:            return @"GhostKitDeleteAccount";
        case DarwinCommandGetCurrentAccount:        return @"GhostKitGetCurrentAccount";
        case DarwinCommandSwitchAccount:            return @"GhostKitSwitchAccount";
        case DarwinCommandAllowPasteForAll:         return @"GhostKitAllowPasteForAll";
        case DarwinCommandIsPasteAllowed:           return @"GhostKitIsPasteAllowed";
        case DarwinCommandSafeExit:                 return @"GhostKitSafeExit";
        case DarwinCommandRespring:                 return @"GhostKitRespring";
        case DarwinCommandLdrestart:                return @"GhostKitLdrestart";
        case DarwinCommandInjectDylib:              return @"GhostKitInjectDylib";
        case DarwinCommandRemoveDylib:              return @"GhostKitRemoveDylib";
        case DarwinCommandGetInjectedDylibs:        return @"GhostKitGetInjectedDylibs";
        case DarwinCommandApplyGraphicsConfig:      return @"GhostKitApplyGraphicsConfig";
        case DarwinCommandGetAvailablePresets:      return @"GhostKitGetAvailablePresets";
        case DarwinCommandGetCurrentGraphics:       return @"GhostKitGetCurrentGraphics";
        case DarwinCommandRestoreDefaultGraphics:   return @"GhostKitRestoreDefaultGraphics";
        case DarwinCommandShowSettings:             return @"GhostKitShowSettings";
        default:                                    return @"GhostKitUnknown";
    }
}

@end
