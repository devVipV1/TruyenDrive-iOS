#import "TDEncoderViewController.h"
#import "TDImageDecryptor.h"
#import "TDGoogleAuth.h"
#import "TDDriveBrowserViewController.h"
#import <PhotosUI/PhotosUI.h>

typedef NS_ENUM(NSInteger, TDEncoderOutputMode) {
    TDEncoderOutputModePhotos = 0,
    TDEncoderOutputModeFiles,
    TDEncoderOutputModeDrive,
};

#pragma mark - TDEncoderViewController

@interface TDEncoderViewController () <PHPickerViewControllerDelegate, UIDocumentPickerDelegate, TDDriveBrowserDelegate>

// UI
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

// Input card
@property (nonatomic, strong) UIView *inputCard;
@property (nonatomic, strong) UIVisualEffectView *inputGlass;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIButton *selectButton;
@property (nonatomic, strong) UILabel *selectionCountLabel;

// Output card
@property (nonatomic, strong) UIView *outputCard;
@property (nonatomic, strong) UIVisualEffectView *outputGlass;
@property (nonatomic, strong) UIButton *photosOption;
@property (nonatomic, strong) UIButton *filesOption;
@property (nonatomic, strong) UIButton *driveOption;
@property (nonatomic, copy) NSString *driveFolderId;
@property (nonatomic, copy) NSString *driveFolderTitle;

// Encrypt button
@property (nonatomic, strong) UIButton *encryptButton;

// Progress area
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *cancelButton;

// State
@property (nonatomic, strong) NSMutableArray<UIImage *> *selectedImages;
@property (nonatomic, assign) TDEncoderOutputMode outputMode;
@property (nonatomic, assign) BOOL isEncrypting;
@property (nonatomic, assign) BOOL isCancelled;

@end

@implementation TDEncoderViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.selectedImages = [NSMutableArray array];
    self.outputMode = TDEncoderOutputModePhotos;
    self.isEncrypting = NO;
    self.isCancelled = NO;

    [self setupScrollView];
    [self setupHeader];
    [self setupInputCard];
    [self setupOutputCard];
    [self setupEncryptButton];
    [self setupProgressArea];
    [self updateUI];

    // Dismiss keyboard on tap
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

#pragma mark - Keyboard

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - Setup: Scroll View

- (void)setupScrollView {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
    ]];
}

#pragma mark - Setup: Header

- (void)setupHeader {
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"Encrypt Images";
    self.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    self.titleLabel.textColor = UIColor.labelColor;
    [self.contentView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.text = @"Protect your images with XOR encryption";
    self.subtitleLabel.font = [UIFont systemFontOfSize:15];
    self.subtitleLabel.textColor = UIColor.secondaryLabelColor;
    [self.contentView addSubview:self.subtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:24],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
    ]];
}

#pragma mark - Setup: Input Card

