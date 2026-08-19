//
//  SystemManager.m
//  GhostKit
//

#import "SystemManager.h"
#import <stdlib.h>
#import <spawn.h>
#import <signal.h>

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
    // We use posix_spawn to avoid blocking.
    pid_t pid = 0;
    char *argv[] = { "killall", "-9", "SpringBoard", NULL };

    int spawnResult = posix_spawnp(&pid, "killall", NULL, NULL, argv, environ);
    if (spawnResult != 0) {
        // Fallback to system().
        system("killall -9 SpringBoard");
    }

    // If that did not work (e.g., binary not found), try sbreload.
    // The above call replaces the process image indirectly via killall,
    // so this fallback only runs if killall is missing.
    system("sbreload 2>/dev/null");
}

#pragma mark - ldrestart

- (void)ldrestart {
    NSLog(@"[GhostKit] ldrestart");

    // ldrestart restarts all daemons. It is available on newer jailbreaks.
    pid_t pid = 0;
    char *argv[] = { "ldrestart", NULL };

    int spawnResult = posix_spawnp(&pid, "ldrestart", NULL, NULL, argv, environ);
    if (spawnResult != 0) {
        // Fallback: kill SpringBoard and backboardd.
        system("killall -9 backboardd SpringBoard");
    }
}

@end
