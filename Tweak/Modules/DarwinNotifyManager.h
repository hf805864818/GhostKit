//
//  DarwinNotifyManager.h
//  GhostKit Tweak
//
//  Cross-process communication via Darwin notifications.
//  The GhostKit App writes command.plist, posts a Darwin notification,
//  then polls result.plist for the response.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DarwinCommand) {
    DarwinCommandCleanKeychain,
    DarwinCommandDeepCleanKeychain,
    DarwinCommandDeleteAllKeychains,
    DarwinCommandBackupKeychain,
    DarwinCommandRestoreKeychain,
    DarwinCommandListKeychain,
    DarwinCommandRefreshIDFA,
    DarwinCommandChangeIdentifier,
    DarwinCommandGetCurrentIdentifiers,
    DarwinCommandResetDevice,
    DarwinCommandGetDeviceInfo,
    DarwinCommandCleanSystemResidue,
    DarwinCommandCleanDatabaseCache,
    DarwinCommandCleanDataDirectory,
    DarwinCommandCleanCookies,
    DarwinCommandCleanPasteboard,
    DarwinCommandGetAppSize,
    DarwinCommandGetAllApps,
    DarwinCommandSearchApps,
    DarwinCommandUninstallApp,
    DarwinCommandGetAppInfo,
    DarwinCommandGetAccountList,
    DarwinCommandAddAccount,
    DarwinCommandDeleteAccount,
    DarwinCommandGetCurrentAccount,
    DarwinCommandSwitchAccount,
    DarwinCommandAllowPasteForAll,
    DarwinCommandIsPasteAllowed,
    DarwinCommandSafeExit,
    DarwinCommandRespring,
    DarwinCommandLdrestart,
    DarwinCommandInjectDylib,
    DarwinCommandRemoveDylib,
    DarwinCommandGetInjectedDylibs,
    DarwinCommandApplyGraphicsConfig,
    DarwinCommandGetAvailablePresets,
    DarwinCommandGetCurrentGraphics,
    DarwinCommandRestoreDefaultGraphics,
    DarwinCommandShowSettings,
};

@interface DarwinNotifyManager : NSObject

+ (instancetype)sharedInstance;

/// Send a command to the Tweak layer (write plist → post Darwin notify → poll result).
- (nullable NSDictionary *)sendCommand:(DarwinCommand)command
                            params:(nullable NSDictionary *)params
                           timeout:(NSTimeInterval)timeout;

/// Fire-and-forget notification (no result expected).
- (void)postNotification:(DarwinCommand)command
                params:(nullable NSDictionary *)params;

/// Check if a Darwin command name corresponds to a known GhostKit command.
+ (nullable DarwinCommand)commandFromString:(NSString *)name;

/// Convert a command to its Darwin notification string.
+ (NSString *)notificationNameForCommand:(DarwinCommand)command;

@end

NS_ASSUME_NONNULL_END
