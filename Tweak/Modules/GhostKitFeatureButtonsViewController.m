//
//  GhostKitFeatureButtonsViewController.m
//  GhostKit Tweak
//

#import "GhostKitFeatureButtonsViewController.h"
#import "OverlayController.h"
#import "DarwinNotifyManager.h"
#import <UIKit/UIKit.h>

#pragma mark - Key Window Helper (iOS 13+ safe, avoids deprecated keyWindow)

static UIWindow * GhostKitGetKeyWindow(void) {
    UIWindow *window = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *w in windowScene.windows) {
            window = w;
            break;
        }
        if (window) break;
    }
    return window;
}

typedef struct {
    NSString *iconName;
    NSString *title;
    NSString *darwinCommand;  // nil = opens settings overlay
} FeatureBtn;

static const FeatureBtn kFeatures[] = {
    { @"key.fill",       @"Keychain清理",   @"GhostKitCleanKeychain" },
    { @"tray.2.fill",    @"深层清理",       @"GhostKitDeepCleanKeychain" },
    { @"trash.fill",     @"清空Keychain",   @"GhostKitDeleteAllKeychains" },
    { @"arrow.clockwise", @"刷新IDFA",      @"GhostKitRefreshIDFA" },
    { @"device.phone",   @"一键新机",       @"GhostKitResetDevice" },
    { @"trash.fill",     @"清理缓存",       @"GhostKitCleanSystemResidue" },
    { @"square.grid.2x2", @"App列表",       @"GhostKitGetAllApps" },
    { @"doc.on.doc.fill", @"粘贴权限",      @"GhostKitAllowPasteForAll" },
    { @"person.crop.circle", @"账号管理",   @"GhostKitGetCurrentAccount" },
    { @"gearshape.fill", @"设置",           nil },
};
static const NSUInteger kFeatureCount = sizeof(kFeatures) / sizeof(kFeatures[0]);


@interface FeatureButtonsVC : UIViewController
@end

@implementation FeatureButtonsVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    [self buildUI];
}

- (void)buildUI {
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismissOverlay)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];

    UIView *backdrop = [[UIView alloc] initWithFrame:self.view.bounds];
    backdrop.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:backdrop atIndex:0];

    CGFloat cardW = 320;
    NSUInteger rows = (NSUInteger)ceil((CGFloat)kFeatureCount / 3.0);
    CGFloat cellH = 80;
    CGFloat cardH = 64 + (CGFloat)rows * cellH + 16;
    CGFloat cardX = (self.view.bounds.size.width - cardW) / 2;
    CGFloat cardY = (self.view.bounds.size.height - cardH) / 2;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(cardX, cardY, cardW, cardH)];
    card.backgroundColor = [[UIColor darkTextColor] colorWithAlphaComponent:0.92];
    card.layer.cornerRadius = 16;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor;

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, cardW, 28)];
    titleLbl.text = @"GhostKit";
    titleLbl.font = [UIFont boldSystemFontOfSize:16];
    titleLbl.textColor = [UIColor whiteColor];
    titleLbl.textAlignment = NSTextAlignmentCenter;
    titleLbl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [card addSubview:titleLbl];

    NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"GhostKit";
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    UILabel *infoLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, 40, cardW - 16, 16)];
    infoLbl.text = [NSString stringWithFormat:@"%@  %@", appName, bundleID];
    infoLbl.font = [UIFont systemFontOfSize:9];
    infoLbl.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45];
    infoLbl.textAlignment = NSTextAlignmentCenter;
    infoLbl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [card addSubview:infoLbl];

    UIView *div = [[UIView alloc] initWithFrame:CGRectMake(24, 60, cardW - 48, 1)];
    div.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    [card addSubview:div];

    CGFloat btnW = (cardW - 40 - 12 * 2) / 3;
    CGFloat btnH = 68;
    for (NSUInteger i = 0; i < kFeatureCount; i++) {
        NSUInteger row = i / 3;
        NSUInteger col = i % 3;
        CGFloat x = 20 + col * (btnW + 12);
        CGFloat y = 66 + row * (btnH + 8);
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(x, y, btnW, btnH);
        btn.tag = (NSInteger)i;
        UIImage *img = [UIImage systemImageNamed:kFeatures[i].iconName];
        UIImageView *iv = [[UIImageView alloc] initWithImage:img];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.frame = CGRectMake((btnW - 28) / 2, 4, 28, 28);
        iv.tintColor = [UIColor systemBlueColor];
        [btn addSubview:iv];
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 36, btnW, 28)];
        lbl.text = kFeatures[i].title;
        lbl.font = [UIFont systemFontOfSize:10];
        lbl.textColor = [UIColor whiteColor];
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.adjustsFontSizeToFitWidth = YES;
        lbl.minimumScaleFactor = 0.7;
        [btn addSubview:lbl];
        [btn addTarget:self action:@selector(onBtnTap:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:btn];
    }
    [self.view addSubview:card];
}

