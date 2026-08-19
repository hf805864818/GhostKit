/*
 * RootHelper.h
 * GhostKit
 *
 * RootHelper - a privileged C helper bundled inside the GhostKit .app.
 * It is spawned by RootHelperManager (Swift) to perform root-level system
 * operations: keychain manipulation, IDFA rotation, cache cleaning, device
 * reset, TCC paste permissions, respring, app uninstall and graphics config.
 *
 * Compile:  cc -arch arm64 -isysroot $SDK -o RootHelper RootHelper.c -lsqlite3
 */

#ifndef GHOSTKIT_ROOTHELPER_H
#define GHOSTKIT_ROOTHELPER_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <errno.h>
#include <fts.h>

/* ---------------------------------------------------------------------------
 * Constants
 * ------------------------------------------------------------------------- */

/* iOS keychain database path (root only). */
#define KEYCHAIN_DB_PATH        "/private/var/Keychains/keychain-2.db"

/* iOS keychain backup directory. */
#define KEYCHAIN_BACKUP_DIR     "/private/var/Keychains/backup"

/* TCC database (per-device permissions). */
#define TCC_DB_PATH             "/private/var/mobile/Library/TCC/TCC.db"

/* IDFA storage file (advertising identifier). */
#define IDFA_DB_PATH            "/private/var/mobile/Library/com.apple.adcenterd/IDFA.db"

/* iOS system temporary directories. */
#define TMP_DIR                 "/tmp"
#define VAR_TMP_DIR             "/private/var/tmp"
#define CACHES_DIR              "/private/var/mobile/Library/Caches"

/* LaunchServices daemon restart. */
#define LDRESTART_PATH          "/usr/bin/ldrestart"
#define KILLALL_PATH            "/usr/bin/killall"

/* Maximum command-line length used by the spawn helper. */
#define MAX_CMD_LEN             4096

/* SQLite result success. */
#ifndef SQLITE_OK
#include <sqlite3.h>
#endif

/* ---------------------------------------------------------------------------
 * Spawn helpers
 * ------------------------------------------------------------------------- */

/**
 * Run an external command as root via posix_spawn.
 * Returns the child's exit status, or -1 on failure.
 */
int run_root_command(const char *command, const char *const argv[]);

/**
 * Convenience wrapper: run a single binary with variadic argv ending in NULL.
 */
int run_simple(const char *binary, ...);

/* ---------------------------------------------------------------------------
 * Keychain operations (sqlite3 backed)
 * ------------------------------------------------------------------------- */

/**
 * Remove keychain entries for a specific bundle identifier.
 * Deletes rows whose access group or acct matches bundleID.
 */
int clean_keychain(const char *bundleID);

/**
 * Aggressively remove every keychain entry for bundleID across all groups.
 */
int deep_clean_keychain(const char *bundleID);

/**
 * Delete the entire keychain database contents (all tables truncated).
 * A backup copy is created in KEYCHAIN_BACKUP_DIR first.
 */
int delete_all_keychains(void);

/**
 * Restore the keychain database from the backup created by delete_all_keychains.
 */
int restore_keychains(void);

/* ---------------------------------------------------------------------------
 * IDFA
 * ------------------------------------------------------------------------- */

/**
 * Delete the stored advertising identifier so iOS rotates it on next request.
 */
int reset_idfa(void);

/* ---------------------------------------------------------------------------
 * System & cache cleaning
 * ------------------------------------------------------------------------- */

/**
 * Clean common system temporary directories (/tmp, /var/tmp, Caches).
 */
int clean_system(void);

/**
 * Clear cache, cookies and temporary files for an application data container.
 */
int clean_cache(const char *bundleID);

/**
 * Wipe the data directory of an app (Documents/Library/Caches).
 */
int clean_data_dir(const char *bundleID);

/**
 * Clear web cookies and local storage for an app.
 */
int clean_cookies(const char *bundleID);

/* ---------------------------------------------------------------------------
 * Device reset
 * ------------------------------------------------------------------------- */

/**
 * Full "new device" reset: rotate IDFA, clear keychains, wipe caches,
 * remove device fingerprint files.
 */
int reset_device(void);

/* ---------------------------------------------------------------------------
 * TCC paste permissions
 * ------------------------------------------------------------------------- */

/**
 * Grant the paste (clipboard read) permission to every installed app by
 * inserting rows into TCC.db for the kTCCServicePaste service.
 */
int allow_paste_all(void);

/* ---------------------------------------------------------------------------
 * UI restart
 * ------------------------------------------------------------------------- */

/**
 * Restart SpringBoard (used after keychain / TCC changes).
 */
int respring(void);

/**
 * Restart all launch daemons (ldrestart).
 */
int ldrestart(void);

/* ---------------------------------------------------------------------------
 * App uninstall
 * ------------------------------------------------------------------------- */

/**
 * Uninstall an application by bundle identifier using mobileinstall SPI.
 */
int uninstall_app(const char *bundleID);

/* ---------------------------------------------------------------------------
 * Graphics config
 * ------------------------------------------------------------------------- */

/**
 * Apply a graphics quality config (JSON file) to an application by writing
 * preference overrides into its container.
 */
int apply_config(const char *bundleID, const char *configPath);

/* ---------------------------------------------------------------------------
 * Utility
 * ------------------------------------------------------------------------- */

/**
 * Remove a directory tree recursively. Returns 0 on success.
 */
int remove_directory_tree(const char *path);

/**
 * Copy a file from src to dst. Returns 0 on success.
 */
int copy_file(const char *src, const char *dst);

/**
 * Print a usage message to stderr.
 */
void print_usage(const char *prog);

#endif /* GHOSTKIT_ROOTHELPER_H */