- (void)setupInputCard {
    self.inputCard = [self createGlassCard];
    [self.contentView addSubview:self.inputCard];

    // Lock icon + label
    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
    UIImageView *lockIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.shield" withConfiguration:iconConfig]];
    lockIcon.translatesAutoresizingMaskIntoConstraints = NO;
    lockIcon.tintColor = UIColor.systemBlueColor;
    lockIcon.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *inputTitle = [[UILabel alloc] init];
    inputTitle.translatesAutoresizingMaskIntoConstraints = NO;
    inputTitle.text = @"Encryption Settings";
    inputTitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    inputTitle.textColor = UIColor.labelColor;

    // Password field
    self.passwordField = [[UITextField alloc] init];
    self.passwordField.translatesAutoresizingMaskIntoConstraints = NO;
    self.passwordField.placeholder = @"Enter encryption password";
    self.passwordField.font = [UIFont systemFontOfSize:15];
    self.passwordField.borderStyle = UITextBorderStyleNone;
    self.passwordField.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.08]
            : [UIColor colorWithWhite:0.0 alpha:0.05];
    }];
    self.passwordField.layer.cornerRadius = 10;
    self.passwordField.layer.cornerCurve = kCACornerCurveContinuous;
    self.passwordField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 0)];
    self.passwordField.leftViewMode = UITextFieldViewModeAlways;
    self.passwordField.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 0)];
    self.passwordField.rightViewMode = UITextFieldViewModeAlways;
    self.passwordField.secureTextEntry = NO;
    self.passwordField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.passwordField.autocorrectionType = UITextAutocorrectionTypeNo;
    [self.passwordField addTarget:self action:@selector(updateUI) forControlEvents:UIControlEventEditingChanged];

    // Select images button
    UIImageSymbolConfiguration *btnIconConfig = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    UIImage *photoIcon = [UIImage systemImageNamed:@"photo.on.rectangle" withConfiguration:btnIconConfig];

    self.selectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.selectButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.selectButton setTitle:@"  Select Images" forState:UIControlStateNormal];
    [self.selectButton setImage:photoIcon forState:UIControlStateNormal];
    self.selectButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.selectButton.tintColor = UIColor.systemBlueColor;
    self.selectButton.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.08]
            : [UIColor colorWithWhite:0.0 alpha:0.05];
    }];
    self.selectButton.layer.cornerRadius = 10;
    self.selectButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.selectButton.contentEdgeInsets = UIEdgeInsetsMake(12, 16, 12, 16);
    [self.selectButton addTarget:self action:@selector(selectImagesTapped) forControlEvents:UIControlEventTouchUpInside];

    // Selection count label
    self.selectionCountLabel = [[UILabel alloc] init];
    self.selectionCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectionCountLabel.text = @"No images selected";
    self.selectionCountLabel.font = [UIFont systemFontOfSize:13];
    self.selectionCountLabel.textColor = UIColor.tertiaryLabelColor;
    self.selectionCountLabel.textAlignment = NSTextAlignmentCenter;

    UIView *cardContent = [self contentViewOfCard:self.inputCard];
    [cardContent addSubview:lockIcon];
    [cardContent addSubview:inputTitle];
    [cardContent addSubview:self.passwordField];
    [cardContent addSubview:self.selectButton];
    [cardContent addSubview:self.selectionCountLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.inputCard.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:20],
        [self.inputCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.inputCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [lockIcon.topAnchor constraintEqualToAnchor:cardContent.topAnchor constant:16],
        [lockIcon.leadingAnchor constraintEqualToAnchor:cardContent.leadingAnchor constant:16],
        [lockIcon.widthAnchor constraintEqualToConstant:20],
        [lockIcon.heightAnchor constraintEqualToConstant:20],

        [inputTitle.centerYAnchor constraintEqualToAnchor:lockIcon.centerYAnchor],
        [inputTitle.leadingAnchor constraintEqualToAnchor:lockIcon.trailingAnchor constant:8],
        [inputTitle.trailingAnchor constraintEqualToAnchor:cardContent.trailingAnchor constant:-16],

        [self.passwordField.topAnchor constraintEqualToAnchor:lockIcon.bottomAnchor constant:14],
        [self.passwordField.leadingAnchor constraintEqualToAnchor:cardContent.leadingAnchor constant:16],
        [self.passwordField.trailingAnchor constraintEqualToAnchor:cardContent.trailingAnchor constant:-16],
        [self.passwordField.heightAnchor constraintEqualToConstant:44],

        [self.selectButton.topAnchor constraintEqualToAnchor:self.passwordField.bottomAnchor constant:12],
        [self.selectButton.leadingAnchor constraintEqualToAnchor:cardContent.leadingAnchor constant:16],
        [self.selectButton.trailingAnchor constraintEqualToAnchor:cardContent.trailingAnchor constant:-16],
        [self.selectButton.heightAnchor constraintEqualToConstant:44],

        [self.selectionCountLabel.topAnchor constraintEqualToAnchor:self.selectButton.bottomAnchor constant:8],
        [self.selectionCountLabel.leadingAnchor constraintEqualToAnchor:cardContent.leadingAnchor constant:16],
        [self.selectionCountLabel.trailingAnchor constraintEqualToAnchor:cardContent.trailingAnchor constant:-16],
        [self.selectionCountLabel.bottomAnchor constraintEqualToAnchor:cardContent.bottomAnchor constant:-16],
    ]];
}

