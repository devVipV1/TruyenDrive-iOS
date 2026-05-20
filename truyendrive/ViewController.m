#import "ViewController.h"
#import "TDDriveAPI.h"
#import "TDReaderViewController.h"
#import "TDGoogleAuth.h"
#import "TDDriveBrowserViewController.h"

static NSString *const kLastURLKey = @"truyendrive_last_url";
static NSString *const kLastPasswordKey = @"truyendrive_last_password";
static NSString *const kRecentFoldersKey = @"truyendrive_recent_folders";
static NSString *const kChapterCellId = @"ChapterCell";

@interface TDRecentFolder : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSTimeInterval timestamp;
@end
@implementation TDRecentFolder
@end

#pragma mark - Glass Card Helper

static UIView *makeGlassCard(void) {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIVisualEffectView *glass;
    if (@available(iOS 26.0, *)) {
        glass = [[UIVisualEffectView alloc] initWithEffect:[[UIGlassEffect alloc] init]];
    } else {
        glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    }
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    glass.layer.cornerRadius = 20;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    [container addSubview:glass];

    [NSLayoutConstraint activateConstraints:@[
        [glass.topAnchor constraintEqualToAnchor:container.topAnchor],
        [glass.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [glass.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [glass.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    ]];

    container.tag = 100;
    return container;
}

static UIView *glassContentView(UIView *card) {
    for (UIView *sub in card.subviews) {
        if ([sub isKindOfClass:[UIVisualEffectView class]]) {
            return ((UIVisualEffectView *)sub).contentView;
        }
    }
    return card;
}

static UITextField *makeTextField(NSString *placeholder, NSString *icon) {
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholder;
    field.font = [UIFont systemFontOfSize:15];
    field.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.06]
            : [UIColor colorWithWhite:0.0 alpha:0.04];
    }];
    field.layer.cornerRadius = 12;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon]];
    iconView.tintColor = UIColor.secondaryLabelColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.frame = CGRectMake(0, 0, 34, 20);
    field.leftView = iconView;
    field.leftViewMode = UITextFieldViewModeAlways;
    field.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 0)];
    field.rightViewMode = UITextFieldViewModeAlways;

    [field.heightAnchor constraintEqualToConstant:46].active = YES;
    return field;
}

#pragma mark - ViewController

@interface ViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UISwitch *passwordToggle;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UICollectionView *chapterCollection;
@property (nonatomic, strong) UIView *chapterCard;
@property (nonatomic, strong) UILabel *folderTitleLabel;
@property (nonatomic, strong) UIView *myDriveCard;
@property (nonatomic, strong) UILabel *myDriveUserLabel;
@property (nonatomic, strong) UIStackView *mainStack;

@property (nonatomic, strong) NSArray<TDDriveItem *> *images;
@property (nonatomic, strong) NSArray<TDChapter *> *chapters;
@property (nonatomic, copy, nullable) NSString *password;
@property (nonatomic, copy, nullable) NSString *folderTitle;
@property (nonatomic, copy, nullable) NSString *currentFolderId;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"TruyenDrive";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.images = @[];
    self.chapters = @[];

    [self buildUI];
    [self loadSavedState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateMyDriveCard];
}

#pragma mark - Build UI

- (void)buildUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.mainStack = [[UIStackView alloc] init];
    self.mainStack.axis = UILayoutConstraintAxisVertical;
    self.mainStack.spacing = 20;
    self.mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.mainStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:8],
        [self.mainStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-20],
        [self.mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
    ]];

    [self.mainStack addArrangedSubview:[self buildWelcomeSection]];
    [self.mainStack addArrangedSubview:[self buildMyDriveCard]];
    [self.mainStack addArrangedSubview:[self buildReaderCard]];
    [self.mainStack addArrangedSubview:[self buildStatusSection]];
    [self.mainStack addArrangedSubview:[self buildChapterCard]];
}

