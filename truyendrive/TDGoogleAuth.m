#import "TDGoogleAuth.h"
#import <WebKit/WebKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <os/log.h>

static NSString *const kLoginURL = @"https://accounts.google.com/ServiceLogin?service=wise&continue=https://drive.google.com/drive/my-drive";
static NSString *const kDriveOrigin = @"https://drive.google.com";
static NSString *const kEmailKey = @"truyendrive_google_email";
static NSString *const kNameKey = @"truyendrive_google_name";

@interface TDLoginViewController : UIViewController <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, copy) void(^onComplete)(BOOL success);
@end

@implementation TDLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Sign in to Google";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    [self.view addSubview:self.webView];

    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:kLoginURL]]];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:^{ if (self.onComplete) self.onComplete(NO); }];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSString *host = webView.URL.host;
    if ([host containsString:@"drive.google.com"]) {
        [webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
            NSString *sapisid = nil;
            NSString *email = nil;
            for (NSHTTPCookie *cookie in cookies) {
                if ([cookie.name isEqualToString:@"SAPISID"] && [cookie.domain containsString:@"google.com"]) {
                    sapisid = cookie.value;
                }
            }
            if (sapisid) {
                NSString *js = @"(function(){"
                    "var e=document.querySelector('[data-email]');"
                    "var email=e?e.getAttribute('data-email'):'';"
                    "var n=document.querySelector('[data-profile-name]');"
                    "var name=n?n.getAttribute('data-profile-name'):'';"
                    "if(!name){var a=document.querySelector('img.gb_A,img.gb_q,[aria-label*=\"Google Account\"]');"
                    "if(a)name=a.getAttribute('aria-label')||'';}"
                    "if(!email){var m=document.cookie.match(/GMAIL_AT=([^;]+)/);}"
                    "return JSON.stringify({email:email,name:name});"
                    "})()";
                [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
                    NSString *email = @"";
                    NSString *name = @"";
                    if ([result isKindOfClass:[NSString class]]) {
                        NSData *d = [(NSString *)result dataUsingEncoding:NSUTF8StringEncoding];
                        NSDictionary *info = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
                        email = info[@"email"] ?: @"";
                        name = info[@"name"] ?: @"";
                    }
                    if (email.length == 0) email = @"Google User";
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSUserDefaults standardUserDefaults] setObject:email forKey:kEmailKey];
                        if (name.length > 0) [[NSUserDefaults standardUserDefaults] setObject:name forKey:kNameKey];
                        [self dismissViewControllerAnimated:YES completion:^{ if (self.onComplete) self.onComplete(YES); }];
                    });
                }];
            }
        }];
    }
}

@end

@interface TDGoogleAuth ()
@property (nonatomic, copy) NSString *cachedSapisid;
@end

@implementation TDGoogleAuth

+ (instancetype)shared {
    static TDGoogleAuth *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[TDGoogleAuth alloc] init]; });
    return inst;
}

- (BOOL)isSignedIn {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kEmailKey].length > 0;
}

- (NSString *)userEmail {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kEmailKey];
}

- (NSString *)userName {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kNameKey];
}

- (NSString *)authUser {
    return @"0";
}

- (void)presentLoginFromViewController:(UIViewController *)vc completion:(void(^)(BOOL))completion {
    TDLoginViewController *login = [[TDLoginViewController alloc] init];
    login.onComplete = completion;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:login];
    [vc presentViewController:nav animated:YES completion:nil];
}

- (void)signOut {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kEmailKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kNameKey];
    self.cachedSapisid = nil;
    WKWebsiteDataStore *store = [WKWebsiteDataStore defaultDataStore];
    [store fetchDataRecordsOfTypes:[WKWebsiteDataStore allWebsiteDataTypes] completionHandler:^(NSArray<WKWebsiteDataRecord *> *records) {
        NSArray *googleRecords = [records filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"displayName CONTAINS 'google'"]];
        [store removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes] forDataRecords:googleRecords completionHandler:^{}];
    }];
}