#pragma mark - Setup: Output Card

- (void)setupOutputCard {
    self.outputCard = [self createGlassCard];
    [self.contentView addSubview:self.outputCard];

    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
    UIImageView *outputIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down" withConfiguration:iconConfig]];
    outputIcon.translatesAutoresizingMaskIntoConstraints = NO;
    outputIcon.tintColor = UIColor.systemBlueColor;
    outputIcon.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *outputTitle = [[UILabel alloc] init];
    outputTitle.translatesAutoresizingMaskIntoConstraints = NO;
    outputTitle.text = @"Save Destination";
    outputTitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    outputTitle.textColor = UIColor.labelColor;

    // Save to Photos option
    self.photosOption = [self createRadioButtonWithTitle:@"Save to Photos"
                                               subtitle:@"Save encrypted images to photo library"
                                               selected:YES];
    [self.photosOption addTarget:self action:@selector(photosOptionTapped) forControlEvents:UIControlEventTouchUpInside];

    // Save to Files option
    self.filesOption = [self createRadioButtonWithTitle:@"Save to Files"
                                              subtitle:@"Export encrypted images to Files app"
                                              selected:NO];
    [self.filesOption addTarget:self action:@selector(filesOptionTapped) forControlEvents:UIControlEventTouchUpInside];

    // Save to Google Drive option
    self.driveOption = [self createRadioButtonWithTitle:@"Upload to Google Drive"
                                              subtitle:@"Encrypt and upload to a Drive folder"
                                              selected:NO];
    [self.driveOption addTarget:self action:@selector(driveOptionTapped) forControlEvents:UIControlEventTouchUpInside];

    UIView *cardContent = [self contentViewOfCard:self.outputCard];
    [cardContent addSubview:outputIcon];
    [cardContent addSubview:outputTitle];
    [cardContent addSubview:self.photosOption];
    [cardContent addSubview:self.filesOption];
    [cardContent addSubview:self.driveOption];

    [NSLayoutConstraint activateConstraints:@[
        [self.outputCard.topAnchor constraintEqualToAnchor:self.inputCard.bottomAnchor constant:16],
        [self.outputCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.outputCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [outputIcon.topAnchor constraintEqualToAnchor:cardContent.topAnchor constant:16],
        [outputIcon.leadingAnchor constraintEqualToAnchor:cardContent.leadingAnchor constant:16],
        [outputIcon.widthAnchor constraintEqualToConstant:20],
        [outputIcon.heightAnchor constraintEqualToConstant:20],

        [outputTitle.centerYAnchor constraintEqualToAnchor:outputIcon.centerYAnchor],
        [outputTitle.leadingAnchor constraintEqualToAnchor:outputIcon.trailingAnchor constant:8],
        [outputTitle.trailingAnchor constraintEqualToAnchor:cardContent.trailingAnchor constant:-16],

        [self.photosOption.topAnchor constraintEqualToAnchor:outputIcon.bottomAnchor constant:14],
        [self.photosOption.leadingAnchor constraintEqualToAnchor:cardContent.leadingAnchor constant:16],
        [self.photosOption.trailingAnchor constraintEqualToAnchor:cardContent.trailingAnchor constant:-16],
        [self.photosOption.heightAnchor constraintEqualToConstant:52],

        [self.filesOption.topAnchor constraintEqualToAnchor:self.photosOption.bottomAnchor constant:8],
        [self.filesOption.leadingAnchor constraintEqualToAnchor:cardContent.leadingAnchor constant:16],
        [self.filesOption.trailingAnchor constraintEqualToAnchor:cardContent.trailingAnchor constant:-16],
        [self.filesOption.heightAnchor constraintEqualToConstant:52],

        [self.driveOption.topAnchor constraintEqualToAnchor:self.filesOption.bottomAnchor constant:8],
        [self.driveOption.leadingAnchor constraintEqualToAnchor:cardContent.leadingAnchor constant:16],
        [self.driveOption.trailingAnchor constraintEqualToAnchor:cardContent.trailingAnchor constant:-16],
        [self.driveOption.heightAnchor constraintEqualToConstant:52],
        [self.driveOption.bottomAnchor constraintEqualToAnchor:cardContent.bottomAnchor constant:-16],
    ]];
}

#pragma mark - Setup: Encrypt Button

- (void)setupEncryptButton {
    self.encryptButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.encryptButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.encryptButton setTitle:@"Encrypt" forState:UIControlStateNormal];
    self.encryptButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [self.encryptButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.encryptButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.5] forState:UIControlStateDisabled];
    self.encryptButton.backgroundColor = UIColor.systemBlueColor;
    self.encryptButton.layer.cornerRadius = 14;
    self.encryptButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.encryptButton addTarget:self action:@selector(encryptTapped) forControlEvents:UIControlEventTouchUpInside];

    [self.contentView addSubview:self.encryptButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.encryptButton.topAnchor constraintEqualToAnchor:self.outputCard.bottomAnchor constant:24],
        [self.encryptButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.encryptButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.encryptButton.heightAnchor constraintEqualToConstant:52],
    ]];
}

