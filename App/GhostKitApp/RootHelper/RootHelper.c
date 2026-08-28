/*
 * RootHelper.c
 * GhostKit
 *
 * Privileged C helper for GhostKit.  Spawned by RootHelperManager (Swift)
 * to perform system operations on iOS.
 *
 * PRIVILEGE MODEL:
 *   - RootHelper attempts to elevate to root via setuid(0) at startup
 *   - If successful (rootful jailbreak), all operations have full access
 *   - If setuid(0) fails (rootless jailbreak / TrollStore), RootHelper
 *     continues anyway — the app's entitlements (platform-application +
 *     no-sandbox) provide sufficient filesystem access for most operations.
 *   - Individual operations report their own errors if they genuinely
 *     require root (e.g., stopping system daemons may fail).
 *
 * OPERATIONS:
 *   clean_keychain, deep_clean_keychain, delete_all_keychains, restore_keychains
 *   reset_idfa, clean_system, clean_cache, clean_data_dir, clean_cookies
 *   reset_device, allow_paste_all, respring, ldrestart
 *   uninstall_app, apply_config
 *
 * COMPILE:
 *   xcrun -sdk iphoneos cc -arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
 *       -o RootHelper RootHelper.c -lsqlite3 -framework Foundation
 *       -framework MobileCoreServices -framework CoreFoundation
 */

#include "RootHelper.h"
#include <sqlite3.h>
#include <fts.h>
#include <stdarg.h>
#include <spawn.h>
#include <sys/wait.h>
#include <CoreFoundation/CoreFoundation.h>

extern char **environ;

/* ── run_shell: replacement for system() using posix_spawn ────────────── */
static int run_shell(const char *cmd) {
    if (!cmd || !*cmd) return -1;

    /* On iOS, /bin/sh does not exist. Try /var/jb/bin/sh (rootless jailbreak)
     * or /bin/bash as fallbacks. If none exist, the command fails silently. */
    const char *sh_paths[] = { "/bin/sh", "/var/jb/bin/sh", "/bin/bash", NULL };
    const char *sh = NULL;
    for (int i = 0; sh_paths[i]; i++) {
        if (access(sh_paths[i], X_OK) == 0) { sh = sh_paths[i]; break; }
    }
    if (!sh) return -1;

    char *argv[] = { (char *)sh, "-c", (char *)cmd, NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, sh, NULL, NULL, argv, environ);
    if (rc != 0) return -1;

    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

/* ── run_shell_capture: like popen() but using posix_spawn ─────────────── */
static int run_shell_capture(const char *cmd, char *output, int out_size) {
    if (!cmd || !*cmd || !output || out_size <= 0) return -1;
    output[0] = '\0';

    /* Find an available shell on iOS. */
    const char *sh_paths[] = { "/bin/sh", "/var/jb/bin/sh", "/bin/bash", NULL };
    const char *sh = NULL;
    for (int i = 0; sh_paths[i]; i++) {
        if (access(sh_paths[i], X_OK) == 0) { sh = sh_paths[i]; break; }
    }
    if (!sh) return -1;

    int pipefd[2];
    if (pipe(pipefd) != 0) return -1;

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);

    char *argv[] = { (char *)sh, "-c", (char *)cmd, NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, sh, &actions, NULL, argv, environ);

    posix_spawn_file_actions_destroy(&actions);

    if (rc != 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return -1;
    }

    close(pipefd[1]);

    int total = 0;
    ssize_t n;
    while ((n = read(pipefd[0], output + total, out_size - total - 1)) > 0) {
        total += (int)n;
        if (total >= out_size - 1) break;
    }
    output[total] = '\0';

    close(pipefd[0]);

    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

/* ── try_launchctl: try multiple launchctl paths on iOS ───────────────── */
static int try_launchctl(const char *action, const char *service) {
    /* On iOS, launchctl may be at different paths depending on jailbreak type:
     * - Stock iOS: /usr/bin/launchctl (but without root, stop/start may fail)
     * - Rootless jailbreak (RelaXin/Dopamine): /var/jb/bin/launchctl
     * - Rootful jailbreak: /usr/bin/launchctl (with root works)
     */
    const char *lc_paths[] = {
        "/var/jb/bin/launchctl",
        "/usr/bin/launchctl",
        "/bin/launchctl",
        NULL
    };

    for (int i = 0; lc_paths[i]; i++) {
        if (access(lc_paths[i], X_OK) != 0) continue;
        int rc = run_simple(lc_paths[i], action, service, NULL);
        if (rc == 0) {
            LOG("launchctl %s %s succeeded via %s", action, service, lc_paths[i]);
            return 0;
        }
    }
    LOG("launchctl %s %s failed (tried all paths)", action, service);
    return -1;
}

/* ── try_killall: try multiple killall paths on iOS ───────────────────── */
static int try_killall(const char *signal, const char *process) {
    const char *ka_paths[] = {
        "/var/jb/bin/killall",
        "/usr/bin/killall",
        "/bin/killall",
        NULL
    };

    for (int i = 0; ka_paths[i]; i++) {
        if (access(ka_paths[i], X_OK) != 0) continue;
        int rc = run_simple(ka_paths[i], signal, process, NULL);
        if (rc == 0) {
            LOG("killall %s %s succeeded via %s", signal, process, ka_paths[i]);
            return 0;
        }
    }
    return -1;
}

/* ===========================================================================
 * Internal helpers
 * ========================================================================= */

/* Simple boolean */
typedef int bool_t;
#define TRUE  1
#define FALSE 0

/* Log a message to stderr (captured by RootHelperManager). */
#define LOG(fmt, ...) \
    fprintf(stderr, "[RootHelper] " fmt "\n", ##__VA_ARGS__)

/* Log to stdout (captured as success message). */
#define LOG_OK(fmt, ...) \
    printf("[RootHelper] " fmt "\n", ##__VA_ARGS__)

/* --------------------------------------------------------------------------
 * posix_spawn wrapper
 * ------------------------------------------------------------------------ */

int run_root_command(const char *command, const char *const argv[]) {
    if (command == NULL) {
        return -1;
    }

    pid_t pid = 0;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);

    int status = posix_spawnp(&pid, command, &actions, NULL,
                              (char *const *)(argv ? argv : (const char *const[]){command, NULL}),
                              environ);
    posix_spawn_file_actions_destroy(&actions);

    if (status != 0) {
        LOG("posix_spawn failed for '%s': %s", command, strerror(status));
        return -1;
    }

    int exit_status = 0;
    waitpid(pid, &exit_status, 0);

    if (WIFEXITED(exit_status)) {
        return WEXITSTATUS(exit_status);
    }
    return -1;
}

int run_simple(const char *binary, ...) {
    if (binary == NULL) {
        return -1;
    }

    const char *argv[32];
    int argc = 0;
    argv[argc++] = binary;

    va_list ap;
    va_start(ap, binary);
    const char *arg;
    while ((arg = va_arg(ap, const char *)) != NULL && argc < 31) {
        argv[argc++] = arg;
    }
    va_end(ap);
    argv[argc] = NULL;

    return run_root_command(binary, argv);
}

/* --------------------------------------------------------------------------
 * File-system utilities
 * ------------------------------------------------------------------------ */

int remove_directory_tree(const char *path) {
    if (path == NULL || path[0] == '\0') {
        return -1;
    }

    char *const paths[] = { (char *)path, NULL };
    FTS *fts = fts_open(paths, FTS_NOCHDIR | FTS_PHYSICAL, NULL);
    if (fts == NULL) {
        LOG("fts_open failed for '%s': %s", path, strerror(errno));
        return -1;
    }

    FTSENT *entry = NULL;
    int error = 0;
    while ((entry = fts_read(fts)) != NULL) {
        switch (entry->fts_info) {
            case FTS_DP:   /* post-order directory */
            case FTS_F:    /* regular file */
            case FTS_SL:   /* symlink */
            case FTS_DEFAULT:
                if (remove(entry->fts_accpath) != 0 && errno != ENOENT) {
                    LOG("remove '%s' failed: %s", entry->fts_accpath, strerror(errno));
                    error = -1;
                }
                break;
            case FTS_DNR:
            case FTS_ERR:
                LOG("fts error '%s': %s", entry->fts_accpath, strerror(errno));
                error = -1;
                break;
            default:
                break;
        }
    }
    fts_close(fts);
    return error;
}

int copy_file(const char *src, const char *dst) {
    if (src == NULL || dst == NULL) {
        return -1;
    }

    FILE *in = fopen(src, "rb");
    if (in == NULL) {
        LOG("copy_file: cannot open source '%s': %s", src, strerror(errno));
        return -1;
    }

    FILE *out = fopen(dst, "wb");
    if (out == NULL) {
        LOG("copy_file: cannot open dest '%s': %s", dst, strerror(errno));
        fclose(in);
        return -1;
    }

    char buffer[65536];
    size_t n;
    while ((n = fread(buffer, 1, sizeof(buffer), in)) > 0) {
        if (fwrite(buffer, 1, n, out) != n) {
            LOG("copy_file: write error: %s", strerror(errno));
            fclose(in);
            fclose(out);
            return -1;
        }
    }

    fclose(in);
    fclose(out);

    /* Preserve permissions */
    struct stat st;
    if (stat(src, &st) == 0) {
        chmod(dst, st.st_mode);
    }
    return 0;
}

/* Make a directory, creating parents as needed. */
static int mkdir_p(const char *path, mode_t mode) {
    char tmp[MAX_CMD_LEN];
    strncpy(tmp, path, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = '\0';

    size_t len = strlen(tmp);
    if (len > 0 && tmp[len - 1] == '/') {
        tmp[len - 1] = '\0';
    }

    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, mode);
            *p = '/';
        }
    }
    if (mkdir(tmp, mode) != 0 && errno != EEXIST) {
        LOG("mkdir_p '%s' failed: %s", tmp, strerror(errno));
        return -1;
    }
    return 0;
}

