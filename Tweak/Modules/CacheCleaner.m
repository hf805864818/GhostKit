//
//  CacheCleaner.m
//  GhostKit
//

#import "CacheCleaner.h"
#import "AppListManager.h"
#import <UIKit/UIKit.h>

@implementation CacheCleaner

+ (instancetype)sharedInstance {
    static CacheCleaner *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CacheCleaner alloc] init];
    });
    return instance;
}

#pragma mark - Helpers

- (unsigned long long)directorySizeAtPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    unsigned long long size = 0;

    if (![fm fileExistsAtPath:path]) {
        return 0;
    }

    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:path];
    NSString *file;
    while ((file = [enumerator nextObject])) {
        NSDictionary *attrs = [enumerator fileAttributes];
        NSNumber *fileSize = attrs[NSFileSize];
        if (fileSize) {
            size += [fileSize unsignedLongLongValue];
        }
    }
    return size;
}

- (BOOL)deleteContentsOfDirectory:(NSString *)dirPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dirPath]) {
        return YES;
    }

    NSError *error = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:dirPath error:&error];
    if (error) {
        NSLog(@"[GhostKit] Cannot list %@: %@", dirPath, error);
        return NO;
    }

    BOOL success = YES;
    for (NSString *item in contents) {
        NSString *itemPath = [dirPath stringByAppendingPathComponent:item];
        NSError *itemError = nil;
        if (![fm removeItemAtPath:itemPath error:&itemError]) {
            NSLog(@"[GhostKit] Cannot remove %@: %@", itemPath, itemError);
            success = NO;
        }
    }
    return success;
}

- (void)deleteFilesWithExtension:(NSString *)ext inDirectory:(NSString *)dir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:dir];
    NSString *file;
    while ((file = [enumerator nextObject])) {
        if ([[file pathExtension] isEqualToString:ext]) {
            NSString *fullPath = [dir stringByAppendingPathComponent:file];
            [fm removeItemAtPath:fullPath error:nil];
        }
    }
}

#pragma mark - System residue

- (BOOL)cleanSystemResidue {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL success = YES;

    // /tmp
    [self deleteContentsOfDirectory:@"/tmp"];

    // /var/tmp
    [self deleteContentsOfDirectory:@"/var/tmp"];

    // System log files
    NSArray *logPaths = @[
        @"/var/log/syslog",
        @"/var/mobile/Library/Logs",
        @"/var/mobile/Library/Caches/Snapshots",
    ];
    for (NSString *path in logPaths) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir]) {
            if (isDir) {
                [self deleteContentsOfDirectory:path];
            } else {
                [fm removeItemAtPath:path error:nil];
            }
        }
    }

    NSLog(@"[GhostKit] cleanSystemResidue done");
    return success;
}

#pragma mark - Database cache (WAL/SHM)

- (BOOL)cleanDatabaseCacheForBundleID:(NSString *)bundleID {
    if (!bundleID) {
        return NO;
    }

    NSString *dataPath = [[AppListManager sharedInstance] getDataContainerPathForBundleID:bundleID];
    if (!dataPath) {
        NSLog(@"[GhostKit] No data container for %@", bundleID);
        return NO;
    }

    // Delete .db-wal and .db-shm files throughout the data container.
    [self deleteFilesWithExtension:@"db-wal" inDirectory:dataPath];
    [self deleteFilesWithExtension:@"db-shm" inDirectory:dataPath];
    [self deleteFilesWithExtension:@"sqlite-wal" inDirectory:dataPath];
    [self deleteFilesWithExtension:@"sqlite-shm" inDirectory:dataPath];

    NSLog(@"[GhostKit] cleanDatabaseCacheForBundleID:%@ done", bundleID);
    return YES;
}

#pragma mark - Data directory

- (BOOL)cleanDataDirectoryForBundleID:(NSString *)bundleID {
    if (!bundleID) {
        return NO;
    }

    NSString *dataPath = [[AppListManager sharedInstance] getDataContainerPathForBundleID:bundleID];
    if (!dataPath) {
        return NO;
    }

    // Clean Library/Caches and tmp, preserve Documents and Library/Preferences.
    NSArray *cleanDirs = @[
        [dataPath stringByAppendingPathComponent:@"Library/Caches"],
        [dataPath stringByAppendingPathComponent:@"tmp"],
        [dataPath stringByAppendingPathComponent:@"Library/SplashBoard/Snapshots"],
    ];

    for (NSString *dir in cleanDirs) {
        [self deleteContentsOfDirectory:dir];
    }

    NSLog(@"[GhostKit] cleanDataDirectoryForBundleID:%@ done", bundleID);
    return YES;
}

