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
#import <stdlib.h>

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
            system([[NSString stringWithFormat:@"ldid -S '%@'", execPath] UTF8String]);
            return YES;
        }
    }

    // 4. Use insert_dylib to add the LC_LOAD_DYLIB load command.
    NSString *command = [NSString stringWithFormat:
        @"insert_dylib --inplace '%@' '%@' 2>&1", loadPath, execPath];

    // Try insert_dylib first.
    int ret = system([command UTF8String]);
    if (ret != 0) {
        NSLog(@"[GhostKit] insert_dylib failed (code %d), trying optool...", ret);

        // Fallback: optool
        NSString *optoolCommand = [NSString stringWithFormat:
            @"optool install -c load -p '%@' -t '%@' 2>&1", loadPath, execPath];
        ret = system([optoolCommand UTF8String]);
        if (ret != 0) {
            NSLog(@"[GhostKit] optool also failed (code %d)", ret);
            // Try manual restoration of backup.
            [fm removeItemAtPath:execPath error:nil];
            [fm copyItemAtPath:backupPath toPath:execPath error:nil];
            return NO;
        }
    }

    // 5. Re-sign the binary and the dylib with ldid.
    system([[NSString stringWithFormat:@"ldid -S '%@'", execPath] UTF8String]);
    system([[NSString stringWithFormat:@"ldid -S '%@'", destDylibPath] UTF8String]);

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
        NSString *command = [NSString stringWithFormat:
            @"optool uninstall -c load -p '%@' -t '%@' 2>&1", loadPath, execPath];
        system([command UTF8String]);
    }

    // 2. Remove the dylib from the bundle.
    if ([fm fileExistsAtPath:destDylibPath]) {
        [fm removeItemAtPath:destDylibPath error:nil];
    }

    // 3. Re-sign.
    system([[NSString stringWithFormat:@"ldid -S '%@'", execPath] UTF8String]);

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
