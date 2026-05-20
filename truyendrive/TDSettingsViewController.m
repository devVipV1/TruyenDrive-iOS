#import "TDSettingsViewController.h"
#import "TDGoogleAuth.h"

static NSString *const kGoogleEmailKey     = @"truyendrive_google_email";
static NSString *const kReadingDirectionKey = @"truyendrive_reading_direction";
static NSString *const kPreloadCountKey     = @"truyendrive_preload_count";

static const NSInteger kPreloadMin     = 1;
static const NSInteger kPreloadMax     = 10;
static const NSInteger kPreloadDefault = 3;

typedef NS_ENUM(NSInteger, TDSettingsSection) {
    TDSettingsSectionAccount = 0,
    TDSettingsSectionReader,
    TDSettingsSectionAbout,
    TDSettingsSectionCount
};

typedef NS_ENUM(NSInteger, TDReaderRow) {
    TDReaderRowDirection = 0,
    TDReaderRowPreload,
    TDReaderRowCount
};

typedef NS_ENUM(NSInteger, TDAboutRow) {
    TDAboutRowVersion = 0,
    TDAboutRowSourceCode,
    TDAboutRowAppName,
    TDAboutRowCount
};

#pragma mark - TDSettingsViewController

@interface TDSettingsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISegmentedControl *directionSegment;
@property (nonatomic, strong) UIStepper *preloadStepper;
@property (nonatomic, strong) UILabel *preloadValueLabel;

@end

@implementation TDSettingsViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Settings";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    [self setupTableView];
    [self setupControls];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadPreferences];
    [self.tableView reloadData];
}

#pragma mark - Setup

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;

    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)setupControls {
    // Reading direction segmented control
    self.directionSegment = [[UISegmentedControl alloc] initWithItems:@[@"LTR", @"RTL", @"TTB"]];
    [self.directionSegment addTarget:self
                              action:@selector(directionChanged:)
                    forControlEvents:UIControlEventValueChanged];

    // Preload stepper
    self.preloadStepper = [[UIStepper alloc] init];
    self.preloadStepper.minimumValue = kPreloadMin;
    self.preloadStepper.maximumValue = kPreloadMax;
    self.preloadStepper.stepValue = 1;
    [self.preloadStepper addTarget:self
                            action:@selector(preloadStepperChanged:)
                  forControlEvents:UIControlEventValueChanged];

    // Label next to the stepper
    self.preloadValueLabel = [[UILabel alloc] init];
    self.preloadValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightMedium];
    self.preloadValueLabel.textColor = UIColor.labelColor;
    self.preloadValueLabel.textAlignment = NSTextAlignmentCenter;
    self.preloadValueLabel.text = @"3";
}

#pragma mark - Preferences

- (void)loadPreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Reading direction
    NSString *direction = [defaults stringForKey:kReadingDirectionKey];
    if ([direction isEqualToString:@"rtl"]) {
        self.directionSegment.selectedSegmentIndex = 1;
    } else if ([direction isEqualToString:@"ttb"]) {
        self.directionSegment.selectedSegmentIndex = 2;
    } else {
        self.directionSegment.selectedSegmentIndex = 0;
    }

    // Preload count
    NSInteger preload = [defaults integerForKey:kPreloadCountKey];
    if (preload < kPreloadMin || preload > kPreloadMax) {
        preload = kPreloadDefault;
    }
    self.preloadStepper.value = preload;
    self.preloadValueLabel.text = [NSString stringWithFormat:@"%ld", (long)preload];
}

- (void)directionChanged:(UISegmentedControl *)sender {
    NSString *value;
    switch (sender.selectedSegmentIndex) {
        case 1:  value = @"rtl"; break;
        case 2:  value = @"ttb"; break;
        default: value = @"ltr"; break;
    }
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:kReadingDirectionKey];
}

- (void)preloadStepperChanged:(UIStepper *)sender {
    NSInteger count = (NSInteger)sender.value;
    self.preloadValueLabel.text = [NSString stringWithFormat:@"%ld", (long)count];
    [[NSUserDefaults standardUserDefaults] setInteger:count forKey:kPreloadCountKey];
}

#pragma mark - Account Actions

- (void)handleSignIn {
    [[TDGoogleAuth shared] presentLoginFromViewController:self completion:^(BOOL success) {
        if (success) {
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:TDSettingsSectionAccount]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }];
}

