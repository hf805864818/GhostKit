//
//  PermissionManager.h
//  GhostKit
//
//  Pasteboard permission management via TCC.db.
//

#import <Foundation/Foundation.h>

@interface PermissionManager : NSObject

+ (instancetype)sharedInstance;

/// Insert / update TCC.db entries to grant pasteboard access
/// for all installed applications.
- (BOOL)allowPasteForAllApps;

/// Check whether a specific bundle ID has pasteboard permission.
- (BOOL)isPasteAllowedForBundleID:(NSString *)bundleID;

@end
