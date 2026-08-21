//
//  OverlayController.m
//  GhostKit Tweak
//
//  Manages 3-finger long-press gesture, feature overlay, and settings overlay.
//

#import "OverlayController.h"
#import "GhostKitFeatureButtonsViewController.h"
#import "GhostKitSettingsViewController.h"
#import "DarwinNotifyManager.h"
#import "AppListManager.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define ENABLED_PLIST_PATH @"/var/mobile/Library/GhostKit/enabled_apps.plist"

// ---------------------------------------------------------------------------
// Private window subclass — absorbs touches so underlying app can't intercept
// ---------------------------------------------------------------------------
@interface GhostKitOverlayWindow : UIWindow
@end
@implementation GhostKitOverlayWindow
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.windowLevel = UIWindowLevelAlert + 100;
        self.hidden = YES;
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)canResignFirstResponder { return YES; }
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    // Pass through to allow gesture recognizer on root view controller
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    // let root VC handle it
}
@end

// ---------------------------------------------------------------------------
// OverlayController
// ---------------------------------------------------------------------------
@interface OverlayController () {
    UIWindow *_overlayWindow;
    UIApplication *_app;
    CFAbsoluteTime _pressStartTime;
    int _pressFingerCount;
}
@end

@implementation OverlayController

+ (instancetype)sharedInstance {
    static OverlayController *instance;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _app = [UIApplication sharedApplication];
        [self ensureDir];
        _pressStartTime = 0;
        _pressFingerCount = 0;
    }
    return self;
}

#pragma mark - Lifecycle

- (void)start {
    [self hookThreeFingerLongPress];
    NSLog(@"[GhostKit] OverlayController started");
}

#pragma mark - Gesture

- (void)hookThreeFingerLongPress {
    SEL sel = @selector(handleThreeFingerPan:);
    Method m = class_getInstanceMethod([UIViewController class], sel);
    if (m) {
        IMP orig = imp_implementationWithBlock(^(id selfObj, UIPanGestureRecognizer *pan) {
            if ([self shouldProcessGesture:pan]) {
                [self onThreeFingerPan:pan];
            }
            // Call original handler
            ((void(*)(id, SEL, UIPanGestureRecognizer*))objc_msgSend)(selfObj, sel, pan);
        });
        method_setImplementation(m, orig);
    }
}

- (BOOL)shouldProcessGesture:(UIPanGestureRecognizer *)pan {
    if (![self isCurrentAppEnabled]) return NO;
    if (pan.state == UIGestureRecognizerStateBegan) {
        _pressStartTime = CFAbsoluteTimeGetCurrent();
        _pressFingerCount = (int)pan.numberOfTouches;
    }
    return YES;
}

- (void)onThreeFingerPan:(UIPanGestureRecognizer *)pan {
    if (![self isCurrentAppEnabled]) return;
    if (pan.state == UIGestureRecognizerStateEnded) {
        CGFloat duration = CFAbsoluteTimeGetCurrent() - _pressStartTime;
        if (duration >= 0.5 && duration <= 3.0 && _pressFingerCount == 3) {
            [self showFeatureButtons];
        }
        _pressStartTime = 0;
        _pressFingerCount = 0;
    }
}

#pragma mark - Show / Hide

- (void)showFeatureButtons {
    [self hideOverlay];
    UIWindow *keyWindow = [self _findKeyWindow];
    if (!keyWindow) return;
    _overlayWindow = [[GhostKitOverlayWindow alloc] initWithFrame:keyWindow.bounds];
    GhostKitFeatureButtonsViewController *vc = [[GhostKitFeatureButtonsViewController alloc] init];
    _overlayWindow.rootViewController = vc;
    _overlayWindow.backgroundColor = [UIColor clearColor];
    _overlayWindow.hidden = NO;
    _overlayWindow.alpha = 0.0;
    [keyWindow addSubview:_overlayWindow];
    [UIView animateWithDuration:0.25 animations:^{ _overlayWindow.alpha = 1.0; }];
}

- (void)showSettings {
    [self hideOverlay];
    UIWindow *keyWindow = [self _findKeyWindow];
    if (!keyWindow) return;
    _overlayWindow = [[GhostKitOverlayWindow alloc] initWithFrame:keyWindow.bounds];
    UINavigationController *nav = [[UINavigationController alloc]
        initWithRootViewController:[[GhostKitSettingsViewController alloc] init]];
    nav.modalPresentationStyle = UIModalPresentationOverFullScreen;
    nav.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    _overlayWindow.rootViewController = nav;
    _overlayWindow.backgroundColor = [UIColor clearColor];
    _overlayWindow.hidden = NO;
    _overlayWindow.alpha = 0.0;
    [keyWindow addSubview:_overlayWindow];
    [UIView animateWithDuration:0.3 animations:^{ _overlayWindow.alpha = 1.0; }];
}

- (void)hideOverlay {
    UIWindow *w = _overlayWindow;
    _overlayWindow = nil;
    if (!w || w.hidden) return;
    [UIView animateWithDuration:0.15 animations:^{ w.alpha = 0.0; }
    completion:^(BOOL finished) { w.hidden = YES; w.rootViewController = nil; }];
}

- (BOOL)isOverlayVisible { return _overlayWindow && !_overlayWindow.hidden; }

- (BOOL)isCurrentAppEnabled {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    return [[self enabledBundleIDs] containsObject:bid];
}

#pragma mark - Whitelist persistence

- (NSSet<NSString *> *)enabledBundleIDs {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:ENABLED_PLIST_PATH];
    NSArray *arr = dict[@"enabledApps"] ?: @[];
    return [NSSet setWithArray:arr];
}

- (void)setEnabledBundleIDs:(NSSet<NSString *> *)bundleIDs {
    NSDictionary *dict = @{
        @"enabledApps": [bundleIDs allObjects],
        @"lastUpdate": @([[NSDate date] timeIntervalSince1970] stringValue),
    };
    [dict writeToFile:ENABLED_PLIST_PATH atomically:YES];
}

- (void)setEnabled:(BOOL)enabled forBundleID:(NSString *)bundleID {
    NSMutableSet *set = [self.enabledBundleIDs mutableCopy];
    if (enabled) [set addObject:bundleID];
    else [set removeObject:bundleID];
    [self setEnabledBundleIDs:set];
}

#pragma mark - Helpers

- (UIWindow *)_findKeyWindow {
    // iOS 13+ compatible way to find the key window
    // (keyWindow is deprecated, use windowScene.windows instead)
    for (UIWindowScene *scene in _app.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
            // Fallback: return first window in the active scene
            if (scene.windows.count > 0) {
                return scene.windows.firstObject;
            }
        }
    }
    // Last resort fallback
    return _app.windows.firstObject;
}

- (void)ensureDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [ENABLED_PLIST_PATH stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
}

@end
