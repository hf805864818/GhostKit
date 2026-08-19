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
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;

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

#pragma mark - tccd helpers

/// Stop tccd so it releases the lock on TCC.db.
/// Without this, sqlite3_open / sqlite3_exec fail because
/// tccd holds a lock on the database file.
- (void)stopTCCD {
    pid_t pid = 0;
    char *argv[] = { "killall", "-9", "tccd", NULL };
    posix_spawnp(&pid, "killall", NULL, NULL, argv, environ);
    usleep(300000);  // 0.3s
}

/// Restart tccd after database modifications.
- (void)startTCCD {
    pid_t pid = 0;
    char *argv[] = { "launchctl", "start", "com.apple.tccd", NULL };
    posix_spawnp(&pid, "launchctl", NULL, NULL, argv, environ);
}

#pragma mark - TCC helpers

/// auth_value: 0 = denied, 2 = allowed, 3 = limited
static const int kAuthValueAllowed = 2;
/// client_type: 0 = bundle ID
static const int kClientTypeBundleID = 0;
/// auth_reason: 4 = user set (pre-granted)
static const int kAuthReasonUserSet = 4;

- (BOOL)executeSQL:(NSString *)sql withBindings:(NSArray *)bindings {
    [self stopTCCD];

    sqlite3 *db = NULL;
    if (sqlite3_open_v2([kTCCDBPath UTF8String], &db,
                        SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        NSLog(@"[GhostKit] Cannot open TCC.db: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        [self startTCCD];
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
    [self startTCCD];
    return success;
}

- (BOOL)grantPasteForBundleID:(NSString *)bundleID {
    [self stopTCCD];

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
        [self startTCCD];
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
    [self startTCCD];
    return success;
}

#pragma mark - Allow paste for all apps

- (BOOL)allowPasteForAllApps {
    NSArray<AppInfo *> *apps = [[AppListManager sharedInstance] getAllInstalledApps];
    if (apps.count == 0) {
        NSLog(@"[GhostKit] No installed apps found for paste permission");
        return NO;
    }

    // Stop tccd once for the entire batch, then restart after.
    [self stopTCCD];

    BOOL allSuccess = YES;
    NSUInteger count = 0;

    for (AppInfo *info in apps) {
        // Inline the grant logic to avoid stopping/starting tccd per app.
        NSString *bundleID = info.bundleID;

        // Delete existing entry.
        NSString *deleteSQL = @"DELETE FROM access WHERE service = ? AND client = ?;";
        // Use a local db handle to avoid recursion into executeSQL:.
        sqlite3 *db = NULL;
        if (sqlite3_open_v2([kTCCDBPath UTF8String], &db,
                            SQLITE_OPEN_READWRITE, NULL) == SQLITE_OK) {
            sqlite3_stmt *delStmt = NULL;
            if (sqlite3_prepare_v2(db, [deleteSQL UTF8String], -1, &delStmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(delStmt, 1, [kPasteboardService UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(delStmt, 2, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_step(delStmt);
                sqlite3_finalize(delStmt);
            }

            // Insert.
            NSString *insertSQL =
                @"INSERT OR REPLACE INTO access "
                 "(service, client, client_type, auth_value, auth_reason, auth_version, "
                 "  flags, TTL, TTL_type) "
                 "VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0);";
            sqlite3_stmt *insStmt = NULL;
            if (sqlite3_prepare_v2(db, [insertSQL UTF8String], -1, &insStmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(insStmt, 1, [kPasteboardService UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(insStmt, 2, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(insStmt, 3, kClientTypeBundleID);
                sqlite3_bind_int(insStmt, 4, kAuthValueAllowed);
                sqlite3_bind_int(insStmt, 5, kAuthReasonUserSet);
                sqlite3_bind_int(insStmt, 6, 1);

                if (sqlite3_step(insStmt) == SQLITE_DONE) {
                    count++;
                } else {
                    allSuccess = NO;
                }
                sqlite3_finalize(insStmt);
            } else {
                // Try simpler schema.
                NSString *simpleSQL =
                    @"INSERT OR REPLACE INTO access (service, client, client_type, auth_value) "
                     "VALUES (?, ?, ?, ?);";
                sqlite3_stmt *simpleStmt = NULL;
                if (sqlite3_prepare_v2(db, [simpleSQL UTF8String], -1, &simpleStmt, NULL) == SQLITE_OK) {
                    sqlite3_bind_text(simpleStmt, 1, [kPasteboardService UTF8String], -1, SQLITE_TRANSIENT);
                    sqlite3_bind_text(simpleStmt, 2, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
                    sqlite3_bind_int(simpleStmt, 3, kClientTypeBundleID);
                    sqlite3_bind_int(simpleStmt, 4, kAuthValueAllowed);
                    if (sqlite3_step(simpleStmt) == SQLITE_DONE) count++;
                    else allSuccess = NO;
                    sqlite3_finalize(simpleStmt);
                } else {
                    allSuccess = NO;
                }
            }
            sqlite3_close(db);
        } else {
            allSuccess = NO;
            if (db) sqlite3_close(db);
        }
    }

    [self startTCCD];

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