- (void)fetchSapisid:(void(^)(NSString *))completion {
    [[WKWebsiteDataStore defaultDataStore].httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        for (NSHTTPCookie *c in cookies) {
            if ([c.name isEqualToString:@"SAPISID"] && [c.domain containsString:@"google.com"]) {
                self.cachedSapisid = c.value;
                dispatch_async(dispatch_get_main_queue(), ^{ completion(c.value); });
                return;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
    }];
}

- (NSString *)sapisidHashForTimestamp:(NSUInteger)timestamp {
    if (!self.cachedSapisid) return nil;
    NSString *raw = [NSString stringWithFormat:@"%lu %@ %@", (unsigned long)timestamp, self.cachedSapisid, kDriveOrigin];
    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", hash[i]];
    return [NSString stringWithFormat:@"SAPISIDHASH %lu_%@ SAPISID1PHASH %lu_%@ SAPISID3PHASH %lu_%@",
            (unsigned long)timestamp, hex, (unsigned long)timestamp, hex, (unsigned long)timestamp, hex];
}

- (NSURLRequest *)authenticatedRequestWithURL:(NSURL *)url method:(NSString *)method body:(NSData *)body {
    if (!self.cachedSapisid) return nil;
    NSUInteger ts = (NSUInteger)[[NSDate date] timeIntervalSince1970];
    NSString *auth = [self sapisidHashForTimestamp:ts];
    if (!auth) return nil;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method;
    req.HTTPBody = body;
    [req setValue:auth forHTTPHeaderField:@"authorization"];
    [req setValue:self.authUser forHTTPHeaderField:@"x-goog-authuser"];
    [req setValue:@"https://drive.google.com" forHTTPHeaderField:@"origin"];
    [req setValue:@"https://drive.google.com/" forHTTPHeaderField:@"referer"];
    return req;
}

- (void)refreshCookies:(void(^)(void))completion {
    [self fetchSapisid:^(NSString *s) { completion(); }];
}

- (void)uploadFileData:(NSData *)fileData
              fileName:(NSString *)fileName
              mimeType:(NSString *)mimeType
        parentFolderId:(NSString *)folderId
            completion:(void(^)(BOOL, NSError *))completion {

    [self fetchSapisid:^(NSString *sapisid) {
        if (!sapisid) {
            completion(NO, [NSError errorWithDomain:@"TDGoogleAuth" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"Not signed in"}]);
            return;
        }

        NSString *boundary = [NSString stringWithFormat:@"td_%u", arc4random()];
        NSMutableData *body = [NSMutableData data];

        NSDictionary *meta = @{
            @"title": fileName,
            @"parents": @[@{@"id": folderId}],
        };
        NSData *metaJSON = [NSJSONSerialization dataWithJSONObject:meta options:0 error:nil];

        [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:metaJSON];
        [body appendData:[[NSString stringWithFormat:@"\r\n--%@\r\nContent-Type: %@\r\n\r\n", boundary, mimeType] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:fileData];
        [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

        // Sync WKWebView cookies to NSHTTPCookieStorage first, then upload
        [[WKWebsiteDataStore defaultDataStore].httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
            for (NSHTTPCookie *c in cookies) {
                [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:c];
            }

            NSString *uploadURL = [NSString stringWithFormat:
                @"https://clients6.google.com/upload/drive/v2internal/files?uploadType=multipart&supportsTeamDrives=true&key=%@",
                @"AIzaSyD_InbmSFufIEps5UAt2NmB_3LvBH3Sz_8"];
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:uploadURL]];
            req.HTTPMethod = @"POST";
            req.HTTPBody = body;
            req.timeoutInterval = 120;
            [req setValue:[NSString stringWithFormat:@"multipart/related; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

            NSUInteger ts = (NSUInteger)[[NSDate date] timeIntervalSince1970];
            NSString *auth = [self sapisidHashForTimestamp:ts];
            if (auth) [req setValue:auth forHTTPHeaderField:@"Authorization"];
            [req setValue:self.authUser forHTTPHeaderField:@"X-Goog-AuthUser"];
            [req setValue:@"https://drive.google.com" forHTTPHeaderField:@"Origin"];
            [req setValue:@"https://drive.google.com/" forHTTPHeaderField:@"Referer"];

            // Use session with shared cookie storage
            NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
            config.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            config.HTTPShouldSetCookies = YES;
            NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

            [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (err) {
                        os_log_error(OS_LOG_DEFAULT, "[TDUpload] Error: %{public}@", err.localizedDescription);
                        completion(NO, err); return;
                    }
                    NSInteger code = ((NSHTTPURLResponse *)resp).statusCode;
                    if (code >= 200 && code < 300) {
                        os_log_error(OS_LOG_DEFAULT, "[TDUpload] OK: %{public}@", fileName);
                        completion(YES, nil);
                    } else {
                        NSString *respBody = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
                        os_log_error(OS_LOG_DEFAULT, "[TDUpload] HTTP %ld: %{public}@", (long)code, respBody ?: @"");
                        NSString *msg = [NSString stringWithFormat:@"HTTP %ld", (long)code];
                        completion(NO, [NSError errorWithDomain:@"TDGoogleAuth" code:code userInfo:@{NSLocalizedDescriptionKey: msg}]);
                    }
                });
            }] resume];
        }];
    }];
}

@end