- (void)handleSignOut {
    [[TDGoogleAuth shared] signOut];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:TDSettingsSectionAccount]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return TDSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((TDSettingsSection)section) {
        case TDSettingsSectionAccount: return 1;
        case TDSettingsSectionReader:  return TDReaderRowCount;
        case TDSettingsSectionAbout:   return TDAboutRowCount;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ((TDSettingsSection)section) {
        case TDSettingsSectionAccount: return @"Account";
        case TDSettingsSectionReader:  return @"Reader";
        case TDSettingsSectionAbout:   return @"About";
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ((TDSettingsSection)indexPath.section) {
        case TDSettingsSectionAccount: return [self accountCellForTableView:tableView];
        case TDSettingsSectionReader:  return [self readerCellForTableView:tableView row:indexPath.row];
        case TDSettingsSectionAbout:   return [self aboutCellForTableView:tableView row:indexPath.row];
        default: return [[UITableViewCell alloc] init];
    }
}

#pragma mark - Cell Builders

- (UITableViewCell *)accountCellForTableView:(UITableView *)tableView {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];

    NSString *email = [TDGoogleAuth shared].userEmail;

    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
    cell.imageView.image = [UIImage systemImageNamed:@"person.crop.circle" withConfiguration:iconConfig];
    cell.imageView.tintColor = UIColor.systemBlueColor;

    if (email.length > 0) {
        cell.textLabel.text = email;
        cell.detailTextLabel.text = @"Google Drive";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UIButton *signOutButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [signOutButton setTitle:@"Sign Out" forState:UIControlStateNormal];
        [signOutButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
        signOutButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [signOutButton sizeToFit];
        [signOutButton addTarget:self action:@selector(handleSignOut) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = signOutButton;
    } else {
        cell.textLabel.text = @"Sign in to Google Drive";
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }

    return cell;
}

- (UITableViewCell *)readerCellForTableView:(UITableView *)tableView row:(NSInteger)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];

    switch ((TDReaderRow)row) {
        case TDReaderRowDirection: {
            cell.textLabel.text = @"Reading Direction";
            cell.imageView.image = [UIImage systemImageNamed:@"book.pages" withConfiguration:iconConfig];
            cell.imageView.tintColor = UIColor.systemOrangeColor;
            cell.accessoryView = self.directionSegment;
            break;
        }
        case TDReaderRowPreload: {
            cell.textLabel.text = @"Preload Images";
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:iconConfig];
            cell.imageView.tintColor = UIColor.systemGreenColor;

            // Compose a stepper + label accessory view
            UIView *container = [[UIView alloc] init];

            self.preloadValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
            self.preloadStepper.translatesAutoresizingMaskIntoConstraints = NO;

            [container addSubview:self.preloadValueLabel];
            [container addSubview:self.preloadStepper];

            [NSLayoutConstraint activateConstraints:@[
                [self.preloadValueLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
                [self.preloadValueLabel.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
                [self.preloadValueLabel.widthAnchor constraintEqualToConstant:30],

                [self.preloadStepper.leadingAnchor constraintEqualToAnchor:self.preloadValueLabel.trailingAnchor constant:8],
                [self.preloadStepper.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
                [self.preloadStepper.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],

                [container.heightAnchor constraintEqualToAnchor:self.preloadStepper.heightAnchor],
            ]];

            // Size the container so UIKit can lay it out as an accessory view
            CGSize stepperSize = self.preloadStepper.intrinsicContentSize;
            CGFloat totalWidth = 30 + 8 + stepperSize.width;
            container.frame = CGRectMake(0, 0, totalWidth, stepperSize.height);

            cell.accessoryView = container;
            break;
        }
        default:
            break;
    }

    return cell;
}

- (UITableViewCell *)aboutCellForTableView:(UITableView *)tableView row:(NSInteger)row {
    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];

    switch ((TDAboutRow)row) {
        case TDAboutRowVersion: {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
            cell.textLabel.text = @"Version";
            cell.detailTextLabel.text = @"1.0.0";
            cell.imageView.image = [UIImage systemImageNamed:@"info.circle" withConfiguration:iconConfig];
            cell.imageView.tintColor = UIColor.systemGrayColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        case TDAboutRowSourceCode: {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.textLabel.text = @"Source Code";
            cell.imageView.image = [UIImage systemImageNamed:@"chevron.left.forwardslash.chevron.right" withConfiguration:iconConfig];
            cell.imageView.tintColor = UIColor.systemPurpleColor;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        case TDAboutRowAppName: {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.textLabel.text = @"TruyenDrive";
            cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
            cell.detailTextLabel.text = @"Comic Reader for Google Drive";
            cell.imageView.image = [UIImage systemImageNamed:@"book.circle.fill" withConfiguration:iconConfig];
            cell.imageView.tintColor = UIColor.systemBlueColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        default:
            return [[UITableViewCell alloc] init];
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == TDSettingsSectionAccount) {
        NSString *email = [TDGoogleAuth shared].userEmail;
        if (email.length == 0) {
            [self handleSignIn];
        }
    } else if (indexPath.section == TDSettingsSectionAbout && indexPath.row == TDAboutRowSourceCode) {
        NSLog(@"[TDSettings] Source code tapped -- URL not yet configured");
    }
}

@end
