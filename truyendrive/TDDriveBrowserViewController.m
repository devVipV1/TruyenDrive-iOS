#import "TDDriveBrowserViewController.h"
#import "TDGoogleAuth.h"
#import "TDDriveAPI.h"
#import <WebKit/WebKit.h>

static NSString *const kDesktopUserAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";
static NSString *const kDriveMyDriveURL = @"https://drive.google.com/drive/my-drive";
static NSString *const kDriveFolderPrefix = @"https://drive.google.com/drive/folders/";

#pragma mark - TDDriveBrowserViewController

@interface TDDriveBrowserViewController () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton *selectButton;
@property (nonatomic, strong) UILabel *folderNameLabel;
@property (nonatomic, copy) NSString *currentFolderId;
@end

@implementation TDDriveBrowserViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = self.folderTitle ?: @"My Drive";

    [self setupNavigation];
    [self setupBottomBar];
    [self setupWebView];
    [self loadDrivePage];
}

- (void)dealloc {
    [self.webView removeObserver:self forKeyPath:@"URL"];
    [self.webView removeObserver:self forKeyPath:@"title"];
}

#pragma mark - Setup

- (void)setupNavigation {
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                          target:self
                                                                                          action:@selector(cancelTapped)];
}

- (void)setupBottomBar {
    self.bottomBar = [[UIView alloc] init];
    self.bottomBar.translatesAutoresizingMaskIntoConstraints = NO;

    // Use Liquid Glass on iOS 26+, fall back to system chrome
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if (@available(iOS 26.0, *)) {
        UIBlurEffect *glass = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
        UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:glass];
        blurView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.bottomBar insertSubview:blurView atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [blurView.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor],
            [blurView.bottomAnchor constraintEqualToAnchor:self.bottomBar.bottomAnchor],
            [blurView.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor],
            [blurView.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor],
        ]];
    } else {
#endif
        self.bottomBar.backgroundColor = UIColor.secondarySystemBackgroundColor;

        // Top separator
        UIView *separator = [[UIView alloc] init];
        separator.translatesAutoresizingMaskIntoConstraints = NO;
        separator.backgroundColor = UIColor.separatorColor;
        [self.bottomBar addSubview:separator];
        [NSLayoutConstraint activateConstraints:@[
            [separator.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor],
            [separator.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor],
            [separator.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor],
            [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        ]];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    }
#endif

    // Folder name label
    self.folderNameLabel = [[UILabel alloc] init];
    self.folderNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderNameLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    self.folderNameLabel.textColor = UIColor.secondaryLabelColor;
    self.folderNameLabel.textAlignment = NSTextAlignmentCenter;
    self.folderNameLabel.text = @"Navigate to a folder, then tap below";
    [self.bottomBar addSubview:self.folderNameLabel];

    // Select button
    UIButtonConfiguration *buttonConfig = [UIButtonConfiguration filledButtonConfiguration];
    buttonConfig.title = @"Open This Folder";
    buttonConfig.image = [UIImage systemImageNamed:@"folder.badge.plus"];
    buttonConfig.imagePadding = 8;
    buttonConfig.cornerStyle = UIButtonConfigurationCornerStyleLarge;

    self.selectButton = [UIButton buttonWithConfiguration:buttonConfig primaryAction:nil];
    self.selectButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.selectButton.enabled = NO;
    [self.selectButton addTarget:self action:@selector(selectFolderTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar addSubview:self.selectButton];

    [self.view addSubview:self.bottomBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.folderNameLabel.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:12],
        [self.folderNameLabel.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor constant:16],
        [self.folderNameLabel.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor constant:-16],

        [self.selectButton.topAnchor constraintEqualToAnchor:self.folderNameLabel.bottomAnchor constant:10],
        [self.selectButton.centerXAnchor constraintEqualToAnchor:self.bottomBar.centerXAnchor],
        [self.selectButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.bottomBar.leadingAnchor constant:20],
        [self.selectButton.trailingAnchor constraintLessThanOrEqualToAnchor:self.bottomBar.trailingAnchor constant:-20],
        [self.selectButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [self.selectButton.heightAnchor constraintEqualToConstant:50],
    ]];
}