#pragma mark - Setup: Progress Area

- (void)setupProgressArea {
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressView.progressTintColor = UIColor.systemBlueColor;
    self.progressView.trackTintColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.1]
            : [UIColor colorWithWhite:0.0 alpha:0.08];
    }];
    self.progressView.layer.cornerRadius = 2;
    self.progressView.clipsToBounds = YES;
    self.progressView.hidden = YES;

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.hidden = YES;

    self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    self.cancelButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.cancelButton.tintColor = UIColor.systemRedColor;
    self.cancelButton.hidden = YES;
    [self.cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];

    [self.contentView addSubview:self.progressView];
    [self.contentView addSubview:self.statusLabel];
    [self.contentView addSubview:self.cancelButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.progressView.topAnchor constraintEqualToAnchor:self.encryptButton.bottomAnchor constant:20],
        [self.progressView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.progressView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.progressView.heightAnchor constraintEqualToConstant:4],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.cancelButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
        [self.cancelButton.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.cancelButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-40],
    ]];
}

#pragma mark - Glass Card Helper

- (UIView *)createGlassCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;

    if (@available(iOS 26.0, *)) {
        UIGlassEffect *glass = [[UIGlassEffect alloc] init];
        UIVisualEffectView *glassView = [[UIVisualEffectView alloc] initWithEffect:glass];
        glassView.translatesAutoresizingMaskIntoConstraints = NO;
        glassView.layer.cornerRadius = 16;
        glassView.clipsToBounds = YES;
        glassView.tag = 1001;
        [card addSubview:glassView];
        [NSLayoutConstraint activateConstraints:@[
            [glassView.topAnchor constraintEqualToAnchor:card.topAnchor],
            [glassView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
            [glassView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [glassView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        ]];
    } else {
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        blurView.translatesAutoresizingMaskIntoConstraints = NO;
        blurView.layer.cornerRadius = 16;
        blurView.clipsToBounds = YES;
        blurView.tag = 1001;
        [card addSubview:blurView];
        [NSLayoutConstraint activateConstraints:@[
            [blurView.topAnchor constraintEqualToAnchor:card.topAnchor],
            [blurView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
            [blurView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [blurView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        ]];
    }

    return card;
}

- (UIView *)contentViewOfCard:(UIView *)card {
    UIVisualEffectView *effectView = [card viewWithTag:1001];
    if (effectView) {
        return effectView.contentView;
    }
    return card;
}

#pragma mark - Radio Button Helper

- (UIButton *)createRadioButtonWithTitle:(NSString *)title subtitle:(NSString *)subtitle selected:(BOOL)selected {
    UIButton *button = [[UIButton alloc] init];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.06]
            : [UIColor colorWithWhite:0.0 alpha:0.03];
    }];
    button.layer.cornerRadius = 10;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = selected ? 2.0 : 1.0;
    button.layer.borderColor = selected ? UIColor.systemBlueColor.CGColor : [UIColor separatorColor].CGColor;

    UIImageSymbolConfiguration *radioConfig = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    UIImageView *radioIcon = [[UIImageView alloc] init];
    radioIcon.translatesAutoresizingMaskIntoConstraints = NO;
    radioIcon.image = selected
        ? [UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:radioConfig]
        : [UIImage systemImageNamed:@"circle" withConfiguration:radioConfig];
    radioIcon.tintColor = selected ? UIColor.systemBlueColor : UIColor.tertiaryLabelColor;
    radioIcon.tag = 2001;
    radioIcon.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *titleLbl = [[UILabel alloc] init];
    titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    titleLbl.text = title;
    titleLbl.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    titleLbl.textColor = UIColor.labelColor;
    titleLbl.tag = 2002;

    UILabel *subtitleLbl = [[UILabel alloc] init];
    subtitleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    subtitleLbl.text = subtitle;
    subtitleLbl.font = [UIFont systemFontOfSize:12];
    subtitleLbl.textColor = UIColor.secondaryLabelColor;
    subtitleLbl.tag = 2003;

    [button addSubview:radioIcon];
    [button addSubview:titleLbl];
    [button addSubview:subtitleLbl];

    // Make labels not intercept touches
    radioIcon.userInteractionEnabled = NO;
    titleLbl.userInteractionEnabled = NO;
    subtitleLbl.userInteractionEnabled = NO;

    [NSLayoutConstraint activateConstraints:@[
        [radioIcon.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:14],
        [radioIcon.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
        [radioIcon.widthAnchor constraintEqualToConstant:22],
        [radioIcon.heightAnchor constraintEqualToConstant:22],

        [titleLbl.leadingAnchor constraintEqualToAnchor:radioIcon.trailingAnchor constant:10],
        [titleLbl.topAnchor constraintEqualToAnchor:button.topAnchor constant:8],
        [titleLbl.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-14],

        [subtitleLbl.leadingAnchor constraintEqualToAnchor:titleLbl.leadingAnchor],
        [subtitleLbl.topAnchor constraintEqualToAnchor:titleLbl.bottomAnchor constant:1],
        [subtitleLbl.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-14],
    ]];

    return button;
}

- (void)updateRadioButton:(UIButton *)button selected:(BOOL)selected {
    UIImageSymbolConfiguration *radioConfig = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    UIImageView *radioIcon = [button viewWithTag:2001];
    radioIcon.image = selected
        ? [UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:radioConfig]
        : [UIImage systemImageNamed:@"circle" withConfiguration:radioConfig];
    radioIcon.tintColor = selected ? UIColor.systemBlueColor : UIColor.tertiaryLabelColor;

    button.layer.borderWidth = selected ? 2.0 : 1.0;
    button.layer.borderColor = selected ? UIColor.systemBlueColor.CGColor : [UIColor separatorColor].CGColor;
}

#pragma mark - UI State

- (void)updateUI {
    BOOL hasImages = self.selectedImages.count > 0;
    BOOL hasPassword = self.passwordField.text.length > 0;

    self.encryptButton.enabled = hasImages && !self.isEncrypting;
    self.encryptButton.alpha = self.encryptButton.enabled ? 1.0 : 0.5;

    NSString *btnTitle = hasPassword ? @"Encrypt & Save" : @"Upload";
    if (self.outputMode == TDEncoderOutputModeDrive) {
        btnTitle = hasPassword ? @"Encrypt & Upload to Drive" : @"Upload to Drive";
    }
    [self.encryptButton setTitle:btnTitle forState:UIControlStateNormal];

    NSUInteger count = self.selectedImages.count;
    if (count == 0) {
        self.selectionCountLabel.text = @"No images selected";
        self.selectionCountLabel.textColor = UIColor.tertiaryLabelColor;
    } else if (count == 1) {
        self.selectionCountLabel.text = @"1 image selected";
        self.selectionCountLabel.textColor = UIColor.systemBlueColor;
    } else {
        self.selectionCountLabel.text = [NSString stringWithFormat:@"%lu images selected", (unsigned long)count];
        self.selectionCountLabel.textColor = UIColor.systemBlueColor;
    }
}

#pragma mark - Actions

- (void)selectImagesTapped {
    if (self.isEncrypting) return;

    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.selectionLimit = 0; // unlimited
    config.filter = [PHPickerFilter imagesFilter];
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)photosOptionTapped {
    if (self.isEncrypting) return;
    self.outputMode = TDEncoderOutputModePhotos;
    [self updateRadioButton:self.photosOption selected:YES];
    [self updateRadioButton:self.filesOption selected:NO];
    [self updateRadioButton:self.driveOption selected:NO];
    [self updateUI];
}

- (void)filesOptionTapped {
    if (self.isEncrypting) return;
    self.outputMode = TDEncoderOutputModeFiles;
    [self updateRadioButton:self.photosOption selected:NO];
    [self updateRadioButton:self.filesOption selected:YES];
    [self updateRadioButton:self.driveOption selected:NO];
    [self updateUI];
}

- (void)driveOptionTapped {
    if (self.isEncrypting) return;
    if (![TDGoogleAuth shared].isSignedIn) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sign In Required"
            message:@"Go to Settings to sign in to Google Drive first." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    // Open folder picker
    TDDriveBrowserViewController *browser = [[TDDriveBrowserViewController alloc] init];
    browser.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:browser];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)driveBrowserDidSelectFolderWithId:(NSString *)folderId title:(NSString *)title {
    self.driveFolderId = folderId;
    self.driveFolderTitle = title;
    self.outputMode = TDEncoderOutputModeDrive;
    [self updateRadioButton:self.photosOption selected:NO];
    [self updateRadioButton:self.filesOption selected:NO];
    [self updateRadioButton:self.driveOption selected:YES];
    // Update drive option subtitle
    for (UIView *v in self.driveOption.subviews) {
        if ([v isKindOfClass:[UILabel class]] && v.tag == 2003) {
            ((UILabel *)v).text = [NSString stringWithFormat:@"Upload to: %@", title];
        }
    }
    [self updateUI];
}

- (void)cancelTapped {
    self.isCancelled = YES;
    self.cancelButton.enabled = NO;
    self.statusLabel.text = @"Cancelling...";
}

- (void)encryptTapped {
    NSString *password = self.passwordField.text;
    if (self.selectedImages.count == 0) return;

    [self dismissKeyboard];
    [self beginEncryption:password];
}

#pragma mark - PHPickerViewControllerDelegate

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];

    if (results.count == 0) return;

    // Reset selections
    [self.selectedImages removeAllObjects];

    // Show loading state
    self.selectionCountLabel.text = [NSString stringWithFormat:@"Loading %lu images...", (unsigned long)results.count];
    self.selectionCountLabel.textColor = UIColor.secondaryLabelColor;
    self.selectButton.enabled = NO;

    __block NSInteger loadedCount = 0;
    NSInteger totalCount = results.count;
    NSMutableArray<UIImage *> *tempImages = [NSMutableArray arrayWithCapacity:totalCount];
    // Pre-fill with NSNull placeholders to maintain order
    for (NSInteger i = 0; i < totalCount; i++) {
        [tempImages addObject:(UIImage *)[NSNull null]];
    }

    for (NSInteger i = 0; i < totalCount; i++) {
        PHPickerResult *result = results[i];
        NSInteger index = i;

        if ([result.itemProvider canLoadObjectOfClass:[UIImage class]]) {
            [result.itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> _Nullable object, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (object && [object isKindOfClass:[UIImage class]]) {
                        tempImages[index] = (UIImage *)object;
                    }

                    loadedCount++;
                    if (loadedCount == totalCount) {
                        // Remove any NSNull placeholders (failed loads)
                        for (NSInteger j = tempImages.count - 1; j >= 0; j--) {
                            if ([tempImages[j] isKindOfClass:[NSNull class]]) {
                                [tempImages removeObjectAtIndex:j];
                            }
                        }
                        [self.selectedImages setArray:tempImages];
                        self.selectButton.enabled = YES;
                        [self updateUI];
                    }
                });
            }];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                loadedCount++;
                if (loadedCount == totalCount) {
                    for (NSInteger j = tempImages.count - 1; j >= 0; j--) {
                        if ([tempImages[j] isKindOfClass:[NSNull class]]) {
                            [tempImages removeObjectAtIndex:j];
                        }
                    }
                    [self.selectedImages setArray:tempImages];
                    self.selectButton.enabled = YES;
                    [self updateUI];
                }
            });
        }
    }
}