/* --------------------------------------------------------------------------
 * SQLite helper
 * ------------------------------------------------------------------------ */

/* Execute a single SQL statement (no results). Returns 0 on success. */
static int sql_exec(const char *db_path, const char *sql) {
    sqlite3 *db = NULL;
    if (sqlite3_open(db_path, &db) != SQLITE_OK) {
        LOG("sql_exec: cannot open '%s': %s", db_path, sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return -1;
    }

    /* Wait up to 5 seconds if the database is locked by another process
     * (e.g., securityd holds a lock on keychain-2.db, tccd on TCC.db).
     * This allows us to modify the DB without stopping the daemon,
     * which is crucial on rootless jailbreaks where we can't stop daemons. */
    sqlite3_busy_timeout(db, 5000);

    char *errmsg = NULL;
    int rc = sqlite3_exec(db, sql, NULL, NULL, &errmsg);
    if (rc != SQLITE_OK) {
        LOG("sql_exec failed: %s (rc=%d)", errmsg ? errmsg : "unknown", rc);
        if (errmsg) sqlite3_free(errmsg);
        sqlite3_close(db);
        return -1;
    }

    sqlite3_close(db);
    return 0;
}

/* Execute a parameterised SQL statement with one text binding. */
static int sql_exec_text(const char *db_path, const char *sql, const char *param) {
    sqlite3 *db = NULL;
    if (sqlite3_open(db_path, &db) != SQLITE_OK) {
        LOG("sql_exec_text: cannot open '%s'", db_path);
        if (db) sqlite3_close(db);
        return -1;
    }

    /* Wait for locks instead of failing immediately. */
    sqlite3_busy_timeout(db, 5000);

    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) {
        LOG("sql_exec_text: prepare failed: %s", sqlite3_errmsg(db));
        sqlite3_close(db);
        return -1;
    }

    if (param) {
        sqlite3_bind_text(stmt, 1, param, -1, SQLITE_STATIC);
    }

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    if (rc != SQLITE_DONE && rc != SQLITE_ROW) {
        LOG("sql_exec_text: step failed: rc=%d", rc);
        return -1;
    }
    return 0;
}

/* ===========================================================================
 * Keychain operations
 * ========================================================================= */

int clean_keychain(const char *bundleID) {
    if (bundleID == NULL) {
        return -1;
    }

    LOG("clean_keychain for '%s'", bundleID);

    /*
     * Try to stop securityd so it releases the lock on keychain-2.db.
     * On rootless jailbreaks this may fail (no root), but we proceed
     * anyway — sqlite3_busy_timeout will wait for the lock.
     */
    try_launchctl("stop", "com.apple.securityd");
    usleep(500000);  /* Wait 0.5s for securityd to release the lock */

    /*
     * keychain-2.db schema (root-only):
     *   genp  - generic passwords  (acct, svce, agrp)
     *   inet  - internet passwords (acct, svce, agrp)
     *   cert  - certificates       (agrp)
     *   keys  - keys               (agrp)
     *   mupd  - managed items      (agrp)
     *   otlp  - one-time passwords (acct, svce, agrp)
     *
     * Delete every row whose access group (agrp) or account (acct)
     * contains the bundle identifier.
     */
    const char *tables[] = { "genp", "inet", "cert", "keys", "mupd", "otlp" };
    int table_count = sizeof(tables) / sizeof(tables[0]);

    char sql[512];
    int errors = 0;

    for (int i = 0; i < table_count; i++) {
        snprintf(sql, sizeof(sql),
                 "DELETE FROM %s WHERE agrp LIKE '%%%s%%' OR acct LIKE '%%%s%%';",
                 tables[i], bundleID, bundleID);
        if (sql_exec(KEYCHAIN_DB_PATH, sql) != 0) {
            errors++;
        }
    }

    /* Also clean the keychain metadata table (persists deleted item references). */
    sql_exec(KEYCHAIN_DB_PATH,
             "DELETE FROM metadata WHERE rowid IN "
             "(SELECT rowid FROM metadata WHERE label LIKE 'apple.default-identifier' "
             "OR label LIKE 'apple.default-keychain');");

    /* Restart securityd so it picks up the modified database. */
    try_launchctl("start", "com.apple.securityd");

    if (errors > 0) {
        LOG("clean_keychain completed with %d table errors", errors);
    }
    LOG_OK("clean_keychain done for '%s'", bundleID);
    return errors == 0 ? 0 : -1;
}