- (void)setupWebView {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = [WKWebsiteDataStore defaultDataStore]; // shares cookies with TDGoogleAuth

    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.customUserAgent = kDesktopUserAgent;
    self.webView.allowsBackForwardNavigationGestures = YES;

    [self.view insertSubview:self.webView belowSubview:self.bottomBar];

    [NSLayoutConstraint activateConstraints:@[
        [self.webView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.bottomBar.topAnchor],
    ]];

    // Observe URL and title changes to detect folder navigation
    [self.webView addObserver:self forKeyPath:@"URL" options:NSKeyValueObservingOptionNew context:nil];
    [self.webView addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:nil];
}

#pragma mark - Load

- (void)loadDrivePage {
    NSString *urlString;
    if (self.folderId.length > 0) {
        urlString = [NSString stringWithFormat:@"%@%@", kDriveFolderPrefix, self.folderId];
    } else {
        urlString = kDriveMyDriveURL;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

#pragma mark - URL Tracking

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (object == self.webView) {
        [self updateFolderStateFromURL:self.webView.URL title:self.webView.title];
    }
}

- (void)updateFolderStateFromURL:(NSURL *)url title:(NSString *)pageTitle {
    NSString *extracted = [self extractFolderIdFromURL:url];
    if (extracted) {
        self.currentFolderId = extracted;
        self.selectButton.enabled = YES;

        // Clean up the page title: Google Drive titles are like "FolderName - Google Drive"
        NSString *displayName = pageTitle ?: @"Selected Folder";
        NSRange dashRange = [displayName rangeOfString:@" - Google Drive"];
        if (dashRange.location != NSNotFound) {
            displayName = [displayName substringToIndex:dashRange.location];
        }
        // Also strip "Google Drive -" prefix if present
        NSString *prefix = @"Google Drive - ";
        if ([displayName hasPrefix:prefix]) {
            displayName = [displayName substringFromIndex:prefix.length];
        }

        if (displayName.length == 0) {
            displayName = @"Selected Folder";
        }

        self.folderNameLabel.text = displayName;
        self.folderNameLabel.textColor = UIColor.labelColor;
        self.title = displayName;
    } else {
        // Check if we're on My Drive root (which also counts as a valid selection)
        NSString *urlStr = url.absoluteString;
        if ([urlStr containsString:@"/drive/my-drive"] || [urlStr containsString:@"/drive/u/"]) {
            self.currentFolderId = @"root";
            self.selectButton.enabled = YES;
            self.folderNameLabel.text = @"My Drive";
            self.folderNameLabel.textColor = UIColor.labelColor;
            self.title = @"My Drive";
        } else {
            self.currentFolderId = nil;
            self.selectButton.enabled = NO;
            self.folderNameLabel.text = @"Navigate to a folder, then tap below";
            self.folderNameLabel.textColor = UIColor.secondaryLabelColor;
            self.title = @"My Drive";
        }
    }
}

- (nullable NSString *)extractFolderIdFromURL:(NSURL *)url {
    if (!url) return nil;
    NSString *path = url.absoluteString;

    // Match /folders/<id> in the URL
    NSRange foldersRange = [path rangeOfString:@"/folders/"];
    if (foldersRange.location == NSNotFound) return nil;

    NSUInteger start = foldersRange.location + foldersRange.length;
    if (start >= path.length) return nil;

    NSString *remainder = [path substringFromIndex:start];

    // The folder ID continues until ? or # or / or end of string
    NSCharacterSet *delimiters = [NSCharacterSet characterSetWithCharactersInString:@"?#/"];
    NSRange delimRange = [remainder rangeOfCharacterFromSet:delimiters];
    if (delimRange.location != NSNotFound) {
        remainder = [remainder substringToIndex:delimRange.location];
    }

    return remainder.length > 0 ? remainder : nil;
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self updateFolderStateFromURL:webView.URL title:webView.title];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;

    // Block navigations that would leave Google Drive (e.g. opening a file preview)
    if (url && ![url.host containsString:@"google.com"] && ![url.host containsString:@"googleapis.com"]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark - Actions

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)selectFolderTapped {
    if (!self.currentFolderId) return;

    NSString *title = self.folderNameLabel.text ?: @"Selected Folder";
    [self dismissViewControllerAnimated:YES completion:^{
        [self.delegate driveBrowserDidSelectFolderWithId:self.currentFolderId title:title];
    }];
}

@end
