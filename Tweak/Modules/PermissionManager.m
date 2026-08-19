//
//  PermissionManager.m
//  GhostKit
//
//  Manipulates the TCC (Transparency, Consent and Control) database at
//  /var/mobile/Library/TCC/TCC.db to grant pasteboard (kTCCServicePasteboard)
//  permissions.
//
//  The `access` table columns (iOS 16+):
//    service, client, client_type, auth_value, auth_reason,
//    auth_version, bootstrap, ... (schema varies by iOS version)
//

#import "PermissionManager.h"
#import "AppListManager.h"
#import <sqlite3.h>

static NSString *const kTCCDBPath = @"/var/mobile/Library/TCC/TCC.db";
static NSString *const kPasteboardService = @"kTCCServicePasteboard";

@implementation PermissionManager

+ (instancetype)sharedInstance {
    static PermissionManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PermissionManager alloc] init];
    });
    return instance;
}

#pragma mark - TCC helpers

/// auth_value: 0 = denied, 2 = allowed, 3 = limited
static const int kAuthValueAllowed = 2;
/// client_type: 0 = bundle ID
static const int kClientTypeBundleID = 0;
/// auth_reason: 4 = user set (pre-granted)
static const int kAuthReasonUserSet = 4;

- (BOOL)executeSQL:(NSString *)sql withBindings:(NSArray *)bindings {
    sqlite3 *db = NULL;
    if (sqlite3_open_v2([kTCCDBPath UTF8String], &db,
                        SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        NSLog(@"[GhostKit] Cannot open TCC.db: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return NO;
    }

    sqlite3_stmt *stmt = NULL;
    BOOL success = NO;

    if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        for (NSUInteger i = 0; i < bindings.count; i++) {
            sqlite3_bind_text(stmt, (int)(i + 1),
                              [bindings[i] UTF8String], -1, SQLITE_TRANSIENT);
        }
        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        } else {
            NSLog(@"[GhostKit] SQL step error: %s", sqlite3_errmsg(db));
        }
        sqlite3_finalize(stmt);
    } else {
        NSLog(@"[GhostKit] SQL prepare error: %s", sqlite3_errmsg(db));
    }

    sqlite3_close(db);
    return success;
}

- (BOOL)grantPasteForBundleID:(NSString *)bundleID {
    // First try to delete any existing entry, then insert a fresh one.
    NSString *deleteSQL = @"DELETE FROM access WHERE service = ? AND client = ?;";
    [self executeSQL:deleteSQL withBindings:@[kPasteboardService, bundleID]];

    // INSERT OR REPLACE to handle the case where a row already exists.
    NSString *insertSQL =
        @"INSERT OR REPLACE INTO access "
         "(service, client, client_type, auth_value, auth_reason, auth_version, "
         "  flags, TTL, TTL_type) "
         "VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0);";

    sqlite3 *db = NULL;
    if (sqlite3_open_v2([kTCCDBPath UTF8String], &db,
                        SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        NSLog(@"[GhostKit] Cannot open TCC.db: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return NO;
    }

    sqlite3_stmt *stmt = NULL;
    BOOL success = NO;

    if (sqlite3_prepare_v2(db, [insertSQL UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, [kPasteboardService UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 3, kClientTypeBundleID);
        sqlite3_bind_int(stmt, 4, kAuthValueAllowed);
        sqlite3_bind_int(stmt, 5, kAuthReasonUserSet);
        sqlite3_bind_int(stmt, 6, 1); // auth_version

        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        } else {
            NSLog(@"[GhostKit] INSERT into TCC failed: %s", sqlite3_errmsg(db));
        }
        sqlite3_finalize(stmt);
    } else {
        // The table schema may differ. Try a simpler INSERT with fewer columns.
        NSString *simpleSQL =
            @"INSERT OR REPLACE INTO access (service, client, client_type, auth_value) "
             "VALUES (?, ?, ?, ?);";

        if (sqlite3_prepare_v2(db, [simpleSQL UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [kPasteboardService UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 3, kClientTypeBundleID);
            sqlite3_bind_int(stmt, 4, kAuthValueAllowed);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
            success = YES;
        } else {
            NSLog(@"[GhostKit] TCC INSERT prepare failed: %s", sqlite3_errmsg(db));
        }
    }

    sqlite3_close(db);
    return success;
}

#pragma mark - Allow paste for all apps

- (BOOL)allowPasteForAllApps {
    NSArray<AppInfo *> *apps = [[AppListManager sharedInstance] getAllInstalledApps];
    if (apps.count == 0) {
        NSLog(@"[GhostKit] No installed apps found for paste permission");
        return NO;
    }

    BOOL allSuccess = YES;
    NSUInteger count = 0;

    for (AppInfo *info in apps) {
        if ([self grantPasteForBundleID:info.bundleID]) {
            count++;
        } else {
            allSuccess = NO;
        }
    }

    NSLog(@"[GhostKit] allowPasteForAllApps: %lu / %lu granted",
          (unsigned long)count, (unsigned long)apps.count);
    return allSuccess;
}

#pragma mark - Is paste allowed

- (BOOL)isPasteAllowedForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) {
        return NO;
    }

    sqlite3 *db = NULL;
    if (sqlite3_open_v2([kTCCDBPath UTF8String], &db,
                        SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return NO;
    }

    NSString *sql = @"SELECT auth_value FROM access WHERE service = ? AND client = ?;";
    sqlite3_stmt *stmt = NULL;
    BOOL allowed = NO;

    if (sqlite3_prepare_v2(db, [sql UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, [kPasteboardService UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [bundleID UTF8String], -1, SQLITE_TRANSIENT);

        if (sqlite3_step(stmt) == SQLITE_ROW) {
            int authValue = sqlite3_column_int(stmt, 0);
            allowed = (authValue == kAuthValueAllowed);
        }
        sqlite3_finalize(stmt);
    }

    sqlite3_close(db);
    return allowed;
}

@end
