//
//  KeychainManager.m
//  GhostKit
//
//  Implements keychain cleaning via the Security framework (SecItemDelete,
//  SecItemCopyMatching, SecItemAdd).  All operations use the Security
//  framework instead of direct SQLite access to keychain-2.db, which
//  requires no root privileges and works on rootless jailbreaks / TrollStore.
//

#import "KeychainManager.h"
#import <Security/Security.h>

static NSString *const kBackupDir = @"/var/mobile/Library/GhostKit/Backups";

@implementation KeychainManager

+ (instancetype)sharedInstance {
    static KeychainManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[KeychainManager alloc] init];
    });
    return instance;
}

#pragma mark - Security framework helpers

/// All keychain item classes we iterate over.
+ (NSArray *)allSecClasses {
    return @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassIdentity,
    ];
}

/// Query all items of a given class, returning their attributes.
+ (NSArray *)queryAllItemsOfClass:(id)secClass {
    NSDictionary *query = @{
        (__bridge id)kSecClass:           secClass,
        (__bridge id)kSecMatchLimit:      (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecReturnAttributes: @YES,
    };
    CFArrayRef results = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&results);
    if (status == errSecSuccess && results != NULL) {
        NSArray *arr = (__bridge_transfer NSArray *)results;
        return arr;
    }
    if (results) CFRelease(results);
    return @[];
}

/// Check if an access group string contains or matches the bundle ID.
+ (BOOL)accessGroup:(NSString *)agrp matchesBundleID:(NSString *)bundleID {
    if (!agrp || !bundleID) return NO;
    if ([agrp isEqualToString:bundleID]) return YES;
    if ([agrp containsString:bundleID]) return YES;
    if ([bundleID containsString:agrp]) return YES;
    return NO;
}

#pragma mark - Security framework clean

- (BOOL)cleanKeychainForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) {
        return NO;
    }

    NSArray *secClasses = [KeychainManager allSecClasses];
    BOOL anyDeleted = NO;

    for (id secClass in secClasses) {
        // Strategy 1: Delete by access group (exact match).
        NSDictionary *groupQuery = @{
            (__bridge id)kSecClass:            secClass,
            (__bridge id)kSecAttrAccessGroup:  bundleID,
            (__bridge id)kSecMatchLimit:       (__bridge id)kSecMatchLimitAll,
        };
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)groupQuery);
        if (status == errSecSuccess) {
            anyDeleted = YES;
        }

        // Strategy 2: Delete by service attribute.
        NSDictionary *serviceQuery = @{
            (__bridge id)kSecClass:       secClass,
            (__bridge id)kSecAttrService: bundleID,
            (__bridge id)kSecMatchLimit:  (__bridge id)kSecMatchLimitAll,
        };
        status = SecItemDelete((__bridge CFDictionaryRef)serviceQuery);
        if (status == errSecSuccess) {
            anyDeleted = YES;
        }

        // Strategy 3: Query all items, find ones whose access group contains
        // the bundle ID, and delete them individually.  This catches items
        // where the access group is "TeamID.bundleID" format.
        NSArray *allItems = [KeychainManager queryAllItemsOfClass:secClass];
        for (NSDictionary *item in allItems) {
            NSString *agrp = item[(__bridge id)kSecAttrAccessGroup];
            if ([KeychainManager accessGroup:agrp matchesBundleID:bundleID]) {
                // Build a delete query with the item's identifying attributes.
                NSMutableDictionary *delQuery = [NSMutableDictionary dictionary];
                delQuery[(__bridge id)kSecClass] = secClass;
                if (agrp) delQuery[(__bridge id)kSecAttrAccessGroup] = agrp;

                NSString *acct = item[(__bridge id)kSecAttrAccount];
                if (acct) delQuery[(__bridge id)kSecAttrAccount] = acct;

                NSString *svce = item[(__bridge id)kSecAttrService];
                if (svce) delQuery[(__bridge id)kSecAttrService] = svce;

                OSStatus delStatus = SecItemDelete((__bridge CFDictionaryRef)delQuery);
                if (delStatus == errSecSuccess) {
                    anyDeleted = YES;
                }
            }
        }
    }

    NSLog(@"[GhostKit] cleanKeychainForBundleID:%@ -> %@", bundleID, anyDeleted ? @"YES" : @"NO");
    return anyDeleted;
}

