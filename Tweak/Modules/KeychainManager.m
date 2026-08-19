//
//  KeychainManager.m
//  GhostKit
//
//  Implements keychain cleaning via the Security framework (SecItemDelete)
//  and via direct sqlite3 manipulation of /var/Keychains/keychain-2.db.
//

#import "KeychainManager.h"
#import <Security/Security.h>
#import <sqlite3.h>

static NSString *const kKeychainDBPath = @"/var/Keychains/keychain-2.db";
static NSString *const kBackupDir     = @"/var/mobile/Library/GhostKit/Backups";

@implementation KeychainManager

+ (instancetype)sharedInstance {
    static KeychainManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[KeychainManager alloc] init];
    });
    return instance;
}

#pragma mark - Security framework clean

- (BOOL)cleanKeychainForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) {
        return NO;
    }

    NSArray *secItemClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassIdentity,
    ];

    BOOL anyDeleted = NO;

    for (id secClass in secItemClasses) {
        // Delete by access group (bundle ID may appear as the access group).
        NSDictionary *groupQuery = @{
            (__bridge id)kSecClass:            secClass,
            (__bridge id)kSecAttrAccessGroup:  bundleID,
            (__bridge id)kSecMatchLimit:       (__bridge id)kSecMatchLimitAll,
        };
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)groupQuery);
        if (status == errSecSuccess) {
            anyDeleted = YES;
        }

        // Delete by service attribute (common when bundle ID is used as kSecAttrService).
        NSDictionary *serviceQuery = @{
            (__bridge id)kSecClass:       secClass,
            (__bridge id)kSecAttrService: bundleID,
            (__bridge id)kSecMatchLimit:  (__bridge id)kSecMatchLimitAll,
        };
        status = SecItemDelete((__bridge CFDictionaryRef)serviceQuery);
        if (status == errSecSuccess) {
            anyDeleted = YES;
        }
    }

    NSLog(@"[GhostKit] cleanKeychainForBundleID:%@ -> %@", bundleID, anyDeleted ? @"YES" : @"NO");
    return anyDeleted;
}

#pragma mark - sqlite3 deep clean

- (BOOL)deepCleanKeychainForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) {
        return NO;
    }

    sqlite3 *db = NULL;
    if (sqlite3_open_v2([kKeychainDBPath UTF8String], &db,
                        SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        NSLog(@"[GhostKit] Cannot open keychain DB: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return NO;
    }

    NSArray *tables = @[@"genp", @"inet", @"keys", @"cert"];
    BOOL success = YES;

    for (NSString *table in tables) {
        NSString *sql = [NSString stringWithFormat:
            @"DELETE FROM %@ WHERE agrp = ?;", table];
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) != SQLITE_DONE) {
                NSLog(@"[GhostKit] Failed to delete from %@: %s",
                      table, sqlite3_errmsg(db));
                success = NO;
            }
            sqlite3_finalize(stmt);
        } else {
            success = NO;
        }
    }

    sqlite3_close(db);
    NSLog(@"[GhostKit] deepCleanKeychainForBundleID:%@ -> %@", bundleID, success ? @"YES" : @"NO");
    return success;
}

#pragma mark - Delete all

