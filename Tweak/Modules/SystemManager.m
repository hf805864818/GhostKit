//
//  SystemManager.m
//  GhostKit
//
//  Uses multi-path binary search for rootless jailbreak compatibility.
//

#import "SystemManager.h"
#import <stdlib.h>
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

@implementation SystemManager

+ (instancetype)sharedInstance {
    static SystemManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SystemManager alloc] init];
    });
    return instance;
}

#pragma mark - Binary path search (rootless compatible)

/// Find an executable binary by trying multiple paths.
/// On rootless jailbreaks, binaries are at /var/jb/bin/.
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

/// Spawn a binary with arguments using posix_spawn.
- (void)spawnBinary:(NSString *)path withArgs:(NSArray<NSString *> *)args {
    if (!path) return;

    // Build C argv array.
    int argc = (int)(1 + args.count + 1);
    char **argv = (char **)malloc(sizeof(char *) * argc);
    if (!argv) return;

    argv[0] = strdup([path UTF8String]);
    for (NSUInteger i = 0; i < args.count; i++) {
        argv[i + 1] = strdup([args[i] UTF8String]);
    }
    argv[argc - 1] = NULL;

    pid_t pid = 0;
    posix_spawn(&pid, [path UTF8String], NULL, NULL, argv, environ);

    // Free argv.
    for (int i = 0; i < argc - 1; i++) {
        if (argv[i]) free(argv[i]);
    }
    free(argv);

    // Wait for the process to complete.
    if (pid > 0) {
        int status = 0;
        waitpid(pid, &status, 0);
    }
}

#pragma mark - Safe exit

- (void)safeExit {
    NSLog(@"[GhostKit] safeExit");

    // Flush standard streams.
    fflush(stdout);
    fflush(stderr);

    // Notify and exit cleanly.
    exit(0);
}

#pragma mark - Respring

- (void)respring {
    NSLog(@"[GhostKit] respring");

    // Method 1: killall SpringBoard (most reliable on jailbroken devices).
    NSString *killallPath = [self findBinary:@"killall"];
    if (killallPath) {
        [self spawnBinary:killallPath withArgs:@[@"-9", @"SpringBoard"]];
        return;
    }

    // Method 2: Try sbreload.
    NSString *sbreloadPath = [self findBinary:@"sbreload"];
    if (sbreloadPath) {
        [self spawnBinary:sbreloadPath withArgs:@[]];
        return;
    }

    // Method 3: Try launchctl to restart SpringBoard.
    NSString *launchctlPath = [self findBinary:@"launchctl"];
    if (launchctlPath) {
        [self spawnBinary:launchctlPath withArgs:@[@"stop", @"com.apple.SpringBoard"]];
        usleep(200000);
        [self spawnBinary:launchctlPath withArgs:@[@"start", @"com.apple.SpringBoard"]];
    }
}

#pragma mark - ldrestart

- (void)ldrestart {
    NSLog(@"[GhostKit] ldrestart");

    // Method 1: Try ldrestart binary.
    NSString *ldrestartPath = [self findBinary:@"ldrestart"];
    if (ldrestartPath) {
        [self spawnBinary:ldrestartPath withArgs:@[]];
        return;
    }

    // Method 2: Fallback - restart key daemons individually.
    NSString *launchctlPath = [self findBinary:@"launchctl"];
    if (launchctlPath) {
        NSArray *daemons = @[
            @"com.apple.securityd",
            @"com.apple.cfprefsd",
            @"com.apple.lsd",
            @"com.apple.SpringBoard",
        ];
        for (NSString *daemon in daemons) {
            [self spawnBinary:launchctlPath withArgs:@[@"stop", daemon]];
            usleep(200000);
            [self spawnBinary:launchctlPath withArgs:@[@"start", daemon]];
        }
        return;
    }

    // Method 3: killall backboardd + SpringBoard.
    NSString *killallPath = [self findBinary:@"killall"];
    if (killallPath) {
        [self spawnBinary:killallPath withArgs:@[@"-9", @"backboardd", @"SpringBoard"]];
    }
}

@end
