//
//  AppListManager.m
//  GhostKit
//
//  Uses the private LSApplicationWorkspace API (from AppSupport / MobileContainerManager)
//  to enumerate, query, and uninstall applications.
//

#import "AppListManager.h"
#import <objc/runtime.h>
#import <objc/message.h>

// ---------------------------------------------------------------------------
// Private API declarations
// ---------------------------------------------------------------------------

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *shortName;
@property (nonatomic, readonly) NSString *bundleVersion;
@property (nonatomic, readonly) NSString *shortVersionString;
@property (nonatomic, readonly) NSURL *bundleURL;
@property (nonatomic, readonly) NSURL *dataContainerURL;
@property (nonatomic, readonly) NSString *itemContentType;
@property (nonatomic, readonly) NSNumber *betaAppFlag;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
- (NSArray<LSApplicationProxy *> *)allApplications;
- (BOOL)uninstallApplication:(NSString *)identifier
                 withOptions:(NSDictionary *)options
                       error:(NSError **)error;
- (LSApplicationProxy *)applicationForIdentifier:(NSString *)identifier;
- (BOOL)openApplication:(NSString *)identifier;
@end

// ---------------------------------------------------------------------------
// AppInfo implementation
// ---------------------------------------------------------------------------

@implementation AppInfo
@end

// ---------------------------------------------------------------------------
// AppListManager implementation
// ---------------------------------------------------------------------------

@implementation AppListManager

+ (instancetype)sharedInstance {
    static AppListManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AppListManager alloc] init];
    });
    return instance;
}

#pragma mark - AppInfo helpers

- (AppInfo *)appInfoFromProxy:(LSApplicationProxy *)proxy {
    if (!proxy) {
        return nil;
    }

    AppInfo *info = [[AppInfo alloc] init];
    info.bundleID   = proxy.applicationIdentifier ?: @"";
    info.name       = proxy.localizedName ?: proxy.shortName ?: @"";
    info.version    = proxy.shortVersionString ?: proxy.bundleVersion ?: @"";
    info.bundlePath = proxy.bundleURL.path ?: @"";
    info.dataPath   = proxy.dataContainerURL.path ?: @"";

    // Try to find an icon path inside the bundle.
    NSString *iconPath = [self findIconPathInBundle:info.bundlePath];
    info.iconPath = iconPath ?: @"";

    return info;
}

- (NSString *)findIconPathInBundle:(NSString *)bundlePath {
    if (!bundlePath || bundlePath.length == 0) {
        return nil;
    }

    NSString *infoPlistPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
    if (!info) {
        return nil;
    }

    // CFBundleIcons -> CFBundlePrimaryIcon -> CFBundleIconFiles
    NSDictionary *icons = info[@"CFBundleIcons"];
    NSDictionary *primaryIcon = icons[@"CFBundlePrimaryIcon"];
    NSArray *iconFiles = primaryIcon[@"CFBundleIconFiles"];

    if (iconFiles.count > 0) {
        NSString *iconName = iconFiles.lastObject;
        NSString *iconPath = [bundlePath stringByAppendingPathComponent:iconName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
            return iconPath;
        }
        // Try with .png extension
        iconPath = [iconPath stringByAppendingString:@".png"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
            return iconPath;
        }
    }

    // Fallback: CFBundleIconFile
    NSString *iconFile = info[@"CFBundleIconFile"];
    if (iconFile) {
        NSString *iconPath = [bundlePath stringByAppendingPathComponent:iconFile];
        if (![[iconPath pathExtension] length]) {
            iconPath = [iconPath stringByAppendingString:@".png"];
        }
        if ([[NSFileManager defaultManager] fileExistsAtPath:iconPath]) {
            return iconPath;
        }
    }

    // Last resort: try common icon names.
    NSArray *commonNames = @[
        @"AppIcon60x60@2x.png",
        @"AppIcon60x60@3x.png",
        @"AppIcon76x76@2x.png",
        @"AppIcon83.5x83.5@2x.png",
        @"icon@2x.png",
        @"Icon.png",
        @"icon.png",
    ];
    for (NSString *name in commonNames) {
        NSString *path = [bundlePath stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return path;
        }
    }

    return nil;
}

#pragma mark - Get all apps

