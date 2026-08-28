#import "GhostKitSettingsViewController.h"
#import "OverlayController.h"
#import "AppListManager.h"
#import <UIKit/UIKit.h>

@interface GhostKitSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *appList;
@end

@implementation GhostKitSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"GhostKit 设置";
    self.appList = [NSMutableArray array];
    [self reloadApps];
    [self setupTable];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadApps];
}

- (void)setupTable {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"AppCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Summary"];
    [self.view addSubview:self.tableView];
}

- (void)reloadApps {
    NSArray *apps = [[AppListManager sharedInstance] getAllInstalledApps];
    NSSet *enabled = [[OverlayController sharedInstance] enabledBundleIDs];
    [self.appList removeAllObjects];
    for (AppInfo *app in apps) {
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        m[@"name"]   = app.name ?: app.bundleID;
        m[@"bid"]    = app.bundleID;
        m[@"enabled"] = @( [enabled containsObject:app.bundleID] );
        [self.appList addObject:m];
    }
    [self.tableView reloadData];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : self.appList.count;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1)
        return [NSString stringWithFormat:@"已安装应用 (%lu)", (unsigned long)self.appList.count];
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Summary" forIndexPath:indexPath];
        NSSet *enabled = [[OverlayController sharedInstance] enabledBundleIDs];
        cell.textLabel.text = [NSString stringWithFormat:@"已启用: %lu / %lu 个应用",
                               (unsigned long)enabled.count, (unsigned long)self.appList.count];
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSInteger row = indexPath.row - 1;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppCell" forIndexPath:indexPath];
    NSDictionary *app = self.appList[row];
    cell.textLabel.text = app[@"name"] ?: @"";
    cell.detailTextLabel.text = app[@"bid"] ?: @"";
    cell.detailTextLabel.font = [UIFont systemFontOfSize:10];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = [app[@"enabled"] boolValue];
    [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? 44 : 56;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 8 : 32;
}

- (void)onSwitch:(UISwitch *)sw {
    CGPoint p = [sw convertPoint:CGPointZero toView:self.tableView];
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
    if (!ip || ip.section == 0) return;
    NSInteger row = ip.row - 1;
    if (row < 0 || row >= self.appList.count) return;
    NSMutableDictionary *app = self.appList[row];
    NSString *bid = app[@"bid"] ?: @"";
    app[@"enabled"] = @(sw.isOn);
    [[OverlayController sharedInstance] setEnabled:sw.isOn forBundleID:bid];
    NSLog(@"[GhostKit] %s overlay for %@", sw.isOn ? @"ENABLED" : @"DISABLED", bid);
}

@end