- (void)onBtnTap:(UIButton *)btn {
    NSUInteger idx = (NSUInteger)btn.tag;
    if (idx >= kFeatureCount) return;
    if (kFeatures[idx].darwinCommand) {
        DarwinCommand dc = [self commandFromString:kFeatures[idx].darwinCommand];
        [[DarwinNotifyManager sharedInstance] postNotification:dc params:nil];
    } else if ([kFeatures[idx].title isEqualToString:@"设置"]) {
        [OverlayController.sharedInstance showSettings];
        return;
    }
    [self dismissOverlay];
}

- (DarwinCommand)commandFromString:(NSString *)s {
    if      ([s isEqualToString:@"GhostKitCleanKeychain"])            return DarwinCommandCleanKeychain;
    else if ([s isEqualToString:@"GhostKitDeepCleanKeychain"])        return DarwinCommandDeepCleanKeychain;
    else if ([s isEqualToString:@"GhostKitDeleteAllKeychains"])       return DarwinCommandDeleteAllKeychains;
    else if ([s isEqualToString:@"GhostKitBackupKeychain"])           return DarwinCommandBackupKeychain;
    else if ([s isEqualToString:@"GhostKitRestoreKeychain"])          return DarwinCommandRestoreKeychain;
    else if ([s isEqualToString:@"GhostKitListKeychain"])             return DarwinCommandListKeychain;
    else if ([s isEqualToString:@"GhostKitRefreshIDFA"])              return DarwinCommandRefreshIDFA;
    else if ([s isEqualToString:@"GhostKitChangeIdentifier"])         return DarwinCommandChangeIdentifier;
    else if ([s isEqualToString:@"GhostKitGetCurrentIdentifiers"])    return DarwinCommandGetCurrentIdentifiers;
    else if ([s isEqualToString:@"GhostKitResetDevice"])              return DarwinCommandResetDevice;
    else if ([s isEqualToString:@"GhostKitGetDeviceInfo"])            return DarwinCommandGetDeviceInfo;
    else if ([s isEqualToString:@"GhostKitCleanSystemResidue"])       return DarwinCommandCleanSystemResidue;
    else if ([s isEqualToString:@"GhostKitCleanDatabaseCache"])       return DarwinCommandCleanDatabaseCache;
    else if ([s isEqualToString:@"GhostKitCleanDataDirectory"])       return DarwinCommandCleanDataDirectory;
    else if ([s isEqualToString:@"GhostKitCleanCookies"])             return DarwinCommandCleanCookies;
    else if ([s isEqualToString:@"GhostKitCleanPasteboard"])          return DarwinCommandCleanPasteboard;
    else if ([s isEqualToString:@"GhostKitGetAppSize"])               return DarwinCommandGetAppSize;
    else if ([s isEqualToString:@"GhostKitGetAllApps"])               return DarwinCommandGetAllApps;
    else if ([s isEqualToString:@"GhostKitSearchApps"])               return DarwinCommandSearchApps;
    else if ([s isEqualToString:@"GhostKitUninstallApp"])             return DarwinCommandUninstallApp;
    else if ([s isEqualToString:@"GhostKitGetAppInfo"])               return DarwinCommandGetAppInfo;
    else if ([s isEqualToString:@"GhostKitGetAccountList"])           return DarwinCommandGetAccountList;
    else if ([s isEqualToString:@"GhostKitAddAccount"])               return DarwinCommandAddAccount;
    else if ([s isEqualToString:@"GhostKitDeleteAccount"])            return DarwinCommandDeleteAccount;
    else if ([s isEqualToString:@"GhostKitGetCurrentAccount"])        return DarwinCommandGetCurrentAccount;
    else if ([s isEqualToString:@"GhostKitSwitchAccount"])            return DarwinCommandSwitchAccount;
    else if ([s isEqualToString:@"GhostKitAllowPasteForAll"])         return DarwinCommandAllowPasteForAll;
    else if ([s isEqualToString:@"GhostKitIsPasteAllowed"])           return DarwinCommandIsPasteAllowed;
    else if ([s isEqualToString:@"GhostKitSafeExit"])                 return DarwinCommandSafeExit;
    else if ([s isEqualToString:@"GhostKitRespring"])                 return DarwinCommandRespring;
    else if ([s isEqualToString:@"GhostKitLdrestart"])                return DarwinCommandLdrestart;
    else if ([s isEqualToString:@"GhostKitInjectDylib"])              return DarwinCommandInjectDylib;
    else if ([s isEqualToString:@"GhostKitRemoveDylib"])              return DarwinCommandRemoveDylib;
    else if ([s isEqualToString:@"GhostKitGetInjectedDylibs"])        return DarwinCommandGetInjectedDylibs;
    else if ([s isEqualToString:@"GhostKitApplyGraphicsConfig"])      return DarwinCommandApplyGraphicsConfig;
    else if ([s isEqualToString:@"GhostKitGetAvailablePresets"])      return DarwinCommandGetAvailablePresets;
    else if ([s isEqualToString:@"GhostKitGetCurrentGraphics"])       return DarwinCommandGetCurrentGraphics;
    else if ([s isEqualToString:@"GhostKitRestoreDefaultGraphics"])   return DarwinCommandRestoreDefaultGraphics;
    else if ([s isEqualToString:@"GhostKitShowSettings"])             return DarwinCommandShowSettings;
    return DarwinCommandCleanKeychain;
}

