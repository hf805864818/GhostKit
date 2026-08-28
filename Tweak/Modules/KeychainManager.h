//
//  KeychainManager.h
//  GhostKit
//
//  Keychain management: clean, deep-clean, backup, restore, list.
//  All operations use the Security framework (SecItemDelete / SecItemCopyMatching /
//  SecItemAdd) instead of direct SQLite access to keychain-2.db, which works on
//  rootless jailbreaks and TrollStore without root privileges.
//

#import <Foundation/Foundation.h>

@interface KeychainManager : NSObject

+ (instancetype)sharedInstance;

/// Delete keychain items for the given bundle ID using the Security framework.
- (BOOL)cleanKeychainForBundleID:(NSString *)bundleID;

/// Deep-clean keychain items by access group, service, and account matching.
- (BOOL)deepCleanKeychainForBundleID:(NSString *)bundleID;

/// Wipe all keychain items (all classes, all apps).
- (BOOL)deleteAllKeychains;

/// Back up keychain items matching bundleID to a .plist file.
/// Returns the path to the backup file, or nil on failure.
- (NSString *)backupKeychainForBundleID:(NSString *)bundleID;

/// Restore previously backed-up keychain items from a .plist file.
- (BOOL)restoreKeychainFromBackup:(NSString *)backupPath;

/// List keychain items (class / access group / service / account) matching bundleID.
- (NSArray<NSDictionary *> *)listKeychainItemsForBundleID:(NSString *)bundleID;

@end