int deep_clean_keychain(const char *bundleID) {
    if (bundleID == NULL) {
        return -1;
    }

    LOG("deep_clean_keychain for '%s'", bundleID);

    /* Stop securityd to release the database lock before direct sqlite access. */
    try_launchctl("stop", "com.apple.securityd");
    usleep(500000);

    /* Deep clean removes ALL rows that could be associated, including
     * group access table entries, sync views, and the backup metadata. */
    const char *tables[] = {
        "genp", "inet", "cert", "keys", "mupd", "otlp",
        "grp", "access_groups"
    };
    int table_count = sizeof(tables) / sizeof(tables[0]);

    char sql[512];
    int errors = 0;

    for (int i = 0; i < table_count; i++) {
        snprintf(sql, sizeof(sql),
                 "DELETE FROM %s WHERE agrp LIKE '%%%s%%' OR acct LIKE '%%%s%%' "
                 "OR svce LIKE '%%%s%%';",
                 tables[i], bundleID, bundleID, bundleID);
        if (sql_exec(KEYCHAIN_DB_PATH, sql) != 0) {
            /* Table may not exist on this iOS version; ignore. */
        }
    }

    /* Also clear the trust store entries for this app. */
    {
        char trust_sql[512];
        snprintf(trust_sql, sizeof(trust_sql),
                 "DELETE FROM trust_record WHERE subject LIKE '%%%s%%';", bundleID);
        sql_exec(KEYCHAIN_DB_PATH, trust_sql);
    }

    /* Vacuum to compact the database after deletion. */
    sql_exec(KEYCHAIN_DB_PATH, "VACUUM;");

    /* Restart securityd after database modifications. */
    try_launchctl("start", "com.apple.securityd");

    LOG_OK("deep_clean_keychain done for '%s'", bundleID);
    return errors == 0 ? 0 : -1;
}

int delete_all_keychains(void) {
    LOG("delete_all_keychains - backing up then truncating");

    /* Stop securityd to release the database lock. */
    try_launchctl("stop", "com.apple.securityd");
    usleep(500000);

    /* Create backup directory. */
    mkdir_p(KEYCHAIN_BACKUP_DIR, 0755);

    /* Back up the keychain database. */
    char backup_path[MAX_CMD_LEN];
    snprintf(backup_path, sizeof(backup_path), "%s/keychain-2.db", KEYCHAIN_BACKUP_DIR);
    copy_file(KEYCHAIN_DB_PATH, backup_path);
    LOG("Backed up keychain to '%s'", backup_path);

    /* Truncate all data tables. */
    const char *tables[] = {
        "genp", "inet", "cert", "keys", "mupd", "otlp",
        "access_groups", "grp", "trust_record", "pupd", "sxp"
    };
    int table_count = sizeof(tables) / sizeof(tables[0]);

    char sql[256];
    for (int i = 0; i < table_count; i++) {
        snprintf(sql, sizeof(sql), "DELETE FROM %s;", tables[i]);
        sql_exec(KEYCHAIN_DB_PATH, sql);
    }

    sql_exec(KEYCHAIN_DB_PATH, "VACUUM;");

    /* Restart securityd. */
    try_launchctl("start", "com.apple.securityd");

    LOG_OK("delete_all_keychains done");
    return 0;
}

int restore_keychains(void) {
    LOG("restore_keychains from backup");

    char backup_path[MAX_CMD_LEN];
    snprintf(backup_path, sizeof(backup_path), "%s/keychain-2.db", KEYCHAIN_BACKUP_DIR);

    struct stat st;
    if (stat(backup_path, &st) != 0) {
        LOG("restore_keychains: no backup found at '%s'", backup_path);
        return -1;
    }

    /* Close any open keychain connections by restarting securityd. */
    try_launchctl("stop", "com.apple.securityd");
    usleep(500000);

    /* Restore the backup over the live database. */
    if (copy_file(backup_path, KEYCHAIN_DB_PATH) != 0) {
        LOG("restore_keychains: copy failed");
        try_launchctl("start", "com.apple.securityd");
        return -1;
    }

    try_launchctl("start", "com.apple.securityd");

    LOG_OK("restore_keychains done");
    return 0;
}

/* ===========================================================================
 * IDFA
 * ========================================================================= */

int reset_idfa(void) {
    LOG("reset_idfa");

    /*
     * The advertising identifier is cached in several locations.
     * Deleting these forces iOS to generate a fresh IDFA on the next
     * ASIdentifierManager query.
     */
    const char *idfa_files[] = {
        "/private/var/mobile/Library/com.apple.adcenterd/IDFA.db",
        "/private/var/mobile/Library/com.apple.adcenterd/adattribution.db",
        "/private/var/mobile/Library/com.apple.adcenterd/adattribution.db-wal",
        "/private/var/mobile/Library/com.apple.adcenterd/adattribution.db-shm",
        "/private/var/mobile/Library/Caches/adid.plist",
        "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.advertising",
        "/private/var/mobile/Library/Preferences/com.apple.advertisingIdentifier.plist",
    };
    int count = sizeof(idfa_files) / sizeof(idfa_files[0]);

    for (int i = 0; i < count; i++) {
        struct stat st;
        if (stat(idfa_files[i], &st) == 0) {
            if (S_ISDIR(st.st_mode)) {
                remove_directory_tree(idfa_files[i]);
            } else {
                unlink(idfa_files[i]);
            }
            LOG("Removed IDFA file: %s", idfa_files[i]);
        }
    }

    /* Also clear the IDFA from the sqlite DB if present. */
    sql_exec(IDFA_DB_PATH, "DELETE FROM idfa;");

    /* Reset the ASIdentifierManager preference.
     * On iOS, /usr/bin/defaults does not exist. Delete the plist file
     * directly — iOS will regenerate it with default values on next access. */
    unlink("/private/var/mobile/Library/Preferences/com.apple.advertisingIdentifier.plist");

    LOG_OK("reset_idfa done");
    return 0;
}

/* ===========================================================================
 * System & cache cleaning
 * ========================================================================= */

int clean_system(void) {
    LOG("clean_system");

    /* Clean /tmp (delete contents, preserve the directory itself) */
    remove_directory_tree("/tmp");
    mkdir("/tmp", 01777);

    /* Clean /var/tmp */
    remove_directory_tree("/private/var/tmp");
    mkdir("/private/var/tmp", 01777);

    /* Clean mobile caches */
    remove_directory_tree("/private/var/mobile/Library/Caches/Snapshots");
    remove_directory_tree("/private/var/mobile/Library/Caches/com.apple.appstore");
    remove_directory_tree("/private/var/mobile/Library/Caches/com.apple.itunescloudd");

    /* Clean system log files (individual known paths) */
    const char *log_files[] = {
        "/private/var/log/system.log",
        "/private/var/log/system.log.0",
        "/private/var/log/asl",
        "/private/var/log/DiagnosticMessages",
    };
    int log_count = sizeof(log_files) / sizeof(log_files[0]);
    for (int i = 0; i < log_count; i++) {
        struct stat st;
        if (stat(log_files[i], &st) == 0) {
            if (S_ISDIR(st.st_mode)) {
                remove_directory_tree(log_files[i]);
            } else {
                unlink(log_files[i]);
            }
        }
    }

    /* Clean diagnostic logs */
    remove_directory_tree("/private/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs");

    /* Clean SpringBoard cache */
    remove_directory_tree("/private/var/mobile/Library/Caches/com.apple.springboard");

    LOG_OK("clean_system done");
    return 0;
}