- (UIView *)buildMyDriveCard {
    self.myDriveCard = makeGlassCard();
    UIView *cv = glassContentView(self.myDriveCard);

    UIImageView *driveIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"externaldrive.fill.badge.person.crop"]];
    driveIcon.translatesAutoresizingMaskIntoConstraints = NO;
    driveIcon.tintColor = UIColor.systemGreenColor;
    driveIcon.contentMode = UIViewContentModeScaleAspectFit;

    self.myDriveUserLabel = [[UILabel alloc] init];
    self.myDriveUserLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.myDriveUserLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.myDriveUserLabel.textColor = UIColor.labelColor;

    UIButton *browseBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    browseBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [browseBtn setTitle:@"Browse My Drive" forState:UIControlStateNormal];
    [browseBtn setImage:[UIImage systemImageNamed:@"folder.badge.gearshape"] forState:UIControlStateNormal];
    browseBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    browseBtn.backgroundColor = UIColor.systemGreenColor;
    [browseBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    browseBtn.tintColor = UIColor.whiteColor;
    browseBtn.layer.cornerRadius = 12;
    browseBtn.layer.cornerCurve = kCACornerCurveContinuous;
    browseBtn.contentEdgeInsets = UIEdgeInsetsMake(10, 16, 10, 16);
    [browseBtn addTarget:self action:@selector(openDriveBrowser) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *topRow = [[UIStackView alloc] initWithArrangedSubviews:@[driveIcon, self.myDriveUserLabel]];
    topRow.axis = UILayoutConstraintAxisHorizontal;
    topRow.spacing = 10;
    topRow.alignment = UIStackViewAlignmentCenter;
    topRow.translatesAutoresizingMaskIntoConstraints = NO;
    [driveIcon.widthAnchor constraintEqualToConstant:24].active = YES;

    UIStackView *vStack = [[UIStackView alloc] initWithArrangedSubviews:@[topRow, browseBtn]];
    vStack.axis = UILayoutConstraintAxisVertical;
    vStack.spacing = 12;
    vStack.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:vStack];

    [NSLayoutConstraint activateConstraints:@[
        [vStack.topAnchor constraintEqualToAnchor:cv.topAnchor constant:16],
        [vStack.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-16],
        [vStack.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [vStack.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],
    ]];

    self.myDriveCard.hidden = YES;
    return self.myDriveCard;
}

- (void)updateMyDriveCard {
    BOOL signedIn = [TDGoogleAuth shared].isSignedIn;
    self.myDriveCard.hidden = !signedIn;
    if (signedIn) {
        NSString *name = [TDGoogleAuth shared].userName;
        NSString *email = [TDGoogleAuth shared].userEmail;
        if (name.length > 0 && ![name isEqualToString:email]) {
            self.myDriveUserLabel.text = [NSString stringWithFormat:@"%@ (%@)", name, email];
        } else {
            self.myDriveUserLabel.text = email;
        }
    }
}

- (void)openDriveBrowser {
    TDDriveBrowserViewController *browser = [[TDDriveBrowserViewController alloc] init];
    browser.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:browser];
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - TDDriveBrowserDelegate

- (void)driveBrowserDidSelectFolderWithId:(NSString *)folderId title:(NSString *)title {
    self.urlField.text = [NSString stringWithFormat:@"https://drive.google.com/drive/folders/%@", folderId];
    [[NSUserDefaults standardUserDefaults] setObject:self.urlField.text forKey:kLastURLKey];
    self.folderTitle = title;
    [self loadFolder:folderId];
}

- (UIView *)buildWelcomeSection {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.numberOfLines = 0;
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.font = [UIFont systemFontOfSize:14];

    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
    NSTextAttachment *iconAtt = [[NSTextAttachment alloc] init];
    iconAtt.image = [[UIImage systemImageNamed:@"photo.on.rectangle.angled"] imageWithTintColor:UIColor.systemBlueColor];
    iconAtt.bounds = CGRectMake(0, -3, 18, 15);
    [text appendAttributedString:[NSAttributedString attributedStringWithAttachment:iconAtt]];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"  View images directly from Google Drive — just paste a shared folder link."
        attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13.5], NSForegroundColorAttributeName: UIColor.secondaryLabelColor}]];

    subtitle.attributedText = text;
    [container addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [subtitle.topAnchor constraintEqualToAnchor:container.topAnchor],
        [subtitle.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4],
        [subtitle.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-4],
        [subtitle.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    return container;
}

- (UIView *)buildReaderCard {
    UIView *card = makeGlassCard();
    UIView *cv = glassContentView(card);

    UILabel *header = [[UILabel alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.text = @"Open Folder";
    header.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    header.textColor = UIColor.secondaryLabelColor;

    UIImageView *headerIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"folder.fill"]];
    headerIcon.translatesAutoresizingMaskIntoConstraints = NO;
    headerIcon.tintColor = UIColor.secondaryLabelColor;
    headerIcon.contentMode = UIViewContentModeScaleAspectFit;
    [headerIcon.widthAnchor constraintEqualToConstant:16].active = YES;

    UIStackView *headerStack = [[UIStackView alloc] initWithArrangedSubviews:@[headerIcon, header]];
    headerStack.axis = UILayoutConstraintAxisHorizontal;
    headerStack.spacing = 6;
    headerStack.translatesAutoresizingMaskIntoConstraints = NO;

    self.urlField = makeTextField(@"Google Drive folder link", @"link");
    self.urlField.keyboardType = UIKeyboardTypeURL;
    self.urlField.returnKeyType = UIReturnKeyGo;
    self.urlField.delegate = self;

    // Password toggle row
    UIView *passwordToggleRow = [[UIView alloc] init];
    passwordToggleRow.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *lockIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.shield"]];
    lockIcon.translatesAutoresizingMaskIntoConstraints = NO;
    lockIcon.tintColor = UIColor.secondaryLabelColor;
    lockIcon.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *pwLabel = [[UILabel alloc] init];
    pwLabel.translatesAutoresizingMaskIntoConstraints = NO;
    pwLabel.text = @"Password Protected";
    pwLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    pwLabel.textColor = UIColor.labelColor;

    self.passwordToggle = [[UISwitch alloc] init];
    self.passwordToggle.translatesAutoresizingMaskIntoConstraints = NO;
    self.passwordToggle.onTintColor = UIColor.systemBlueColor;
    [self.passwordToggle addTarget:self action:@selector(passwordToggleChanged) forControlEvents:UIControlEventValueChanged];

    [passwordToggleRow addSubview:lockIcon];
    [passwordToggleRow addSubview:pwLabel];
    [passwordToggleRow addSubview:self.passwordToggle];

    [NSLayoutConstraint activateConstraints:@[
        [lockIcon.leadingAnchor constraintEqualToAnchor:passwordToggleRow.leadingAnchor],
        [lockIcon.centerYAnchor constraintEqualToAnchor:passwordToggleRow.centerYAnchor],
        [lockIcon.widthAnchor constraintEqualToConstant:20],
        [pwLabel.leadingAnchor constraintEqualToAnchor:lockIcon.trailingAnchor constant:8],
        [pwLabel.centerYAnchor constraintEqualToAnchor:passwordToggleRow.centerYAnchor],
        [self.passwordToggle.trailingAnchor constraintEqualToAnchor:passwordToggleRow.trailingAnchor],
        [self.passwordToggle.centerYAnchor constraintEqualToAnchor:passwordToggleRow.centerYAnchor],
        [passwordToggleRow.heightAnchor constraintEqualToConstant:36],
    ]];

    self.passwordField = makeTextField(@"Enter decryption password", @"key.fill");
    self.passwordField.textContentType = UITextContentTypeOneTimeCode;
    self.passwordField.returnKeyType = UIReturnKeyGo;
    self.passwordField.delegate = self;
    self.passwordField.hidden = YES;
    self.passwordField.alpha = 0;

    self.openButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.openButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.openButton setTitle:@"  Open Folder" forState:UIControlStateNormal];
    [self.openButton setImage:[UIImage systemImageNamed:@"arrow.right.circle.fill"] forState:UIControlStateNormal];
    self.openButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.openButton.backgroundColor = UIColor.systemBlueColor;
    [self.openButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.openButton.tintColor = UIColor.whiteColor;
    self.openButton.layer.cornerRadius = 14;
    self.openButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.openButton addTarget:self action:@selector(handleOpen) forControlEvents:UIControlEventTouchUpInside];
    [self.openButton.heightAnchor constraintEqualToConstant:50].active = YES;

    UIStackView *fieldStack = [[UIStackView alloc] initWithArrangedSubviews:@[headerStack, self.urlField, passwordToggleRow, self.passwordField, self.openButton]];
    fieldStack.axis = UILayoutConstraintAxisVertical;
    fieldStack.spacing = 12;
    fieldStack.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:fieldStack];

    [NSLayoutConstraint activateConstraints:@[
        [fieldStack.topAnchor constraintEqualToAnchor:cv.topAnchor constant:18],
        [fieldStack.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-18],
        [fieldStack.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [fieldStack.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],
    ]];

    return card;
}