#pragma mark - Encryption

- (void)beginEncryption:(NSString *)password {
    self.isEncrypting = YES;
    self.isCancelled = NO;
    self.encryptButton.enabled = NO;
    self.encryptButton.alpha = 0.5;
    self.selectButton.enabled = NO;
    self.passwordField.enabled = NO;

    self.progressView.hidden = NO;
    self.progressView.progress = 0;
    self.statusLabel.hidden = NO;
    self.statusLabel.text = @"Encrypting...";
    self.cancelButton.hidden = NO;
    self.cancelButton.enabled = YES;

    NSArray<UIImage *> *imagesToEncrypt = [self.selectedImages copy];
    NSInteger totalCount = imagesToEncrypt.count;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray<NSData *> *encryptedDataArray = [NSMutableArray arrayWithCapacity:totalCount];

        for (NSInteger i = 0; i < totalCount; i++) {
            if (self.isCancelled) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finishEncryptionWithMessage:@"Encryption cancelled" success:NO];
                });
                return;
            }

            UIImage *image = imagesToEncrypt[i];

            BOOL hasPassword = password.length > 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.statusLabel.text = [NSString stringWithFormat:@"%@ %ld/%ld...",
                    hasPassword ? @"Encrypting" : @"Processing", (long)(i + 1), (long)totalCount];
                self.progressView.progress = (float)i / (float)totalCount;
            });

            NSData *pngData = nil;
            if (hasPassword) {
                pngData = [TDImageDecryptor encryptImage:image password:password];
            } else {
                pngData = UIImagePNGRepresentation(image);
            }
            if (pngData) {
                [encryptedDataArray addObject:pngData];
            } else {
                NSLog(@"[TDEncoder] Failed to process image %ld", (long)i);
            }
        }

        if (self.isCancelled) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishEncryptionWithMessage:@"Encryption cancelled" success:NO];
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressView.progress = 1.0;
            self.statusLabel.text = @"Saving...";
        });

        if (self.outputMode == TDEncoderOutputModePhotos) {
            [self saveToPhotos:encryptedDataArray total:totalCount];
        } else if (self.outputMode == TDEncoderOutputModeDrive) {
            [self uploadToDrive:encryptedDataArray];
        } else {
            [self saveToFiles:encryptedDataArray];
        }
    });
}