- (void)dismissOverlay {
    UIWindow *w = self.view.window;
    [UIView animateWithDuration:0.15 animations:^{ self.view.alpha = 0.0; }
    completion:^(BOOL finished) { if (w) { w.hidden = YES; w.rootViewController = nil; } }];
}

@end

@implementation GhostKitFeatureButtonsViewController

+ (void)showOverlayFromViewController:(UIViewController *)vc {
    UIWindow *keyWindow = GhostKitGetKeyWindow();
    if (!keyWindow) return;
    UIWindow *overlay = [[GhostKitOverlayWindow alloc] initWithFrame:keyWindow.bounds];
    FeatureButtonsVC *fbvc = [[FeatureButtonsVC alloc] init];
    overlay.rootViewController = fbvc;
    overlay.backgroundColor = [UIColor clearColor];
    overlay.hidden = NO;
    overlay.alpha = 0.0;
    [keyWindow addSubview:overlay];
    [UIView animateWithDuration:0.25 animations:^{ overlay.alpha = 1.0; }];
}

+ (void)hideOverlay {
    UIWindow *keyWindow = GhostKitGetKeyWindow();
    if (!keyWindow) return;
    for (UIWindow *w in keyWindow.subviews) {
        if ([w isKindOfClass:[GhostKitOverlayWindow class]] && !w.hidden) {
            [UIView animateWithDuration:0.15 animations:^{ w.alpha = 0.0; }
            completion:^(BOOL finished) { w.hidden = YES; w.rootViewController = nil; }];
            return;
        }
    }
}

@end