- (UIView *)buildStatusSection {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;

    [container addSubview:self.spinner];
    [container addSubview:self.statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.spinner.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.spinner.bottomAnchor constant:8],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    ]];

    container.hidden = YES;
    return container;
}

- (UIView *)buildChapterCard {
    self.chapterCard = makeGlassCard();
    self.chapterCard.hidden = YES;
    UIView *cv = glassContentView(self.chapterCard);

    self.folderTitleLabel = [[UILabel alloc] init];
    self.folderTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderTitleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    self.folderTitleLabel.textColor = UIColor.labelColor;

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 6;
    layout.sectionInset = UIEdgeInsetsZero;

    self.chapterCollection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.chapterCollection.translatesAutoresizingMaskIntoConstraints = NO;
    self.chapterCollection.backgroundColor = UIColor.clearColor;
    self.chapterCollection.scrollEnabled = NO;
    self.chapterCollection.dataSource = self;
    self.chapterCollection.delegate = self;
    [self.chapterCollection registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:kChapterCellId];

    [cv addSubview:self.folderTitleLabel];
    [cv addSubview:self.chapterCollection];

    [NSLayoutConstraint activateConstraints:@[
        [self.folderTitleLabel.topAnchor constraintEqualToAnchor:cv.topAnchor constant:16],
        [self.folderTitleLabel.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [self.folderTitleLabel.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],
        [self.chapterCollection.topAnchor constraintEqualToAnchor:self.folderTitleLabel.bottomAnchor constant:12],
        [self.chapterCollection.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
        [self.chapterCollection.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
        [self.chapterCollection.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-12],
        [self.chapterCollection.heightAnchor constraintEqualToConstant:300],
    ]];

    return self.chapterCard;
}

#pragma mark - State

- (void)loadSavedState {
    NSString *lastURL = [[NSUserDefaults standardUserDefaults] stringForKey:kLastURLKey];
    NSString *lastPass = [[NSUserDefaults standardUserDefaults] stringForKey:kLastPasswordKey];
    if (lastURL.length > 0) self.urlField.text = lastURL;
    if (lastPass.length > 0) {
        self.passwordField.text = lastPass;
        self.passwordToggle.on = YES;
        self.passwordField.hidden = NO;
        self.passwordField.alpha = 1.0;
    }
}

#pragma mark - Actions

- (void)passwordToggleChanged {
    BOOL on = self.passwordToggle.isOn;
    [UIView animateWithDuration:0.25 animations:^{
        self.passwordField.hidden = !on;
        self.passwordField.alpha = on ? 1.0 : 0.0;
    }];
    if (on) {
        [self.passwordField becomeFirstResponder];
    } else {
        self.passwordField.text = @"";
        [self.passwordField resignFirstResponder];
    }
}

- (void)handleOpen {
    [self.view endEditing:YES];
    NSString *urlString = self.urlField.text;
    if (urlString.length == 0) return;

    [[NSUserDefaults standardUserDefaults] setObject:urlString forKey:kLastURLKey];
    NSString *pw = self.passwordField.text;
    if (pw.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:pw forKey:kLastPasswordKey];
    }

    NSString *folderId = [TDDriveAPI folderIdFromURL:urlString];
    if (!folderId) {
        self.statusLabel.text = @"Invalid link. Make sure it contains /folders/...";
        self.statusLabel.superview.hidden = NO;
        return;
    }

    [self loadFolder:folderId];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.urlField) {
        [self.passwordField becomeFirstResponder];
    } else {
        [self handleOpen];
    }
    return YES;
}

#pragma mark - Data Loading

- (void)loadFolder:(NSString *)folderId {
    self.currentFolderId = folderId;
    self.images = @[];
    self.chapters = @[];
    NSString *manualPassword = self.passwordField.text;
    self.password = manualPassword.length > 0 ? manualPassword : nil;
    self.folderTitle = nil;
    self.chapterCard.hidden = YES;
    [self.chapterCollection reloadData];

    self.statusLabel.text = @"Loading folder...";
    self.statusLabel.superview.hidden = NO;
    [self.spinner startAnimating];

    self.openButton.enabled = NO;
    self.openButton.alpha = 0.6;

    [[TDDriveAPI shared] fetchFolderDetails:folderId completion:^(TDFolderDetails *details, NSError *error) {
        if (details) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.folderTitle = details.title;
                self.folderTitleLabel.text = details.title;
            });
        }
    }];

    [self loadAllPages:folderId cursor:nil accImages:[NSMutableArray array] accChapters:[NSMutableArray array] password:self.password];
}