- (void)saveToPhotos:(NSArray<NSData *> *)encryptedDataArray total:(NSInteger)totalCount {
    __block NSInteger savedCount = 0;
    __block NSInteger failedCount = 0;
    NSInteger dataCount = encryptedDataArray.count;

    for (NSInteger i = 0; i < dataCount; i++) {
        NSData *pngData = encryptedDataArray[i];
        UIImage *encryptedImage = [UIImage imageWithData:pngData];

        if (!encryptedImage) {
            failedCount++;
            if (savedCount + failedCount == dataCount) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString *msg = [NSString stringWithFormat:@"Done! %ld images encrypted and saved to Photos", (long)savedCount];
                    if (failedCount > 0) {
                        msg = [NSString stringWithFormat:@"%@\n(%ld failed)", msg, (long)failedCount];
                    }
                    [self finishEncryptionWithMessage:msg success:YES];
                });
            }
            continue;
        }

        UIImageWriteToSavedPhotosAlbum(encryptedImage, nil, nil, nil);
        savedCount++;

        if (savedCount + failedCount == dataCount) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *msg = [NSString stringWithFormat:@"Done! %ld images encrypted and saved to Photos", (long)savedCount];
                if (failedCount > 0) {
                    msg = [NSString stringWithFormat:@"%@\n(%ld failed)", msg, (long)failedCount];
                }
                [self finishEncryptionWithMessage:msg success:YES];
            });
        }
    }
}

