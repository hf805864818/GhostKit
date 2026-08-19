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
        // Fallback: try sbreload (system() is unavailable in the iOS SDK).
        char *sbArgv[] = { "sbreload", NULL };
        posix_spawnp(&pid, "sbreload", NULL, NULL, sbArgv, environ);
    }
}

#pragma mark - ldrestart

- (void)ldrestart {
    NSLog(@"[GhostKit] ldrestart");

    // ldrestart restarts all daemons. It is available on newer jailbreaks.
    pid_t pid = 0;
    char *argv[] = { "ldrestart", NULL };

    int spawnResult = posix_spawnp(&pid, "ldrestart", NULL, NULL, argv, environ);
    if (spawnResult != 0) {
        // Fallback: kill SpringBoard and backboardd (system() is unavailable in the iOS SDK).
        char *killArgv[] = { "killall", "-9", "backboardd", "SpringBoard", NULL };
        posix_spawnp(&pid, "killall", NULL, NULL, killArgv, environ);
    }
}

@end