- (void)loadAllPages:(NSString *)folderId
              cursor:(NSString *)cursor
           accImages:(NSMutableArray<TDDriveItem *> *)accImages
         accChapters:(NSMutableArray<TDChapter *> *)accChapters
            password:(NSString *)password {

    [[TDDriveAPI shared] fetchFolderItems:folderId cursor:cursor completion:^(TDFolderResult *result, NSError *error) {
        if (![self.currentFolderId isEqualToString:folderId]) return;

        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.spinner stopAnimating];
                self.statusLabel.text = [NSString stringWithFormat:@"Error: %@", error.localizedDescription];
                self.openButton.enabled = YES;
                self.openButton.alpha = 1.0;
            });
            return;
        }

        [accImages addObjectsFromArray:result.images];
        [accChapters addObjectsFromArray:result.chapters];
        NSString *pw = result.password ?: password;

        if (result.nextCursor.length > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = [NSString stringWithFormat:@"Loading... %lu items found", (unsigned long)(accImages.count + accChapters.count)];
            });
            [self loadAllPages:folderId cursor:result.nextCursor accImages:accImages accChapters:accChapters password:pw];
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            self.openButton.enabled = YES;
            self.openButton.alpha = 1.0;
            self.password = pw;
            self.images = [accImages copy];
            self.chapters = [accChapters copy];

            if (self.images.count == 0 && self.chapters.count == 0) {
                self.statusLabel.text = @"Folder is empty or not accessible.";
                return;
            }

            self.statusLabel.superview.hidden = YES;

            if (self.images.count > 0 && self.chapters.count == 0) {
                [self openReaderWithImages:self.images];
            } else if (self.chapters.count > 0) {
                self.chapterCard.hidden = NO;
                self.folderTitleLabel.text = self.folderTitle ?: @"Chapters";
                CGFloat cellH = 52;
                CGFloat totalH = MIN(self.chapters.count * (cellH + 6), 400);
                for (NSLayoutConstraint *c in self.chapterCollection.constraints) {
                    if (c.firstAttribute == NSLayoutAttributeHeight) { c.constant = totalH; break; }
                }
                [self.chapterCollection reloadData];
            }
        });
    }];
}