- (BOOL)deleteAllKeychains {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2([kKeychainDBPath UTF8String], &db,
                        SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        NSLog(@"[GhostKit] Cannot open keychain DB: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return NO;
    }

    NSArray *tables = @[@"genp", @"inet", @"keys", @"cert"];
    BOOL success = YES;

    for (NSString *table in tables) {
        NSString *sql = [NSString stringWithFormat:@"DELETE FROM %@;", table];
        char *errMsg = NULL;
        if (sqlite3_exec(db, [sql UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
            NSLog(@"[GhostKit] Failed to clear %@: %s", table, errMsg);
            if (errMsg) sqlite3_free(errMsg);
            success = NO;
        }
    }

    sqlite3_close(db);
    NSLog(@"[GhostKit] deleteAllKeychains -> %@", success ? @"YES" : @"NO");
    return success;
}

#pragma mark - Backup

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
        [NSString stringWithFormat:@"keychain_%@_%@.db", bundleID, timestamp]];

    sqlite3 *db = NULL;
    if (sqlite3_open_v2([kKeychainDBPath UTF8String], &db,
                        SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        NSLog(@"[GhostKit] Cannot open keychain DB for backup: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return nil;
    }

    // Attach the backup database.
    NSString *attachSQL = [NSString stringWithFormat:@"ATTACH DATABASE '%@' AS backup;", backupPath];
    char *errMsg = NULL;
    if (sqlite3_exec(db, [attachSQL UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
        NSLog(@"[GhostKit] ATTACH failed: %s", errMsg);
        if (errMsg) sqlite3_free(errMsg);
        sqlite3_close(db);
        return nil;
    }

    NSArray *tables = @[@"genp", @"inet", @"keys", @"cert"];

    for (NSString *table in tables) {
        // Create the table in the backup DB using the same schema (no rows).
        NSString *createSQL = [NSString stringWithFormat:
            @"CREATE TABLE IF NOT EXISTS backup.%@ AS SELECT * FROM %@ WHERE 0;", table, table];
        sqlite3_exec(db, [createSQL UTF8String], NULL, NULL, NULL);

        // Insert matching rows.
        NSString *insertSQL = [NSString stringWithFormat:
            @"INSERT INTO backup.%@ SELECT * FROM %@ WHERE agrp = ?;", table, table];
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, [insertSQL UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
    }

    sqlite3_exec(db, "DETACH DATABASE backup;", NULL, NULL, NULL);
    sqlite3_close(db);

    NSLog(@"[GhostKit] Backup created at %@", backupPath);
    return backupPath;
}

#pragma mark - Restore

- (BOOL)restoreKeychainFromBackup:(NSString *)backupPath {
    if (!backupPath || backupPath.length == 0) {
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:backupPath]) {
        NSLog(@"[GhostKit] Backup file not found: %@", backupPath);
        return NO;
    }

    sqlite3 *db = NULL;
    if (sqlite3_open_v2([kKeychainDBPath UTF8String], &db,
                        SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        NSLog(@"[GhostKit] Cannot open keychain DB for restore: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return NO;
    }

    NSString *attachSQL = [NSString stringWithFormat:
        @"ATTACH DATABASE '%@' AS backup;", backupPath];
    char *errMsg = NULL;
    if (sqlite3_exec(db, [attachSQL UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
        NSLog(@"[GhostKit] ATTACH failed: %s", errMsg);
        if (errMsg) sqlite3_free(errMsg);
        sqlite3_close(db);
        return NO;
    }

    NSArray *tables = @[@"genp", @"inet", @"keys", @"cert"];
    BOOL success = YES;

    for (NSString *table in tables) {
        // Check whether the backup table exists.
        NSString *checkSQL = [NSString stringWithFormat:
            @"SELECT name FROM backup.sqlite_master WHERE type='table' AND name='%@';", table];
        sqlite3_stmt *chkStmt = NULL;
        BOOL tableExists = NO;
        if (sqlite3_prepare_v2(db, [checkSQL UTF8String], -1, &chkStmt, NULL) == SQLITE_OK) {
            if (sqlite3_step(chkStmt) == SQLITE_ROW) {
                tableExists = YES;
            }
            sqlite3_finalize(chkStmt);
        }

        if (tableExists) {
            NSString *insertSQL = [NSString stringWithFormat:
                @"INSERT INTO %@ SELECT * FROM backup.%@;", table, table];
            char *err = NULL;
            if (sqlite3_exec(db, [insertSQL UTF8String], NULL, NULL, &err) != SQLITE_OK) {
                NSLog(@"[GhostKit] Restore error for %@: %s", table, err);
                if (err) sqlite3_free(err);
                success = NO;
            }
        }
    }

    sqlite3_exec(db, "DETACH DATABASE backup;", NULL, NULL, NULL);
    sqlite3_close(db);

    NSLog(@"[GhostKit] restoreKeychainFromBackup:%@ -> %@", backupPath, success ? @"YES" : @"NO");
    return success;
}

#pragma mark - List

- (NSArray<NSDictionary *> *)listKeychainItemsForBundleID:(NSString *)bundleID {
    NSMutableArray *items = [NSMutableArray array];
    if (!bundleID || bundleID.length == 0) {
        return items;
    }

    sqlite3 *db = NULL;
    if (sqlite3_open_v2([kKeychainDBPath UTF8String], &db,
                        SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        NSLog(@"[GhostKit] Cannot open keychain DB for listing: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return items;
    }

    // (table, descriptive column)
    NSArray *tableInfo = @[
        @[@"genp", @"srv"],   // generic passwords
        @[@"inet", @"srv"],   // internet passwords
        @[@"keys", @"klbl"],  // keys
        @[@"cert", @"labl"],  // certificates
    ];

    for (NSArray *info in tableInfo) {
        NSString *table  = info[0];
        NSString *column = info[1];
        NSString *sql = [NSString stringWithFormat:
            @"SELECT agrp, %@, length(data) FROM %@ WHERE agrp = ?;", column, table];

        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
            while (sqlite3_step(stmt) == SQLITE_ROW) {
                const char *agrp = (const char *)sqlite3_column_text(stmt, 0);
                const char *srv  = (const char *)sqlite3_column_text(stmt, 1);
                int dataLen      = sqlite3_column_int(stmt, 2);

                [items addObject:@{
                    @"table":       table,
                    @"accessGroup": agrp ? [NSString stringWithUTF8String:agrp] : @"",
                    @"service":     srv  ? [NSString stringWithUTF8String:srv]  : @"",
                    @"dataLength":  @(dataLen),
                }];
            }
            sqlite3_finalize(stmt);
        }
    }

    sqlite3_close(db);
    return items;
}

@end