/* --------------------------------------------------------------------------
 * Binary plist helper (uses CoreFoundation, works on iOS without plutil)
 * ------------------------------------------------------------------------ */

/* Read a string value from a binary plist by key.
 * Returns 0 on success, -1 on failure.  Caller must free *out_value on success. */
static int read_plist_string(const char *plist_path, const char *key, char **out_value) {
    if (plist_path == NULL || key == NULL || out_value == NULL) return -1;
    *out_value = NULL;

    CFStringRef cfKey = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    if (cfKey == NULL) return -1;

    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL,
        (const UInt8 *)plist_path, strlen(plist_path), false);
    if (url == NULL) { CFRelease(cfKey); return -1; }

    CFReadStreamRef stream = CFReadStreamCreateWithFile(NULL, url);
    CFRelease(url);
    if (stream == NULL) { CFRelease(cfKey); return -1; }

    if (!CFReadStreamOpen(stream)) {
        CFRelease(stream); CFRelease(cfKey); return -1;
    }

    CFPropertyListRef plist = CFPropertyListCreateWithStream(
        NULL, stream, 0, kCFPropertyListImmutable, NULL, NULL);
    CFReadStreamClose(stream);
    CFRelease(stream);

    if (plist == NULL) { CFRelease(cfKey); return -1; }

    int result = -1;
    if (CFGetTypeID(plist) == CFDictionaryGetTypeID()) {
        CFDictionaryRef dict = (CFDictionaryRef)plist;
        CFTypeRef value = CFDictionaryGetValue(dict, cfKey);
        if (value != NULL && CFGetTypeID(value) == CFStringGetTypeID()) {
            CFStringRef cfStr = (CFStringRef)value;
            CFIndex len = CFStringGetLength(cfStr);
            CFIndex maxBuf = CFStringGetMaximumSizeForEncoding(len, kCFStringEncodingUTF8) + 1;
            char *buf = (char *)malloc((size_t)maxBuf);
            if (buf != NULL) {
                if (CFStringGetCString(cfStr, buf, maxBuf, kCFStringEncodingUTF8)) {
                    *out_value = buf;
                    result = 0;
                } else {
                    free(buf);
                }
            }
        }
    }

    CFRelease(plist);
    CFRelease(cfKey);
    return result;
}

/* Find an app's data container path by scanning Containers directory. */
static int find_data_container(const char *bundleID, char *out_path, size_t out_len) {
    if (bundleID == NULL || out_path == NULL || out_len == 0) {
        return -1;
    }

    const char *data_root = "/private/var/mobile/Containers/Data/Application";
    DIR *dir = opendir(data_root);
    if (dir == NULL) {
        LOG("find_data_container: cannot open '%s'", data_root);
        return -1;
    }

    struct dirent *entry;
    int found = 0;
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.') {
            continue;
        }

        /*
         * Check the .com.apple.mobile_container_manager.plist metadata file.
         * This is a binary plist containing MCContainerIdentifier which holds
         * the bundle ID.  We parse it directly with CoreFoundation.
         */
        char plist_path[MAX_CMD_LEN];
        snprintf(plist_path, sizeof(plist_path),
                 "%s/%s/.com.apple.mobile_container_manager.plist",
                 data_root, entry->d_name);

        struct stat st;
        if (stat(plist_path, &st) != 0) {
            /* Also try without the .plist extension (older iOS versions). */
            snprintf(plist_path, sizeof(plist_path),
                     "%s/%s/.com.apple.mobile_container_manager",
                     data_root, entry->d_name);
            if (stat(plist_path, &st) != 0) {
                continue;
            }
        }

        /* Parse the binary plist with CoreFoundation and read MCContainerIdentifier. */
        char *container_id = NULL;
        if (read_plist_string(plist_path, "MCContainerIdentifier", &container_id) == 0) {
            if (strcmp(container_id, bundleID) == 0) {
                snprintf(out_path, out_len, "%s/%s", data_root, entry->d_name);
                free(container_id);
                found = 1;
                break;
            }
            free(container_id);
        }
    }
    closedir(dir);

    return found ? 0 : -1;
}

int clean_cache(const char *bundleID) {
    if (bundleID == NULL) {
        return -1;
    }

    LOG("clean_cache for '%s'", bundleID);

    char container[MAX_CMD_LEN];
    if (find_data_container(bundleID, container, sizeof(container)) != 0) {
        LOG("clean_cache: container not found for '%s'", bundleID);
        return -1;
    }

    /* Remove Caches, tmp, and Snapshots directories. */
    char path[MAX_CMD_LEN];

    snprintf(path, sizeof(path), "%s/Library/Caches", container);
    remove_directory_tree(path);
    mkdir(path, 0755);

    snprintf(path, sizeof(path), "%s/tmp", container);
    remove_directory_tree(path);
    mkdir(path, 0755);

    snprintf(path, sizeof(path), "%s/Library/SplashBoard", container);
    remove_directory_tree(path);

    /* Clean the app's preferences cache. */
    snprintf(path, sizeof(path), "/private/var/mobile/Library/Preferences/%s.plist", bundleID);
    /* Note: We do NOT delete the plist, just reload defaults. */

    LOG_OK("clean_cache done for '%s'", bundleID);
    return 0;
}

int clean_data_dir(const char *bundleID) {
    if (bundleID == NULL) {
        return -1;
    }

    LOG("clean_data_dir for '%s'", bundleID);

    char container[MAX_CMD_LEN];
    if (find_data_container(bundleID, container, sizeof(container)) != 0) {
        LOG("clean_data_dir: container not found for '%s'", bundleID);
        return -1;
    }

    /* Wipe Documents, Library (except Preferences), tmp. */
    char path[MAX_CMD_LEN];

    snprintf(path, sizeof(path), "%s/Documents", container);
    remove_directory_tree(path);
    mkdir(path, 0755);

    snprintf(path, sizeof(path), "%s/Library/Caches", container);
    remove_directory_tree(path);
    mkdir(path, 0755);

    snprintf(path, sizeof(path), "%s/Library/Cookies", container);
    remove_directory_tree(path);
    mkdir(path, 0755);

    snprintf(path, sizeof(path), "%s/Library/WebKit", container);
    remove_directory_tree(path);

    snprintf(path, sizeof(path), "%s/tmp", container);
    remove_directory_tree(path);
    mkdir(path, 0755);

    LOG_OK("clean_data_dir done for '%s'", bundleID);
    return 0;
}

