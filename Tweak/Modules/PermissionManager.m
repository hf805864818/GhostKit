//
//  PermissionManager.m
//  GhostKit
//
//  Manipulates the TCC (Transparency, Consent and Control) database at
//  /var/mobile/Library/TCC/TCC.db to grant pasteboard (kTCCServicePasteboard)
//  permissions.
//
//  On rootless jailbreaks (RelaXin/Dopamine) and TrollStore, the Tweak
//  process may not have sufficient privileges to directly modify TCC.db.
//  We try multiple strategies:
//    1. Stop tccd (try multiple binary paths for rootless jailbreaks)
//    2. Open TCC.db with sqlite3_busy_timeout to wait for locks
//    3. If SQLite open fails, return NO with a clear error
//

#import "PermissionManager.h"
#import "AppListManager.h"
#import <sqlite3.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

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

#pragma mark - Binary path search (rootless compatible)

/// Find an executable binary by trying multiple paths on iOS.
/// On rootless jailbreaks, binaries are at /var/jb/bin/ instead of /usr/bin/.
- (NSString *)findBinary:(NSString *)name {
    NSArray *paths = @[
        [NSString stringWithFormat:@"/var/jb/bin/%@", name],
        [NSString stringWithFormat:@"/usr/bin/%@", name],
        [NSString stringWithFormat:@"/bin/%@", name],
    ];
    for (NSString *path in paths) {
        if (access([path UTF8String], X_OK) == 0) {
            return path;
        }
    }
    return nil;
}

