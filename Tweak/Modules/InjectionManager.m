//
//  InjectionManager.m
//  GhostKit
//
//  Uses the `insert_dylib` command-line tool to modify Mach-O LC_LOAD_DYLIB
//  load commands, and `ldid` for re-signing.  Also parses Mach-O headers
//  directly to enumerate existing load commands.
//

#import "InjectionManager.h"
#import "AppListManager.h"
#import <mach-o/loader.h>
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;

/// Get the path to a bundled tool binary.
/// Tweak injects into the target app process, so tools are not in
/// our own bundle. We search known TrollStore app paths.
static NSString *toolPath(NSString *name) {
    // Try multiple possible GhostKit app bundle locations
    NSArray *searchPaths = @[
        @"/var/containers/Bundle/Application",
        @"/Applications",
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *searchDir in searchPaths) {
        NSArray *subdirs = [fm contentsOfDirectoryAtPath:searchDir error:nil];
        for (NSString *subdir in subdirs) {
            NSString *appDir = [searchDir stringByAppendingPathComponent:subdir];
            NSArray *contents = [fm contentsOfDirectoryAtPath:appDir error:nil];
            for (NSString *item in contents) {
                if ([item hasSuffix:@".app"]) {
                    NSString *appPath = [appDir stringByAppendingPathComponent:item];
                    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
                    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
                    NSString *bid = info[@"CFBundleIdentifier"];
                    // Match GhostKit app by bundle ID prefix
                    if ([bid hasPrefix:@"apple.ghostkit"] || [bid hasPrefix:@"com.ghostkit"]) {
                        NSString *tool = [appPath stringByAppendingPathComponent:name];
                        if ([fm fileExistsAtPath:tool]) {
                            return tool;
                        }
                    }
                }
            }
        }
    }
    // Fallback: assume tool is in PATH
    return name;
}

/// Run a command with arguments via posix_spawnp, returning the exit code.
/// Replaces system() which is unavailable in the iOS SDK.
/// Tools are looked up from the GhostKit app bundle first.
static int runSpawnCommand(NSString *cmd, NSArray<NSString *> *args) {
    if (!cmd || cmd.length == 0) {
        return -1;
    }

    // Resolve tool path from GhostKit app bundle
    NSString *resolvedPath = toolPath(cmd);

    NSUInteger argc = args.count + 2;  // path + args + NULL
    const char **cArgv = calloc(argc, sizeof(const char *));
    if (!cArgv) {
        return -1;
    }

    cArgv[0] = [resolvedPath UTF8String];
    for (NSUInteger i = 0; i < args.count; i++) {
        cArgv[i + 1] = [args[i] UTF8String];
    }
    cArgv[args.count + 1] = NULL;

    pid_t pid = 0;
    int spawnResult = posix_spawnp(&pid, [resolvedPath UTF8String], NULL, NULL,
                                   (char *const *)cArgv, environ);
    free(cArgv);

    if (spawnResult != 0) {
        return spawnResult;
    }

    int status = 0;
    waitpid(pid, &status, 0);

    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return -1;
}

@implementation InjectionManager

+ (instancetype)sharedInstance {
    static InjectionManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[InjectionManager alloc] init];
    });
    return instance;
}

#pragma mark - Helpers

- (NSString *)executablePathForBundleID:(NSString *)bundleID {
    AppInfo *appInfo = [[AppListManager sharedInstance] getAppInfoWithBundleID:bundleID];
    if (!appInfo || !appInfo.bundlePath) {
        return nil;
    }

    // Read CFBundleExecutable from Info.plist.
    NSString *infoPlistPath = [appInfo.bundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
    NSString *execName = info[@"CFBundleExecutable"] ?: bundleID;

    return [appInfo.bundlePath stringByAppendingPathComponent:execName];
}

- (NSString *)backupPathForExecutable:(NSString *)execPath {
    return [execPath stringByAppendingString:@".GhostKit.orig"];
}

#pragma mark - Inject

- (BOOL)injectDylib:(NSString *)dylibPath forBundleID:(NSString *)bundleID {
    if (!dylibPath || !bundleID || dylibPath.length == 0 || bundleID.length == 0) {
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dylibPath]) {
        NSLog(@"[GhostKit] Dylib not found: %@", dylibPath);
        return NO;
    }

    AppInfo *appInfo = [[AppListManager sharedInstance] getAppInfoWithBundleID:bundleID];
    if (!appInfo || !appInfo.bundlePath) {
        NSLog(@"[GhostKit] App not found: %@", bundleID);
        return NO;
    }

    NSString *execPath = [self executablePathForBundleID:bundleID];
    if (!execPath) {
        NSLog(@"[GhostKit] Cannot resolve executable for %@", bundleID);
        return NO;
    }

    NSString *bundlePath = appInfo.bundlePath;
    NSString *dylibName = [dylibPath lastPathComponent];
    NSString *destDylibPath = [bundlePath stringByAppendingPathComponent:dylibName];

    // 1. Copy the dylib into the app bundle (520.dylib pattern).
    if (![fm fileExistsAtPath:destDylibPath]) {
        NSError *copyError = nil;
        if (![fm copyItemAtPath:dylibPath toPath:destDylibPath error:&copyError]) {
            NSLog(@"[GhostKit] Failed to copy dylib: %@", copyError);
            return NO;
        }
    }

    // 2. Backup the original binary.
    NSString *backupPath = [self backupPathForExecutable:execPath];
    if (![fm fileExistsAtPath:backupPath]) {
        [fm copyItemAtPath:execPath toPath:backupPath error:nil];
    }

    // 3. Check if already injected.
    NSArray *existingDylibs = [self getInjectedDylibsForBundleID:bundleID];
    NSString *loadPath = [NSString stringWithFormat:@"@executable_path/%@", dylibName];
    for (NSString *existing in existingDylibs) {
        if ([existing isEqualToString:loadPath] || [existing containsString:dylibName]) {
            NSLog(@"[GhostKit] Dylib %@ already injected in %@", dylibName, bundleID);
            // Still re-sign to be safe.
            runSpawnCommand(@"ldid", @[@"-S", execPath]);
            return YES;
        }
    }

    // 4. Use insert_dylib to add the LC_LOAD_DYLIB load command.
    // Try insert_dylib first.
    int ret = runSpawnCommand(@"insert_dylib", @[@"--inplace", loadPath, execPath]);
    if (ret != 0) {
        NSLog(@"[GhostKit] insert_dylib failed (code %d), trying optool...", ret);

        // Fallback: optool
        ret = runSpawnCommand(@"optool", @[@"install", @"-c", @"load", @"-p", loadPath, @"-t", execPath]);
        if (ret != 0) {
            NSLog(@"[GhostKit] optool also failed (code %d)", ret);
            // Try manual restoration of backup.
            [fm removeItemAtPath:execPath error:nil];
            [fm copyItemAtPath:backupPath toPath:execPath error:nil];
            return NO;
        }
    }

    // 5. Re-sign the binary and the dylib with ldid.
    runSpawnCommand(@"ldid", @[@"-S", execPath]);
    runSpawnCommand(@"ldid", @[@"-S", destDylibPath]);

    NSLog(@"[GhostKit] injectDylib:%@ forBundleID:%@ -> YES", dylibName, bundleID);
    return YES;
}