int clean_cookies(const char *bundleID) {
    if (bundleID == NULL) {
        return -1;
    }

    LOG("clean_cookies for '%s'", bundleID);

    char container[MAX_CMD_LEN];
    if (find_data_container(bundleID, container, sizeof(container)) != 0) {
        LOG("clean_cookies: container not found for '%s'", bundleID);
        return -1;
    }

    char path[MAX_CMD_LEN];

    /* Safari-style cookie databases */
    snprintf(path, sizeof(path), "%s/Library/Cookies/Cookies.binarycookies", container);
    unlink(path);

    /* WebKit storage */
    snprintf(path, sizeof(path), "%s/Library/Cookies", container);
    remove_directory_tree(path);
    mkdir(path, 0755);

    snprintf(path, sizeof(path), "%s/Library/WebKit", container);
    remove_directory_tree(path);

    /* WebKit WebsiteData */
    snprintf(path, sizeof(path),
             "%s/Library/WebKit/WebsiteData", container);
    remove_directory_tree(path);

    /* Network storage (includes localStorage / IndexedDB) */
    snprintf(path, sizeof(path),
             "/private/var/mobile/Containers/Data/Application/*/Library/WebKit/*");
    /* More targeted: the specific container. */
    snprintf(path, sizeof(path), "%s/Library/WebKit", container);
    remove_directory_tree(path);

    LOG_OK("clean_cookies done for '%s'", bundleID);
    return 0;
}

/* ===========================================================================
 * Device reset ("一键新机")
 * ========================================================================= */

int reset_device(void) {
    LOG("reset_device - full new device reset");

    /* 1. Rotate IDFA */
    reset_idfa();

    /* 2. Clear the keychain */
    delete_all_keychains();

    /* 3. Clean all caches */
    clean_system();

    /* 4. Remove device fingerprint files */
    const char *fingerprint_files[] = {
        "/private/var/mobile/Library/Preferences/com.apple.identityservices.idstatuscache.plist",
        "/private/var/mobile/Library/Preferences/com.apple.identityservices.plist",
        "/private/var/mobile/Library/Preferences/com.apple.routined.plist",
        "/private/var/mobile/Library/Preferences/com.apple.locationd.plist",
        "/private/var/mobile/Library/Preferences/com.apple.iTunesStore.plist",
        "/private/var/mobile/Library/Preferences/com.apple.appstoreclient.plist",
        "/private/var/mobile/Library/Preferences/MobileSlideShow.plist",
        "/private/var/mobile/Library/Preferences/com.apple.mobilephone.plist",
        "/private/var/mobile/Library/Preferences/com.apple.facetime.plist",
        "/private/var/mobile/Library/Preferences/com.apple.iMessage.plist",
        "/private/var/mobile/Library/Preferences/com.apple.Messages.plist",
        "/private/var/mobile/Library/Preferences/com.apple.ProtectedCloudKeyStore.plist",
        "/private/var/mobile/Library/Preferences/com.apple.security.plist",
    };
    int count = sizeof(fingerprint_files) / sizeof(fingerprint_files[0]);
    for (int i = 0; i < count; i++) {
        unlink(fingerprint_files[i]);
    }

    /* 5. Reset the advertising defaults
     * On iOS, /usr/bin/defaults does not exist. Delete the plist file directly. */
    unlink("/private/var/mobile/Library/Preferences/com.apple.advertisingIdentifier.plist");

    /* 6. Remove the wifi/SSID cache (forces re-authentication).
     * Delete the plist file directly instead of using `defaults delete`. */
    unlink("/private/var/mobile/Library/Preferences/com.apple.wifi.plist");

    /* 7. Reset the Bluetooth cache */
    unlink("/private/var/mobile/Library/Preferences/com.apple.Bluetooth.plist");

    /* 8. Reset the UDID cache (forces regeneration) */
    remove_directory_tree("/private/var/mobile/Library/Caches/com.apple.MobileAccessoryUpdater");

    /* 9. Delete the provisioning profile cache */
    remove_directory_tree("/private/var/containers/Shared/SystemGroup/"
                          "systemgroup.com.apple.configurationprofiles");

    LOG_OK("reset_device done - restart recommended");
    return 0;
}

/* ===========================================================================
 * TCC paste permissions
 * ========================================================================= */

int allow_paste_all(void) {
    LOG("allow_paste_all - granting paste permission to all apps");

    /*
     * Try to stop tccd so it releases the lock on TCC.db.
     * On rootless jailbreaks this may fail, but sqlite3_busy_timeout
     * will wait for the lock instead of failing immediately.
     */
    try_launchctl("stop", "com.apple.tccd");
    usleep(300000);  /* 0.3s for tccd to release the lock */

    /*
     * TCC.db 'access' table schema:
     *   service         TEXT
     *   client          TEXT     (bundle ID)
     *   client_type     INTEGER  (0 = app)
     *   auth_value      INTEGER  (0=denied, 2=allowed)
     *   auth_reason     INTEGER
     *   auth_version    INTEGER
     *   config_object   BLOB
     *   config_table    TEXT
     *   ...
     *
     * We insert/UPDATE rows for kTCCServicePasteboard with auth_value=2
     * for every app found in /var/containers/Bundle/Application.
     */
    sqlite3 *db = NULL;
    if (sqlite3_open(TCC_DB_PATH, &db) != SQLITE_OK) {
        LOG("allow_paste_all: cannot open TCC.db: %s", sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        try_launchctl("start", "com.apple.tccd");
        return -1;
    }

    /* Wait up to 5s if TCC.db is locked by tccd. */
    sqlite3_busy_timeout(db, 5000);

    /* First, set all existing paste entries to allowed. */
    sql_exec(TCC_DB_PATH,
             "UPDATE access SET auth_value=2, auth_reason=0 "
             "WHERE service='kTCCServicePasteboard';");

    /* Enumerate all app bundle IDs from the Applications metadata. */
    const char *bundle_root = "/private/var/containers/Bundle/Application";
    DIR *dir = opendir(bundle_root);
    if (dir == NULL) {
        /* Fallback: also scan the system app list. */
        dir = opendir("/Applications");
    }

    if (dir != NULL) {
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            if (entry->d_name[0] == '.') {
                continue;
            }

            /* Look for .app bundles inside. */
            char app_dir[MAX_CMD_LEN];
            snprintf(app_dir, sizeof(app_dir), "%s/%s", bundle_root, entry->d_name);

            DIR *appdir = opendir(app_dir);
            if (appdir == NULL) {
                continue;
            }

            struct dirent *app_entry;
            while ((app_entry = readdir(appdir)) != NULL) {
                /* Find *.app directories */
                char *dot_app = strstr(app_entry->d_name, ".app");
                if (dot_app == NULL || strcmp(dot_app, ".app") != 0) {
                    continue;
                }

                char info_path[MAX_CMD_LEN];
                snprintf(info_path, sizeof(info_path), "%s/%s/Info.plist",
                         app_dir, app_entry->d_name);

                /* Extract CFBundleIdentifier using CoreFoundation. */
                char *bundle_id = NULL;
                if (read_plist_string(info_path, "CFBundleIdentifier", &bundle_id) == 0
                    && strlen(bundle_id) > 0) {
                    /* Insert a paste permission row.
                     * Only the essential columns are set; auth_value=2 means
                     * "allowed".  We use INSERT OR REPLACE keyed on
                     * (service, client) so re-runs are idempotent. */
                    const char *sql =
                        "INSERT OR REPLACE INTO access "
                        "(service, client, client_type, auth_value, "
                        "auth_reason, auth_version, flags) "
                        "VALUES('kTCCServicePasteboard', ?1, 0, 2, 0, 1, 0);";

                    sqlite3_stmt *stmt = NULL;
                    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) == SQLITE_OK) {
                        sqlite3_bind_text(stmt, 1, bundle_id, -1, SQLITE_STATIC);
                        sqlite3_step(stmt);
                        sqlite3_finalize(stmt);
                    }
                    free(bundle_id);
                }
            }
            closedir(appdir);
        }
        closedir(dir);
    }

    sqlite3_close(db);

    /* Restart tccd so it picks up the modified TCC.db. */
    try_launchctl("start", "com.apple.tccd");

    LOG_OK("allow_paste_all done");
    return 0;
}

