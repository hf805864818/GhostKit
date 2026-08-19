//
//  AppListManager.h
//  GhostKit
//
//  Application list management via LSApplicationWorkspace (private API).
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class LSApplicationProxy;

@interface AppInfo : NSObject

@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *iconPath;
@property (nonatomic, copy) NSString *dataPath;
@property (nonatomic, copy) NSString *bundlePath;

@end

@interface AppListManager : NSObject

+ (instancetype)sharedInstance;

/// Return all user-installed applications.
- (NSArray<AppInfo *> *)getAllInstalledApps;

/// Search installed apps whose bundle ID or name contains the keyword.
- (NSArray<AppInfo *> *)searchApps:(NSString *)keyword;

/// Uninstall an app by bundle ID.
- (BOOL)uninstallApp:(NSString *)bundleID;

/// Get AppInfo for a single bundle ID.
- (AppInfo *)getAppInfoWithBundleID:(NSString *)bundleID;

/// Resolve the data container path for a bundle ID
/// by reading .com.apple.mobile_container_manager.plist.
- (NSString *)getDataContainerPathForBundleID:(NSString *)bundleID;

/// Extract the app icon image from the app bundle.
- (UIImage *)extractIconFromBundle:(NSString *)bundlePath;

@end