#pragma mark - Deep clean (Security framework)

- (BOOL)deepCleanKeychainForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) {
        return NO;
    }

    // First do the standard clean.
    BOOL ok = [self cleanKeychainForBundleID:bundleID];

    // Also delete items where the account name contains the bundle ID.
    NSArray *secClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
    ];

    for (id secClass in secClasses) {
        // Delete by account attribute.
        NSDictionary *acctQuery = @{
            (__bridge id)kSecClass:      secClass,
            (__bridge id)kSecAttrAccount: bundleID,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        };
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)acctQuery);
        if (status == errSecSuccess) {
            ok = YES;
        }

        // Delete by service attribute (broader match).
        NSDictionary *svcQuery = @{
            (__bridge id)kSecClass:      secClass,
            (__bridge id)kSecAttrService: bundleID,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        };
        status = SecItemDelete((__bridge CFDictionaryRef)svcQuery);
        if (status == errSecSuccess) {
            ok = YES;
        }
    }

    NSLog(@"[GhostKit] deepCleanKeychainForBundleID:%@ -> %@", bundleID, ok ? @"YES" : @"NO");
    return ok;
}

#pragma mark - Delete all (Security framework)

- (BOOL)deleteAllKeychains {
    NSArray *secClasses = [KeychainManager allSecClasses];
    BOOL anyDeleted = NO;

    for (id secClass in secClasses) {
        // Deleting with just the class and no other attributes removes ALL
        // items of that class from the keychain.
        NSDictionary *query = @{
            (__bridge id)kSecClass: secClass,
        };
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecSuccess) {
            anyDeleted = YES;
            NSLog(@"[GhostKit] Deleted all items of class %@", secClass);
        }
    }

    NSLog(@"[GhostKit] deleteAllKeychains -> %@", anyDeleted ? @"YES" : @"NO");
    return anyDeleted;
}

#pragma mark - Backup (Security framework)

- (NSString *)backupKeychainForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) {
        return nil;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:kBackupDir
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

    NSString *timestamp = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *backupPath = [kBackupDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"keychain_%@_%@.plist", bundleID, timestamp]];

    NSMutableArray *backupItems = [NSMutableArray array];
    NSArray *secClasses = [KeychainManager allSecClasses];

    for (id secClass in secClasses) {
        // Query all items of this class with both attributes and data.
        NSDictionary *query = @{
            (__bridge id)kSecClass:            secClass,
            (__bridge id)kSecMatchLimit:        (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnAttributes:  @YES,
            (__bridge id)kSecReturnData:        @YES,
        };
        CFArrayRef results = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&results);
        if (status == errSecSuccess && results != NULL) {
            NSArray *items = (__bridge_transfer NSArray *)results;
            for (NSDictionary *item in items) {
                NSString *agrp = item[(__bridge id)kSecAttrAccessGroup];
                if ([KeychainManager accessGroup:agrp matchesBundleID:bundleID]) {
                    // Serialize the item for backup.
                    NSMutableDictionary *serialized = [item mutableCopy];
                    // Store the class string for later restoration.
                    serialized[@"__secClass"] = [NSString stringWithFormat:@"%lu", (unsigned long)[secClass hash]];
                    [backupItems addObject:serialized];
                }
            }
        } else if (results) {
            CFRelease(results);
        }
    }

    // Write the backup to a plist file.
    NSDictionary *backup = @{
        @"bundleID": bundleID,
        @"timestamp": timestamp,
        @"items": backupItems,
    };
    [backup writeToFile:backupPath atomically:YES];

    NSLog(@"[GhostKit] Backup created at %@ (%lu items)", backupPath, (unsigned long)backupItems.count);
    return backupPath;
}

#pragma mark - Restore (Security framework)