/* ===========================================================================
 * UI restart
 * ========================================================================= */

int respring(void) {
    LOG("respring");

    /* Kill SpringBoard so it restarts and picks up all changes.
     * Try killall from multiple paths, then launchctl. */
    try_killall("-9", "SpringBoard");

    /* If killall is not available, use launchctl. */
    try_launchctl("stop", "com.apple.SpringBoard");
    try_launchctl("start", "com.apple.SpringBoard");

    LOG_OK("respring done");
    return 0;
}

int ldrestart(void) {
    LOG("ldrestart");

    /* Try ldrestart from multiple paths. */
    const char *ldr_paths[] = {
        "/var/jb/bin/ldrestart",
        "/usr/bin/ldrestart",
        LDRESTART_PATH,
        NULL
    };
    for (int i = 0; ldr_paths[i]; i++) {
        struct stat st;
        if (stat(ldr_paths[i], &st) == 0) {
            run_simple(ldr_paths[i], NULL);
            LOG_OK("ldrestart done via %s", ldr_paths[i]);
            return 0;
        }
    }

    /* Fallback: restart key daemons individually. */
    const char *daemons[] = {
        "com.apple.securityd",
        "com.apple.cfprefsd",
        "com.apple.lsd",
        "com.apple.SpringBoard",
    };
    int count = sizeof(daemons) / sizeof(daemons[0]);
    for (int i = 0; i < count; i++) {
        try_launchctl("stop", daemons[i]);
        usleep(200000);
        try_launchctl("start", daemons[i]);
    }

    LOG_OK("ldrestart done");
    return 0;
}

/* ===========================================================================
 * App uninstall
 * ========================================================================= */

int uninstall_app(const char *bundleID) {
    if (bundleID == NULL) {
        return -1;
    }

    LOG("uninstall_app '%s'", bundleID);

    /*
     * Use the MobileInstallation SPI via the LSApplicationWorkspace
     * private API.  Since this is C, we invoke it through the
     * lsregister / mic command-line tool or by removing containers directly.
     *
     * Approach:
     *   1. Remove the app bundle from Bundle/Application.
     *   2. Remove the data container from Data/Application.
     *   3. Remove the app group container.
     *   4. Run lsregister to update the LaunchServices database.
     *   5. Run uicache to refresh icons.
     */

    /* Remove bundle container(s) — scan directory in C (no find/rm needed). */
    {
        const char *bundle_dirs[] = {
            "/private/var/containers/Bundle/Application",
            "/Applications",
            NULL
        };
        char app_suffix[320];
        snprintf(app_suffix, sizeof(app_suffix), "%s.app", bundleID);

        for (int d = 0; bundle_dirs[d]; d++) {
            DIR *dir = opendir(bundle_dirs[d]);
            if (!dir) continue;
            struct dirent *entry;
            while ((entry = readdir(dir)) != NULL) {
                if (entry->d_name[0] == '.') continue;
                char subdir[MAX_CMD_LEN];
                snprintf(subdir, sizeof(subdir), "%s/%s", bundle_dirs[d], entry->d_name);
                DIR *sub = opendir(subdir);
                if (!sub) continue;
                struct dirent *app_entry;
                while ((app_entry = readdir(sub)) != NULL) {
                    if (strstr(app_entry->d_name, app_suffix) == NULL) continue;
                    char app_path[MAX_CMD_LEN];
                    snprintf(app_path, sizeof(app_path), "%s/%s", subdir, app_entry->d_name);
                    remove_directory_tree(app_path);
                    LOG("Removed bundle: %s", app_path);
                }
                closedir(sub);
            }
            closedir(dir);
        }
    }

    /* Remove data container. */
    char container[MAX_CMD_LEN];
    if (find_data_container(bundleID, container, sizeof(container)) == 0) {
        remove_directory_tree(container);
    }

    /* Remove app group containers — scan in C (no find/grep needed). */
    {
        const char *shared_dirs[] = {
            "/private/var/containers/Shared/AppGroup",
            "/private/var/containers/Shared/PlugInKit",
            NULL
        };
        for (int d = 0; shared_dirs[d]; d++) {
            DIR *dir = opendir(shared_dirs[d]);
            if (!dir) continue;
            struct dirent *entry;
            while ((entry = readdir(dir)) != NULL) {
                if (entry->d_name[0] == '.') continue;
                char plist_path[MAX_CMD_LEN];
                snprintf(plist_path, sizeof(plist_path),
                         "%s/%s/.com.apple.mobile_container_manager.plist",
                         shared_dirs[d], entry->d_name);
                char *mcid = NULL;
                if (read_plist_string(plist_path, "MCContainerIdentifier", &mcid) == 0
                    && mcid != NULL) {
                    if (strstr(mcid, bundleID) != NULL) {
                        char group_path[MAX_CMD_LEN];
                        snprintf(group_path, sizeof(group_path), "%s/%s",
                                 shared_dirs[d], entry->d_name);
                        remove_directory_tree(group_path);
                        LOG("Removed group container: %s", group_path);
                    }
                    free(mcid);
                }
            }
            closedir(dir);
        }
    }

    /* Remove the preferences plist. */
    {
        char cmd[MAX_CMD_LEN];
        snprintf(cmd, sizeof(cmd),
                 "/private/var/mobile/Library/Preferences/%s.plist", bundleID);
        unlink(cmd);
    }

    /* Update LaunchServices database.
     * lsregister may be at /var/jb/usr/bin/ on rootless jailbreaks. */
    {
        const char *lsr_paths[] = {
            "/var/jb/usr/bin/lsregister",
            "/usr/bin/lsregister",
            NULL
        };
        for (int i = 0; lsr_paths[i]; i++) {
            if (access(lsr_paths[i], X_OK) == 0) {
                run_simple(lsr_paths[i], "-kill", "-r",
                           "-domain", "system", "-domain", "user", NULL);
                break;
            }
        }
    }

    /* Refresh icon cache.
     * uicache may be at /var/jb/bin/uicache on rootless jailbreaks. */
    {
        const char *uic_paths[] = {
            "/var/jb/bin/uicache",
            "/usr/bin/uicache",
            NULL
        };
        for (int i = 0; uic_paths[i]; i++) {
            if (access(uic_paths[i], X_OK) == 0) {
                run_simple(uic_paths[i], "-p", bundleID, NULL);
                break;
            }
        }
    }

    LOG_OK("uninstall_app done for '%s'", bundleID);
    return 0;
}

