//
//  KeychainManager.h
//  GhostKit
//
//  Keychain management: clean, deep-clean, backup, restore, list.
//

#import <Foundation/Foundation.h>

@interface KeychainManager : NSObject

+ (instancetype)sharedInstance;

/// Delete keychain items for the given bundle ID using the Security framework.
- (BOOL)cleanKeychainForBundleID:(NSString *)bundleID;

/// Deep-clean keychain items by directly operating on /var/Keychains/keychain-2.db.
- (BOOL)deepCleanKeychainForBundleID:(NSString *)bundleID;

/// Wipe every row from all keychain tables.
- (BOOL)deleteAllKeychains;

/// Restore previously backed-up keychain rows from a .db file.
- (BOOL)restoreKeychainFromBackup:(NSString *)backupPath;

/// Back up keychain rows whose access group matches bundleID to a .db file.
/// Returns the path to the backup file, or nil on failure.
- (NSString *)backupKeychainForBundleID:(NSString *)bundleID;

/// List keychain items (service / label / data length) whose access group matches bundleID.
- (NSArray<NSDictionary *> *)listKeychainItemsForBundleID:(NSString *)bundleID;

@end
