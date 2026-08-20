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
        [_self ensureDir];
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
        self.pressStartTime = CFAbsoluteTimeGetCurrent();
        self.pressFingerCount = (int)pan.numberOfTouches;
    }
    return YES;
}

- (void)onThreeFingerPan:(UIPanGestureRecognizer *)pan {
    self.pressStartTime = 0;
    self.pressFingerCount = 0;
    if (![self isCurrentAppEnabled]) return;
    if (pan.state == UIGestureRecognizerStateEnded) {
        CGFloat duration = CFAbsoluteTimeGetCurrent() - self.pressStartTime;
        if (duration >= 0.5 && duration <= 3.0 && self.pressFingerCount == 3) {
            [self showFeatureButtons];
        }
    }
}

#pragma mark - Show / Hide

- (void)showFeatureButtons {
    [self hideOverlay];
    UIWindow *keyWindow = _app.keyWindow;
    if (!keyWindow) return;
    _overlayWindow = [[GhostKitOverlayWindow alloc] initWithFrame:keyWindow.bounds];
    FeatureButtonsVC *vc = [[FeatureButtonsVC alloc] init];
    _overlayWindow.rootViewController = vc;
    _overlayWindow.backgroundColor = [UIColor clearColor];
    _overlayWindow.hidden = NO;
    _overlayWindow.alpha = 0.0;
    [keyWindow addSubview:_overlayWindow];
    [UIView animateWithDuration:0.25 animations:^{ _overlayWindow.alpha = 1.0; }];
}

- (void)showSettings {
    [self hideOverlay];
    UIWindow *keyWindow = _app.keyWindow;
    if (!keyWindow) return;
    _overlayWindow = [[GhostKitOverlayWindow alloc] initWithFrame:keyWindow.bounds];
    UINavigationController *nav = [[UINavigationController alloc]
        initWithRootViewController:[[SettingsVC alloc] init]];
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

- (void)ensureDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [ENABLED_PLIST_PATH stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
}

@end