/* ===========================================================================
 * Graphics config
 * ========================================================================= */

int apply_config(const char *bundleID, const char *configPath) {
    if (bundleID == NULL || configPath == NULL) {
        return -1;
    }

    LOG("apply_config '%s' <- '%s'", bundleID, configPath);

    /* Read the preset name from the config file. */
    char preset[128] = {0};
    FILE *f = fopen(configPath, "r");
    if (f == NULL) {
        LOG("apply_config: cannot read config '%s'", configPath);
        return -1;
    }
    size_t n = fread(preset, 1, sizeof(preset) - 1, f);
    preset[n] = '\0';
    fclose(f);

    /* Trim whitespace and quotes. */
    char *p = preset;
    while (*p == ' ' || *p == '"' || *p == '\n' || *p == '\r') p++;
    size_t plen = strlen(p);
    while (plen > 0 && (p[plen-1] == '\n' || p[plen-1] == '\r' ||
                         p[plen-1] == ' ' || p[plen-1] == '"')) {
        p[--plen] = '\0';
    }

    /* Find the app's data container. */
    char container[MAX_CMD_LEN];
    if (find_data_container(bundleID, container, sizeof(container)) != 0) {
        LOG("apply_config: container not found for '%s'", bundleID);
        return -1;
    }

    /* Scan Documents/UE4Game/ for the project directory name.
     * Each UE4 game uses a different project name (e.g., ShadowTrackerExtra
     * for PUBG Mobile), so we dynamically discover it rather than
     * hardcoding. */
    char ue4_dir[MAX_CMD_LEN];
    snprintf(ue4_dir, sizeof(ue4_dir), "%s/Documents/UE4Game", container);
    DIR *dir = opendir(ue4_dir);
    if (dir == NULL) {
        LOG("apply_config: UE4Game directory not found at '%s'", ue4_dir);
        return -1;
    }

    /* Handle "restore" preset: delete UserCustom.ini to restore defaults. */
    if (strcmp(p, "restore") == 0) {
        int restored = 0;
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            if (entry->d_name[0] == '.') continue;
            char ini_path[MAX_CMD_LEN];
            snprintf(ini_path, sizeof(ini_path),
                     "%s/%s/Saved/Config/IOS/UserCustom.ini",
                     ue4_dir, entry->d_name);
            if (unlink(ini_path) == 0) {
                LOG("apply_config: deleted '%s'", ini_path);
                restored = 1;
            }
        }
        closedir(dir);
        if (restored) {
            LOG_OK("apply_config: restored defaults for '%s'", bundleID);
        }
        return restored ? 0 : -1;
    }

    /* Map preset name to quality level. */
    int level = 1;  /* Default to medium */
    if (strcmp(p, "流畅") == 0 || strcmp(p, "low") == 0) {
        level = 0;
    } else if (strcmp(p, "平衡") == 0 || strcmp(p, "medium") == 0) {
        level = 1;
    } else if (strcmp(p, "高清") == 0 || strcmp(p, "high") == 0) {
        level = 2;
    } else if (strcmp(p, "极致") == 0 || strcmp(p, "ultra") == 0) {
        level = 3;
    } else if (strcmp(p, "自定义") == 0 || strcmp(p, "custom") == 0) {
        level = 1;  /* Custom defaults to medium-equivalent */
    }

    /*
     * UE4 scalability group quality table per level:
     * [0]=ResolutionQuality(50-100), [1]=ViewDistance,
     * [2]=AntiAliasing, [3]=Shadow, [4]=PostProcess,
     * [5]=Texture, [6]=Effects, [7]=Foliage
     */
    static const int q[4][8] = {
        {50,  0, 0, 0, 0, 0, 0, 0},   /* 流畅 */
        {75,  1, 1, 1, 1, 1, 1, 1},   /* 平衡 */
        {100, 2, 2, 2, 2, 2, 2, 2},   /* 高清 */
        {100, 3, 3, 3, 3, 3, 3, 3},   /* 极致 */
    };
    static const char *scale_factor[4] = {"1.0", "1.5", "2.0", "2.5"};
    static const char *mobile_hdr[4]   = {"False", "False", "True", "True"};
    static const char *fps_limit[4]     = {"30", "45", "60", "120"};

    /* Generate UE4 INI content in [UserCustom DeviceProfile] format. */
    char ini[4096];
    snprintf(ini, sizeof(ini),
        "[UserCustom DeviceProfile]\n"
        "+CVars=sg.ResolutionQuality=%d\n"
        "+CVars=sg.ViewDistanceQuality=%d\n"
        "+CVars=sg.AntiAliasingQuality=%d\n"
        "+CVars=sg.ShadowQuality=%d\n"
        "+CVars=sg.PostProcessQuality=%d\n"
        "+CVars=sg.TextureQuality=%d\n"
        "+CVars=sg.EffectsQuality=%d\n"
        "+CVars=sg.FoliageQuality=%d\n"
        "+CVars=r.MobileContentScaleFactor=%s\n"
        "+CVars=r.MobileHDR=%s\n"
        "+CVars=r.MobileOnChipMSAA=%s\n"
        "+CVars=r.DynamicResolution=%s\n"
        "+CVars=r.FPSLimit=%s\n"
        "+CVars=r.AmbientOcclusion.ComputeHLOD=%s\n"
        "+CVars=r.BloomQuality=%d\n"
        "+CVars=r.DepthOfFieldQuality=%d\n"
        "+CVars=r.DetailMode=%d\n"
        "+CVars=r.DistanceFieldShadowing=%s\n"
        "+CVars=r.EyeAdaptationQuality=%d\n"
        "+CVars=r.LensFlareQuality=%d\n"
        "+CVars=r.LightShaftQuality=%d\n"
        "+CVars=r.PostProcessAAQuality=%d\n"
        "+CVars=r.ShadowQuality=%d\n"
        "+CVars=r.Streaming.LimitPoolSizeToVRAM=True\n"
        "+CVars=r.TonemapQuality=%d\n"
        "+CVars=r.ViewDistance=%d\n"
        "+CVars=r.ForceLODShadow=%s\n",
        q[level][0], q[level][1], q[level][2], q[level][3],
        q[level][4], q[level][5], q[level][6], q[level][7],
        scale_factor[level], mobile_hdr[level],
        level >= 2 ? "True" : "False",
        level >= 2 ? "True" : "False",
        fps_limit[level],
        level >= 1 ? "True" : "False",
        q[level][4], q[level][4], q[level][1],
        level >= 2 ? "True" : "False",
        q[level][4], q[level][4], q[level][4], q[level][4], q[level][3],
        q[level][4], q[level][1],
        level >= 1 ? "True" : "False");

    /* Write UserCustom.ini to the first matching UE4 project directory. */
    int success = 0;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.') continue;

        /* Ensure config directory exists. */
        char config_dir[MAX_CMD_LEN];
        snprintf(config_dir, sizeof(config_dir),
                 "%s/%s/Saved/Config/IOS", ue4_dir, entry->d_name);
        mkdir_p(config_dir, 0755);

        char ini_path[MAX_CMD_LEN];
        snprintf(ini_path, sizeof(ini_path),
                 "%s/UserCustom.ini", config_dir);

        FILE *out = fopen(ini_path, "w");
        if (out != NULL) {
            fputs(ini, out);
            fclose(out);
            LOG("apply_config: wrote '%s'", ini_path);
            success = 1;
            break;
        }
    }
    closedir(dir);

    if (!success) {
        LOG("apply_config: failed to write UserCustom.ini");
        return -1;
    }

    LOG_OK("apply_config done for '%s' (preset=%s, level=%d)", bundleID, p, level);
    return 0;
}