- (void)saveToFiles:(NSArray<NSData *> *)encryptedDataArray {
    // Write encrypted PNGs to a temporary directory, then present a document picker
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"TDEncrypted"];
        NSFileManager *fm = [NSFileManager defaultManager];

        // Clean up any previous export
        [fm removeItemAtPath:tempDir error:nil];
        [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

        NSMutableArray<NSURL *> *fileURLs = [NSMutableArray array];
        for (NSInteger i = 0; i < (NSInteger)encryptedDataArray.count; i++) {
            NSString *filename = [NSString stringWithFormat:@"encrypted_%03ld.png", (long)(i + 1)];
            NSString *filePath = [tempDir stringByAppendingPathComponent:filename];
            [encryptedDataArray[i] writeToFile:filePath atomically:YES];
            [fileURLs addObject:[NSURL fileURLWithPath:filePath]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (fileURLs.count == 0) {
                [self finishEncryptionWithMessage:@"No images were encrypted" success:NO];
                return;
            }

            UIDocumentPickerViewController *docPicker = [[UIDocumentPickerViewController alloc] initForExportingURLs:fileURLs];
            docPicker.delegate = self;
            [self presentViewController:docPicker animated:YES completion:nil];
        });
    });
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSString *msg = [NSString stringWithFormat:@"Done! %lu encrypted images exported to Files", (unsigned long)urls.count];
    [self finishEncryptionWithMessage:msg success:YES];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self finishEncryptionWithMessage:@"Export cancelled" success:NO];
}