- (BOOL)restoreKeychainFromBackup:(NSString *)backupPath {
    if (!backupPath || backupPath.length == 0) {
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:backupPath]) {
        NSLog(@"[GhostKit] Backup file not found: %@", backupPath);
        return NO;
    }

    NSDictionary *backup = [NSDictionary dictionaryWithContentsOfFile:backupPath];
    if (!backup) {
        NSLog(@"[GhostKit] Cannot read backup file: %@", backupPath);
        return NO;
    }

    NSArray *items = backup[@"items"];
    if (!items || items.count == 0) {
        NSLog(@"[GhostKit] No items in backup");
        return YES;
    }

    NSArray *secClasses = [KeychainManager allSecClasses];
    BOOL anyRestored = NO;

    for (NSDictionary *item in items) {
        // Determine the item class from the stored index.
        NSString *classHashStr = item[@"__secClass"];
        NSUInteger classHash = classHashStr ? [classHashStr integerValue] : 0;

        id secClass = nil;
        for (id sc in secClasses) {
            if ((NSUInteger)[sc hash] == classHash) {
                secClass = sc;
                break;
            }
        }
        if (!secClass) {
            // Default to generic password if class not found.
            secClass = (__bridge id)kSecClassGenericPassword;
        }

        // Build an add query from the item's attributes and data.
        NSMutableDictionary *addQuery = [NSMutableDictionary dictionary];
        addQuery[(__bridge id)kSecClass] = secClass;

        // Copy relevant attributes.
        NSArray *attrKeys = @[
            (__bridge id)kSecAttrAccessGroup,
            (__bridge id)kSecAttrAccount,
            (__bridge id)kSecAttrService,
            (__bridge id)kSecAttrLabel,
            (__bridge id)kSecAttrServer,
            (__bridge id)kSecAttrProtocol,
            (__bridge id)kSecAttrAuthenticationType,
            (__bridge id)kSecAttrPort,
            (__bridge id)kSecAttrPath,
            (__bridge id)kSecAttrCreationDate,
            (__bridge id)kSecAttrModificationDate,
            (__bridge id)kSecAttrDescription,
            (__bridge id)kSecAttrComment,
        ];
        for (id key in attrKeys) {
            id val = item[key];
            if (val) {
                addQuery[key] = val;
            }
        }

        // Add the data value.
        NSData *valueData = item[(__bridge id)kSecValueData];
        if (valueData) {
            addQuery[(__bridge id)kSecValueData] = valueData;
        }

        OSStatus status = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
        if (status == errSecSuccess) {
            anyRestored = YES;
        }
    }

    NSLog(@"[GhostKit] restoreKeychainFromBackup:%@ -> %@", backupPath, anyRestored ? @"YES" : @"NO");
    return anyRestored;
}

#pragma mark - List (Security framework)

- (NSArray<NSDictionary *> *)listKeychainItemsForBundleID:(NSString *)bundleID {
    NSMutableArray *items = [NSMutableArray array];
    if (!bundleID || bundleID.length == 0) {
        return items;
    }

    NSArray *secClasses = [KeychainManager allSecClasses];

    // Class display names for the result.
    NSDictionary *classNames = @{
        (__bridge id)kSecClassGenericPassword: @"GenericPassword",
        (__bridge id)kSecClassInternetPassword: @"InternetPassword",
        (__bridge id)kSecClassKey: @"Key",
        (__bridge id)kSecClassCertificate: @"Certificate",
        (__bridge id)kSecClassIdentity: @"Identity",
    };

    for (id secClass in secClasses) {
        NSArray *allItems = [KeychainManager queryAllItemsOfClass:secClass];
        for (NSDictionary *item in allItems) {
            NSString *agrp = item[(__bridge id)kSecAttrAccessGroup];
            if ([KeychainManager accessGroup:agrp matchesBundleID:bundleID]) {
                NSString *service = item[(__bridge id)kSecAttrService] ?:
                                    item[(__bridge id)kSecAttrServer] ?: @"";
                NSString *account = item[(__bridge id)kSecAttrAccount] ?: @"";
                NSString *className = classNames[secClass] ?: @"Unknown";

                [items addObject:@{
                    @"class":        className,
                    @"accessGroup":  agrp ?: @"",
                    @"service":      service,
                    @"account":      account,
                }];
            }
        }
    }

    NSLog(@"[GhostKit] listKeychainItemsForBundleID:%@ -> %lu items",
          bundleID, (unsigned long)items.count);
    return items;
}

@end