#pragma mark - Remove

- (BOOL)removeDylib:(NSString *)dylibPath forBundleID:(NSString *)bundleID {
    if (!dylibPath || !bundleID) {
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    AppInfo *appInfo = [[AppListManager sharedInstance] getAppInfoWithBundleID:bundleID];
    if (!appInfo || !appInfo.bundlePath) {
        return NO;
    }

    NSString *execPath = [self executablePathForBundleID:bundleID];
    if (!execPath) {
        return NO;
    }

    NSString *backupPath = [self backupPathForExecutable:execPath];
    NSString *bundlePath = appInfo.bundlePath;
    NSString *dylibName = [dylibPath lastPathComponent];
    NSString *destDylibPath = [bundlePath stringByAppendingPathComponent:dylibName];

    // 1. Restore the original binary from backup.
    if ([fm fileExistsAtPath:backupPath]) {
        [fm removeItemAtPath:execPath error:nil];
        [fm copyItemAtPath:backupPath toPath:execPath error:nil];
        [fm removeItemAtPath:backupPath error:nil];
    } else {
        // No backup available; try optool uninstall.
        NSString *loadPath = [NSString stringWithFormat:@"@executable_path/%@", dylibName];
        runSpawnCommand(@"optool", @[@"uninstall", @"-c", @"load", @"-p", loadPath, @"-t", execPath]);
    }

    // 2. Remove the dylib from the bundle.
    if ([fm fileExistsAtPath:destDylibPath]) {
        [fm removeItemAtPath:destDylibPath error:nil];
    }

    // 3. Re-sign.
    runSpawnCommand(@"ldid", @[@"-S", execPath]);

    NSLog(@"[GhostKit] removeDylib:%@ forBundleID:%@ -> YES", dylibName, bundleID);
    return YES;
}

#pragma mark - Get injected dylibs

- (NSArray<NSString *> *)getInjectedDylibsForBundleID:(NSString *)bundleID {
    NSMutableArray *dylibs = [NSMutableArray array];
    if (!bundleID) {
        return dylibs;
    }

    NSString *execPath = [self executablePathForBundleID:bundleID];
    if (!execPath) {
        return dylibs;
    }

    NSData *data = [NSData dataWithContentsOfFile:execPath];
    if (!data || data.length < sizeof(struct mach_header_64)) {
        return dylibs;
    }

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    const struct mach_header_64 *header = (const struct mach_header_64 *)bytes;

    // Check magic for 64-bit Mach-O.
    if (header->magic != MH_MAGIC_64) {
        // Try 32-bit.
        if (data.length >= sizeof(struct mach_header)) {
            const struct mach_header *header32 = (const struct mach_header *)bytes;
            if (header32->magic == MH_MAGIC) {
                uintptr_t ptr = sizeof(struct mach_header);
                for (uint32_t i = 0; i < header32->ncmds; i++) {
                    const struct load_command *cmd =
                        (const struct load_command *)(bytes + ptr);
                    if (cmd->cmd == LC_LOAD_DYLIB || cmd->cmd == LC_LOAD_WEAK_DYLIB) {
                        const struct dylib_command *dylib_cmd =
                            (const struct dylib_command *)cmd;
                        const char *name = (const char *)(bytes + ptr + dylib_cmd->dylib.name.offset);
                        if (name) {
                            [dylibs addObject:[NSString stringWithUTF8String:name]];
                        }
                    }
                    ptr += cmd->cmdsize;
                }
                return dylibs;
            }
        }
        return dylibs;
    }

    // 64-bit.
    uintptr_t ptr = sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *cmd =
            (const struct load_command *)(bytes + ptr);
        if (cmd->cmd == LC_LOAD_DYLIB || cmd->cmd == LC_LOAD_WEAK_DYLIB) {
            const struct dylib_command *dylib_cmd =
                (const struct dylib_command *)cmd;
            const char *name = (const char *)(bytes + ptr + dylib_cmd->dylib.name.offset);
            if (name) {
                [dylibs addObject:[NSString stringWithUTF8String:name]];
            }
        }
        ptr += cmd->cmdsize;
    }

    return dylibs;
}

@end
