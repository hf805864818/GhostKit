//
//  OverlayController.h
//  GhostKit Tweak
//
//  Manages the floating GhostKit overlay window.
//  Tracks 3-finger long press via UIApplication swizzle.
//  Shows feature buttons and a settings page.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OverlayController : NSObject

+ (instancetype)sharedInstance;
- (void)start;
- (void)showFeatureButtons;
- (void)showSettings;
- (void)hideOverlay;
- (BOOL)isOverlayVisible;
- (BOOL)isCurrentAppEnabled;
- (NSSet<NSString *> *)enabledBundleIDs;
- (void)setEnabledBundleIDs:(NSSet<NSString *> *)bundleIDs;
- (void)setEnabled:(BOOL)enabled forBundleID:(NSString *)bundleID;

@end
NS_ASSUME_NONNULL_END