#pragma mark - Cookies

- (BOOL)cleanCookiesForBundleID:(NSString *)bundleID {
    NSFileManager *fm = [NSFileManager defaultManager];

    if (!bundleID) {
        // System-wide cookies.
        NSArray *systemCookiePaths = @[
            @"/var/mobile/Library/Cookies",
            @"/var/mobile/Library/Caches/com.apple.nsurlstore",
        ];
        for (NSString *path in systemCookiePaths) {
            [self deleteContentsOfDirectory:path];
        }

        // Also clear the shared HTTP cookie storage.
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in [storage cookies]) {
            [storage deleteCookie:cookie];
        }

        NSLog(@"[GhostKit] cleanCookies (system-wide) done");
        return YES;
    }

    // Per-app cookies.
    NSString *dataPath = [[AppListManager sharedInstance] getDataContainerPathForBundleID:bundleID];
    if (!dataPath) {
        return NO;
    }

    NSArray *cookiePaths = @[
        [dataPath stringByAppendingPathComponent:@"Library/Cookies"],
        [dataPath stringByAppendingPathComponent:@"Library/Caches/com.apple.nsurlstore"],
        [dataPath stringByAppendingPathComponent:@"Library/WebKit/WebsiteData"],
    ];

    for (NSString *path in cookiePaths) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir]) {
            if (isDir) {
                [self deleteContentsOfDirectory:path];
            } else {
                [fm removeItemAtPath:path error:nil];
            }
        }
    }

    NSLog(@"[GhostKit] cleanCookiesForBundleID:%@ done", bundleID);
    return YES;
}

#pragma mark - Pasteboard

- (BOOL)cleanPasteboard {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Clear the system pasteboard via UIKit.
    dispatch_async(dispatch_get_main_queue(), ^{
        UIPasteboard *pb = [UIPasteboard generalPasteboard];
        pb.items = @[];
    });

    // Delete pasteboard cache files.
    NSArray *paths = @[
        @"/var/mobile/Library/Caches/com.apple.Pasteboard",
        @"/var/mobile/Library/Caches/com.apple.UIKit.pboard",
        @"/private/var/db/PasteBoard",
    ];

    for (NSString *path in paths) {
        if ([fm fileExistsAtPath:path]) {
            [self deleteContentsOfDirectory:path];
        }
    }

    NSLog(@"[GhostKit] cleanPasteboard done");
    return YES;
}

#pragma mark - App size

- (NSDictionary *)getAppSizeForBundleID:(NSString *)bundleID {
    if (!bundleID) {
        return @{};
    }

    AppInfo *appInfo = [[AppListManager sharedInstance] getAppInfoWithBundleID:bundleID];
    if (!appInfo) {
        return @{};
    }

    NSString *dataPath = [[AppListManager sharedInstance] getDataContainerPathForBundleID:bundleID];

    unsigned long long bundleSize = [self directorySizeAtPath:appInfo.bundlePath];
    unsigned long long dataSize   = dataPath ? [self directorySizeAtPath:dataPath] : 0;
    unsigned long long total      = bundleSize + dataSize;

    // Human-readable size formatter (block to avoid nested function).
    NSString *(^formatSize)(unsigned long long) = ^NSString *(unsigned long long bytes) {
        if (bytes >= 1073741824) {
            return [NSString stringWithFormat:@"%.2f GB", (double)bytes / 1073741824.0];
        } else if (bytes >= 1048576) {
            return [NSString stringWithFormat:@"%.2f MB", (double)bytes / 1048576.0];
        } else if (bytes >= 1024) {
            return [NSString stringWithFormat:@"%.2f KB", (double)bytes / 1024.0];
        }
        return [NSString stringWithFormat:@"%llu B", bytes];
    };

    return @{
        @"bundleID":      bundleID,
        @"bundleSize":    @(bundleSize),
        @"dataSize":      @(dataSize),
        @"totalSize":     @(total),
        @"bundleSizeStr": formatSize(bundleSize),
        @"dataSizeStr":   formatSize(dataSize),
        @"totalSizeStr":  formatSize(total),
    };
}

@end
