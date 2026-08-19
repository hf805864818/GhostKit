//
//  GraphicsConfigManager.h
//  GhostKit
//
//  Game graphics quality configuration.
//  Supports modifying UE4 ini files for supported games.
//

#import <Foundation/Foundation.h>

@interface GraphicsConfigManager : NSObject

+ (instancetype)sharedInstance;

/// Apply a graphics preset (流畅 / 平衡 / 极致) to the given game.
- (BOOL)applyGraphicsConfig:(NSString *)preset forBundleID:(NSString *)bundleID;

/// Return the list of available preset names.
- (NSArray<NSString *> *)getAvailablePresets;

/// Return the current preset name for a game, or "默认" if unmodified.
- (NSString *)getCurrentConfigForBundleID:(NSString *)bundleID;

/// Restore the game's default graphics configuration (delete the custom ini).
- (BOOL)restoreDefaultForBundleID:(NSString *)bundleID;

@end
