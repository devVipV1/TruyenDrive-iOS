#import <UIKit/UIKit.h>

@interface TDGoogleAuth : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL isSignedIn;
@property (nonatomic, readonly, nullable) NSString *userEmail;
@property (nonatomic, readonly, nullable) NSString *userName;
@property (nonatomic, readonly, nullable) NSString *authUser;

- (void)presentLoginFromViewController:(UIViewController *)vc completion:(void(^)(BOOL success))completion;
- (void)signOut;

- (nullable NSString *)sapisidHashForTimestamp:(NSUInteger)timestamp;
- (nullable NSURLRequest *)authenticatedRequestWithURL:(NSURL *)url method:(NSString *)method body:(nullable NSData *)body;

- (void)uploadFileData:(NSData *)fileData
              fileName:(NSString *)fileName
              mimeType:(NSString *)mimeType
        parentFolderId:(NSString *)folderId
            completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

- (void)refreshCookies:(void(^)(void))completion;

@end