/// Spawn a binary with the given arguments. Returns the exit status.
- (int)spawnBinary:(NSString *)path withArgs:(NSArray<NSString *> *)args {
    if (!path) return -1;

    // Build C argv array.
    int argc = (int)(1 + args.count + 1);
    char **argv = (char **)malloc(sizeof(char *) * argc);
    if (!argv) return -1;

    argv[0] = strdup([path UTF8String]);
    for (NSUInteger i = 0; i < args.count; i++) {
        argv[i + 1] = strdup([args[i] UTF8String]);
    }
    argv[argc - 1] = NULL;

    pid_t pid = 0;
    int rc = posix_spawn(&pid, [path UTF8String], NULL, NULL, argv, environ);

    // Free argv.
    for (int i = 0; i < argc - 1; i++) {
        if (argv[i]) free(argv[i]);
    }
    free(argv);

    if (rc != 0) return -1;

    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

#pragma mark - tccd helpers

/// Stop tccd so it releases the lock on TCC.db.
- (void)stopTCCD {
    NSString *killallPath = [self findBinary:@"killall"];
    if (killallPath) {
        [self spawnBinary:killallPath withArgs:@[@"-9", @"tccd"]];
    }
    usleep(300000);  // 0.3s for tccd to release the lock
}

/// Restart tccd after database modifications.
- (void)startTCCD {
    NSString *launchctlPath = [self findBinary:@"launchctl"];
    if (launchctlPath) {
        [self spawnBinary:launchctlPath withArgs:@[@"start", @"com.apple.tccd"]];
    }
}

#pragma mark - TCC helpers

/// auth_value: 0 = denied, 2 = allowed, 3 = limited
static const int kAuthValueAllowed = 2;
/// client_type: 0 = bundle ID
static const int kClientTypeBundleID = 0;
/// auth_reason: 4 = user set (pre-granted)
static const int kAuthReasonUserSet = 4;

- (BOOL)grantPasteForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) return NO;

    [self stopTCCD];

    sqlite3 *db = NULL;
    if (sqlite3_open_v2([kTCCDBPath UTF8String], &db,
                        SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        NSLog(@"[GhostKit] Cannot open TCC.db: %s", db ? sqlite3_errmsg(db) : "null");
        if (db) sqlite3_close(db);
        [self startTCCD];
        return NO;
    }

    // Wait up to 5s if TCC.db is locked by tccd.
    sqlite3_busy_timeout(db, 5000);

    // First, delete any existing entry for this bundle ID.
    sqlite3_stmt *delStmt = NULL;
    const char *deleteSQL = "DELETE FROM access WHERE service = ? AND client = ?;";
    if (sqlite3_prepare_v2(db, deleteSQL, -1, &delStmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(delStmt, 1, [kPasteboardService UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(delStmt, 2, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_step(delStmt);
        sqlite3_finalize(delStmt);
    }

    // Insert the permission row.
    // Try the full schema first, then fall back to a simpler one.
    BOOL success = NO;

    const char *insertSQL =
        "INSERT OR REPLACE INTO access "
        "(service, client, client_type, auth_value, auth_reason, auth_version, "
        " flags, TTL, TTL_type) "
        "VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0);";

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, insertSQL, -1, &stmt, NULL) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, [kPasteboardService UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 3, kClientTypeBundleID);
        sqlite3_bind_int(stmt, 4, kAuthValueAllowed);
        sqlite3_bind_int(stmt, 5, kAuthReasonUserSet);
        sqlite3_bind_int(stmt, 6, 1);

        if (sqlite3_step(stmt) == SQLITE_DONE) {
            success = YES;
        } else {
            NSLog(@"[GhostKit] INSERT into TCC failed: %s", sqlite3_errmsg(db));
        }
        sqlite3_finalize(stmt);
    } else {
        // The table schema may differ. Try a simpler INSERT.
        const char *simpleSQL =
            "INSERT OR REPLACE INTO access (service, client, client_type, auth_value) "
            "VALUES (?, ?, ?, ?);";

        if (sqlite3_prepare_v2(db, simpleSQL, -1, &stmt, NULL) == SQLITE_OK) {
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

    sqlite3 *db = NULL;
    if (sqlite3_open_v2([kTCCDBPath UTF8String], &db,
                        SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        NSLog(@"[GhostKit] Cannot open TCC.db for batch paste: %s",
              db ? sqlite3_errmsg(db) : "null");
        if (db) sqlite3_close(db);
        [self startTCCD];
        return NO;
    }

    sqlite3_busy_timeout(db, 5000);

    NSUInteger count = 0;
    BOOL anySuccess = NO;

    for (AppInfo *info in apps) {
        NSString *bundleID = info.bundleID;
        if (!bundleID || bundleID.length == 0) continue;

        // Delete existing entry.
        sqlite3_stmt *delStmt = NULL;
        const char *deleteSQL = "DELETE FROM access WHERE service = ? AND client = ?;";
        if (sqlite3_prepare_v2(db, deleteSQL, -1, &delStmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(delStmt, 1, [kPasteboardService UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(delStmt, 2, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_step(delStmt);
            sqlite3_finalize(delStmt);
        }

        // Insert. Try full schema, then simpler.
        const char *insertSQL =
            "INSERT OR REPLACE INTO access "
            "(service, client, client_type, auth_value, auth_reason, auth_version, "
            " flags, TTL, TTL_type) "
            "VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0);";

        sqlite3_stmt *stmt = NULL;
        BOOL inserted = NO;

        if (sqlite3_prepare_v2(db, insertSQL, -1, &stmt, NULL) == SQLITE_OK) {
            sqlite3_bind_text(stmt, 1, [kPasteboardService UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_text(stmt, 2, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
            sqlite3_bind_int(stmt, 3, kClientTypeBundleID);
            sqlite3_bind_int(stmt, 4, kAuthValueAllowed);
            sqlite3_bind_int(stmt, 5, kAuthReasonUserSet);
            sqlite3_bind_int(stmt, 6, 1);

            if (sqlite3_step(stmt) == SQLITE_DONE) {
                inserted = YES;
            }
            sqlite3_finalize(stmt);
        }

        if (!inserted) {
            // Try simpler schema.
            const char *simpleSQL =
                "INSERT OR REPLACE INTO access (service, client, client_type, auth_value) "
                "VALUES (?, ?, ?, ?);";
            if (sqlite3_prepare_v2(db, simpleSQL, -1, &stmt, NULL) == SQLITE_OK) {
                sqlite3_bind_text(stmt, 1, [kPasteboardService UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(stmt, 2, [bundleID UTF8String], -1, SQLITE_TRANSIENT);
                sqlite3_bind_int(stmt, 3, kClientTypeBundleID);
                sqlite3_bind_int(stmt, 4, kAuthValueAllowed);
                if (sqlite3_step(stmt) == SQLITE_DONE) inserted = YES;
                sqlite3_finalize(stmt);
            }
        }

        if (inserted) {
            count++;
            anySuccess = YES;
        }
    }

    sqlite3_close(db);
    [self startTCCD];

    NSLog(@"[GhostKit] allowPasteForAllApps: %lu / %lu granted",
          (unsigned long)count, (unsigned long)apps.count);
    return anySuccess;
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

    sqlite3_busy_timeout(db, 3000);

    const char *sql = "SELECT auth_value FROM access WHERE service = ? AND client = ?;";
    sqlite3_stmt *stmt = NULL;
    BOOL allowed = NO;

    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
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