- (void)uploadToDrive:(NSArray<NSData *> *)dataArray {
    if (!self.driveFolderId) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishEncryptionWithMessage:@"No folder selected. Tap 'Upload to Google Drive' to pick a folder." success:NO];
        });
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self uploadNextItem:dataArray index:0 uploaded:0 failed:0];
    });
}

- (void)uploadNextItem:(NSArray<NSData *> *)dataArray index:(NSInteger)i uploaded:(NSInteger)uploaded failed:(NSInteger)failed {
    NSInteger total = dataArray.count;

    if (self.isCancelled) {
        [self finishEncryptionWithMessage:@"Upload cancelled" success:NO];
        return;
    }

    if (i >= total) {
        self.progressView.progress = 1.0;
        NSString *msg;
        if (failed == 0) {
            msg = [NSString stringWithFormat:@"Done! %ld images uploaded to %@", (long)uploaded, self.driveFolderTitle];
        } else {
            msg = [NSString stringWithFormat:@"%ld uploaded, %ld failed", (long)uploaded, (long)failed];
        }
        [self finishEncryptionWithMessage:msg success:failed == 0];
        return;
    }

    self.statusLabel.text = [NSString stringWithFormat:@"Uploading %ld/%ld...", (long)(i + 1), (long)total];
    self.progressView.progress = (float)i / (float)total;

    NSString *fileName = [NSString stringWithFormat:@"img_%03ld.png", (long)i];

    [[TDGoogleAuth shared] uploadFileData:dataArray[i]
                                 fileName:fileName
                                 mimeType:@"image/png"
                           parentFolderId:self.driveFolderId
                               completion:^(BOOL success, NSError *error) {
        [self uploadNextItem:dataArray
                       index:i + 1
                    uploaded:uploaded + (success ? 1 : 0)
                      failed:failed + (success ? 0 : 1)];
    }];
}

#pragma mark - Finish

- (void)finishEncryptionWithMessage:(NSString *)message success:(BOOL)success {
    self.isEncrypting = NO;
    self.isCancelled = NO;

    self.passwordField.enabled = YES;
    self.selectButton.enabled = YES;
    self.cancelButton.hidden = YES;
    self.progressView.hidden = YES;

    self.statusLabel.text = message;
    self.statusLabel.textColor = success ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    self.statusLabel.hidden = NO;

    [self updateUI];

    // Hide status after a few seconds on success
    if (success) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.isEncrypting) {
                [UIView animateWithDuration:0.3 animations:^{
                    self.statusLabel.alpha = 0;
                } completion:^(BOOL finished) {
                    self.statusLabel.hidden = YES;
                    self.statusLabel.alpha = 1.0;
                    self.statusLabel.textColor = UIColor.secondaryLabelColor;
                }];
            }
        });
    }
}

@end
