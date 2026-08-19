//
//  CacheCleaner.h
//  GhostKit
//
//  System and per-app cache cleaning.
//

#import <Foundation/Foundation.h>

@interface CacheCleaner : NSObject

+ (instancetype)sharedInstance;

/// Clean system temporary files in /tmp and /var/tmp.
- (BOOL)cleanSystemResidue;

/// Delete SQLite WAL / SHM sidecar files in the app's data container.
- (BOOL)cleanDatabaseCacheForBundleID:(NSString *)bundleID;

/// Clean the app's Caches and tmp directories (preserves Documents).
- (BOOL)cleanDataDirectoryForBundleID:(NSString *)bundleID;

/// Clean cookies for a specific app (nil = system-wide cookies).
- (BOOL)cleanCookiesForBundleID:(NSString *)bundleID;

/// Clear the system pasteboard.
- (BOOL)cleanPasteboard;

/// Calculate the on-disk size of the app's data container.
- (NSDictionary *)getAppSizeForBundleID:(NSString *)bundleID;

@end