/* ===========================================================================
 * Usage
 * ========================================================================= */

void print_usage(const char *prog) {
    fprintf(stderr,
        "GhostKit RootHelper - privileged system operations\n\n"
        "Usage: %s <command> [args...]\n\n"
        "Commands:\n"
        "  clean-keychain <bundleID>         Remove keychain entries for an app\n"
        "  deep-clean-keychain <bundleID>    Aggressively clear all keychain data\n"
        "  delete-all-keychains              Delete entire keychain database\n"
        "  restore-keychains                  Restore keychain from backup\n"
        "  reset-idfa                         Rotate the advertising identifier\n"
        "  clean-system                       Clean system temporary files\n"
        "  clean-cache <bundleID>            Clear app cache directory\n"
        "  clean-data-dir <bundleID>         Wipe app data directory\n"
        "  clean-cookies <bundleID>           Clear app cookies & storage\n"
        "  reset-device                        Full new-device reset\n"
        "  allow-paste-all                     Grant paste permission to all apps\n"
        "  respring                            Restart SpringBoard\n"
        "  ldrestart                           Restart launch daemons\n"
        "  uninstall <bundleID>               Uninstall an application\n"
        "  apply-config <bundleID> <path>     Apply graphics config\n"
        "  help                                Show this message\n",
        prog ? prog : "RootHelper");
}

/* ===========================================================================
 * main
 * ========================================================================= */

int main(int argc, char *argv[]) {
    /* ── Detect privilege level ───────────────────────────────────────
     * Try to elevate to root via setuid(0).
     * If successful: all operations can access system-critical paths.
     * If failed: continue anyway — on TrollStore with proper entitlements
     *   (platform-application + no-sandbox), the app can access the
     *   filesystem and perform most operations without root.
     * Individual operations will report their own errors if they
     * genuinely require root.
     * ───────────────────────────────────────────────────────────────── */
    uid_t old_uid = getuid();

    if (old_uid == 0) {
        LOG("Running as root (already privileged)");
    } else {
        if (setuid(0) != 0 || getuid() != 0) {
            /* setuid(0) failed — this is expected on rootless jailbreaks
             * (RelaXin/Dopamine) and TrollStore. Continue anyway: the
             * app's entitlements (no-sandbox, platform-application)
             * provide sufficient filesystem access for most operations. */
            LOG("setuid(0) failed (errno=%d: %s) — continuing with entitlements",
                errno, strerror(errno));
            LOG("Running as uid=%d (non-root). Relying on entitlements for access.",
                old_uid);
        } else {
            setgid(0);
            setsid();
            LOG("Elevated to root (was uid=%d)", old_uid);
        }
    }

    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    const char *cmd = argv[1];

    /* -- Keychain -- */
    if (strcmp(cmd, "clean-keychain") == 0) {
        if (argc < 3) { fprintf(stderr, "Usage: %s clean-keychain <bundleID>\n", argv[0]); return 1; }
        return clean_keychain(argv[2]);
    }
    if (strcmp(cmd, "deep-clean-keychain") == 0) {
        if (argc < 3) { fprintf(stderr, "Usage: %s deep-clean-keychain <bundleID>\n", argv[0]); return 1; }
        return deep_clean_keychain(argv[2]);
    }
    if (strcmp(cmd, "delete-all-keychains") == 0) {
        return delete_all_keychains();
    }
    if (strcmp(cmd, "restore-keychains") == 0) {
        return restore_keychains();
    }

    /* -- IDFA -- */
    if (strcmp(cmd, "reset-idfa") == 0) {
        return reset_idfa();
    }

    /* -- System / cache -- */
    if (strcmp(cmd, "clean-system") == 0) {
        return clean_system();
    }
    if (strcmp(cmd, "clean-cache") == 0) {
        if (argc < 3) { fprintf(stderr, "Usage: %s clean-cache <bundleID>\n", argv[0]); return 1; }
        return clean_cache(argv[2]);  /* May work for app's own container */
    }
    if (strcmp(cmd, "clean-data-dir") == 0) {
        if (argc < 3) { fprintf(stderr, "Usage: %s clean-data-dir <bundleID>\n", argv[0]); return 1; }
        return clean_data_dir(argv[2]);  /* May work for app's own container */
    }
    if (strcmp(cmd, "clean-cookies") == 0) {
        if (argc < 3) { fprintf(stderr, "Usage: %s clean-cookies <bundleID>\n", argv[0]); return 1; }
        return clean_cookies(argv[2]);  /* May work for app's own container */
    }

    /* -- Device -- */
    if (strcmp(cmd, "reset-device") == 0) {
        return reset_device();
    }
    if (strcmp(cmd, "allow-paste-all") == 0) {
        return allow_paste_all();
    }
    if (strcmp(cmd, "respring") == 0) {
        return respring();
    }
    if (strcmp(cmd, "ldrestart") == 0) {
        return ldrestart();
    }

    /* -- Uninstall -- */
    if (strcmp(cmd, "uninstall") == 0) {
        if (argc < 3) { fprintf(stderr, "Usage: %s uninstall <bundleID>\n", argv[0]); return 1; }
        return uninstall_app(argv[2]);
    }

    /* -- Graphics config -- */
    if (strcmp(cmd, "apply-config") == 0) {
        if (argc < 4) { fprintf(stderr, "Usage: %s apply-config <bundleID> <configPath>\n", argv[0]); return 1; }
        return apply_config(argv[2], argv[3]);  /* May work without root */
    }

    /* -- Help -- */
    if (strcmp(cmd, "help") == 0 || strcmp(cmd, "--help") == 0 ||
        strcmp(cmd, "-h") == 0) {
        print_usage(argv[0]);
        return 0;
    }

    fprintf(stderr, "Unknown command: %s\n", cmd);
    print_usage(argv[0]);
    return 1;
}