- (NSArray<AppInfo *> *)getAllInstalledApps {
    NSMutableArray *result = [NSMutableArray array];

    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    if (!workspaceClass) {
        NSLog(@"[GhostKit] LSApplicationWorkspace not available");
        return result;
    }

    LSApplicationWorkspace *workspace = [workspaceClass defaultWorkspace];
    if (!workspace) {
        return result;
    }

    NSArray *proxies = [workspace allInstalledApplications];
    if (!proxies) {
        proxies = [workspace allApplications];
    }

    for (LSApplicationProxy *proxy in proxies) {
        AppInfo *info = [self appInfoFromProxy:proxy];
        if (info) {
            [result addObject:info];
        }
    }

    // Sort by name.
    [result sortUsingComparator:^NSComparisonResult(AppInfo *a, AppInfo *b) {
        return [a.name compare:b.name options:NSCaseInsensitiveSearch];
    }];

    NSLog(@"[GhostKit] getAllInstalledApps: %lu apps", (unsigned long)result.count);
    return result;
}

#pragma mark - Search

- (NSArray<AppInfo *> *)searchApps:(NSString *)keyword {
    NSMutableArray *result = [NSMutableArray array];
    NSArray *allApps = [self getAllInstalledApps];

    if (!keyword || keyword.length == 0) {
        return allApps;
    }

    NSString *lowerKeyword = [keyword lowercaseString];
    for (AppInfo *info in allApps) {
        if ([info.bundleID.lowercaseString containsString:lowerKeyword] ||
            [info.name.lowercaseString containsString:lowerKeyword]) {
            [result addObject:info];
        }
    }

    return result;
}

#pragma mark - Uninstall

- (BOOL)uninstallApp:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) {
        return NO;
    }

    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    if (!workspaceClass) {
        return NO;
    }

    LSApplicationWorkspace *workspace = [workspaceClass defaultWorkspace];
    NSError *error = nil;
    NSDictionary *options = @{ @"DeleteApplicationOption": @YES };

    BOOL ok = [workspace uninstallApplication:bundleID
                                   withOptions:options
                                         error:&error];
    if (error) {
        NSLog(@"[GhostKit] Uninstall error for %@: %@", bundleID, error);
    }

    NSLog(@"[GhostKit] uninstallApp:%@ -> %@", bundleID, ok ? @"YES" : @"NO");
    return ok;
}

#pragma mark - Get app info

- (AppInfo *)getAppInfoWithBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) {
        return nil;
    }

    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    if (!workspaceClass) {
        return nil;
    }

    LSApplicationWorkspace *workspace = [workspaceClass defaultWorkspace];
    LSApplicationProxy *proxy = [workspace applicationForIdentifier:bundleID];

    return [self appInfoFromProxy:proxy];
}

#pragma mark - Data container path

- (NSString *)getDataContainerPathForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) {
        return nil;
    }

    // 1. Try via LSApplicationProxy.dataContainerURL.
    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    if (workspaceClass) {
        LSApplicationWorkspace *workspace = [workspaceClass defaultWorkspace];
        LSApplicationProxy *proxy = [workspace applicationForIdentifier:bundleID];
        if (proxy) {
            NSURL *dataURL = proxy.dataContainerURL;
            if (dataURL) {
                return dataURL.path;
            }
        }
    }

    // 2. Fallback: scan /var/mobile/Containers/Data/Application/ for the
    //    .com.apple.mobile_container_manager.plist whose MCContainerIdentifier
    //    matches the bundle ID.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *containersDir = @"/var/mobile/Containers/Data/Application";

    NSArray *containerUUIDs = [fm contentsOfDirectoryAtPath:containersDir error:nil];
    if (!containerUUIDs) {
        // Try the alternate path on some iOS versions.
        containersDir = @"/private/var/mobile/Containers/Data/Application";
        containerUUIDs = [fm contentsOfDirectoryAtPath:containersDir error:nil];
    }

    for (NSString *uuid in containerUUIDs) {
        NSString *plistPath = [containersDir
            stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@/.com.apple.mobile_container_manager.plist", uuid]];

        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        if (plist) {
            NSString *containerBundleID = plist[@"MCContainerIdentifier"];
            if (containerBundleID && [containerBundleID isEqualToString:bundleID]) {
                return [containersDir stringByAppendingPathComponent:uuid];
            }
        }
    }

    NSLog(@"[GhostKit] Data container not found for %@", bundleID);
    return nil;
}

#pragma mark - Extract icon

- (UIImage *)extractIconFromBundle:(NSString *)bundlePath {
    NSString *iconPath = [self findIconPathInBundle:bundlePath];
    if (iconPath) {
        return [UIImage imageWithContentsOfFile:iconPath];
    }
    return nil;
}

@end