- (void)openReaderWithImages:(NSArray<TDDriveItem *> *)images {
    TDReaderViewController *reader = [[TDReaderViewController alloc] init];
    reader.images = images;
    reader.folderTitle = self.folderTitle ?: @"TruyenDrive";
    reader.password = self.password;
    reader.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:reader animated:YES completion:nil];
}

#pragma mark - UICollectionView (Chapters)

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.chapters.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kChapterCellId forIndexPath:indexPath];
    TDChapter *chapter = self.chapters[indexPath.item];

    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];

    cell.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.06]
            : [UIColor colorWithWhite:0.0 alpha:0.03];
    }];
    cell.layer.cornerRadius = 10;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    NSString *iconName = [chapter.kind isEqualToString:@"pdf"] ? @"doc.richtext" : @"folder.fill";
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName withConfiguration:cfg]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [chapter.kind isEqualToString:@"pdf"] ? UIColor.systemRedColor : UIColor.systemBlueColor;

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.text = chapter.name;
    nameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    nameLabel.textColor = UIColor.labelColor;

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightMedium]]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = UIColor.tertiaryLabelColor;

    [cell.contentView addSubview:icon];
    [cell.contentView addSubview:nameLabel];
    [cell.contentView addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:14],
        [icon.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [nameLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [nameLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [nameLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-8],
        [chevron.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-14],
        [chevron.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
    ]];

    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(collectionView.bounds.size.width, 52);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    TDChapter *chapter = self.chapters[indexPath.item];
    if ([chapter.kind isEqualToString:@"folder"]) {
        self.urlField.text = [NSString stringWithFormat:@"https://drive.google.com/drive/folders/%@", chapter.chapterId];
        [[NSUserDefaults standardUserDefaults] setObject:self.urlField.text forKey:kLastURLKey];
        [self loadFolder:chapter.chapterId];
    }
}

@end
