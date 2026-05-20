#import "TDDriveAPI.h"
#import "TDGoogleAuth.h"
#import <WebKit/WebKit.h>

#pragma mark - Constants

static NSString *const kGuestAPIKey        = @"AIzaSyC1qbk75NzWBvSaDh6KnsjjA9pIrP4lYIE";
static NSString *const kAuthAPIKey         = @"AIzaSyD_InbmSFufIEps5UAt2NmB_3LvBH3Sz_8";
static NSString *const kGuestJSPBExtension = @"W1sxNDk3LG51bGwsbnVsbCxudWxsLG51bGwsbnVsbCxudWxsLG51bGwsMSxudWxsLG51bGwsWzJdXV0=";
static NSString *const kAuthJSPBExtension  = @"W1szMDUsMCxudWxsLG51bGwsbnVsbCxudWxsLG51bGwsbnVsbCwxLG51bGwsbnVsbCxbMl1dXQ==";

static NSString *const kItemsFieldMask = @"items(parent,modified_date_millis,has_visitor_permissions,contains_unsubscribed_children,capabilities(can_copy,can_download,can_edit,can_add_children,can_delete,can_remove_children,can_share,can_trash,can_rename,can_list_children,can_read_team_drive,can_move_team_drive_item),modified_by_me_date_millis,last_viewed_by_me_date_millis,alternate_link,file_size,owner(id,focus_user_id,is_me,type,email),shortcut_details(target_id,target_mime_type,target_lookup_status,target_item,can_request_access_to_target),last_modifying_user(id,focus_user_id,is_me,type,email),has_thumbnail,thumbnail_version,title,mime_type,image(width,height),id,resource_key,shared,user_role,explicitly_trashed,quota_bytes_used,folder_color,has_child_folder,starred,file_extension,primary_sync_parent,trashed,version,team_drive_id,create_date_millis),continuation_token";
static NSString *const kItemFieldMask  = @"responses(status(code,message,details),item(parent,modified_date_millis,has_visitor_permissions,capabilities(can_copy,can_download,can_edit,can_add_children,can_delete,can_remove_children,can_share,can_trash,can_rename,can_list_children),alternate_link,file_size,owner(id,focus_user_id,is_me,type,email),shortcut_details(target_id,target_mime_type,target_lookup_status,target_item),has_thumbnail,thumbnail_version,title,mime_type,id,resource_key,shared,user_role,explicitly_trashed,folder_color,starred,file_extension,version,team_drive_id,create_date_millis,permission_summary))";

static NSString *const kMimeFolder   = @"application/vnd.google-apps.folder";
static NSString *const kMimePDF      = @"application/pdf";
static NSString *const kMimeShortcut = @"application/vnd.google-apps.shortcut";

static NSString *const kErrorDomain = @"com.truyendrive.driveapi";

#pragma mark - Model Implementations

@implementation TDDriveItem
@end

@implementation TDChapter
@end

@implementation TDFolderResult
@end

@implementation TDFolderDetails
@end

#pragma mark - TDDriveAPI

@interface TDDriveAPI ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy, readonly) NSString *guestItemsURL;
@property (nonatomic, copy, readonly) NSString *guestItemURL;
@end

@implementation TDDriveAPI

#pragma mark - Singleton

+ (instancetype)shared {
    static TDDriveAPI *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TDDriveAPI alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        _session = [NSURLSession sessionWithConfiguration:config];
        _guestItemsURL = [NSString stringWithFormat:@"https://drivefrontend-pa.clients6.google.com/v1/items:list?key=%@", kGuestAPIKey];
        _guestItemURL  = [NSString stringWithFormat:@"https://drivefrontend-pa.clients6.google.com/v1/items:get?key=%@", kGuestAPIKey];
    }
    return self;
}

#pragma mark - Public API

- (void)fetchFolderItems:(NSString *)folderId
                  cursor:(nullable NSString *)cursor
              completion:(void(^)(TDFolderResult * _Nullable, NSError * _Nullable))completion {

    NSString *cursorJSON = cursor ? cursor : @"";
    NSString *body = [NSString stringWithFormat:
        @"[[null,null,null,null,0,null,null,null,null,null,null,null,null,null,null,null,null,null,null,\"\",null,0,null,null,[4,1,1],null,null,null,null,null,null,null,null,null,null,[[1]],null,null,null,null,null,null,null,[[\"%@\"]]],[50,\"%@\",[2,5]]]",
        [self jsonEscapeString:folderId],
        [self jsonEscapeString:cursorJSON]];

    if ([TDGoogleAuth shared].isSignedIn) {
        [self authFetchWithBody:body fieldMask:kItemsFieldMask completion:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) { completion(nil, error); return; }
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode != 200) {
                completion(nil, [NSError errorWithDomain:kErrorDomain code:httpResponse.statusCode
                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]}]);
                return;
            }
            NSArray *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![root isKindOfClass:[NSArray class]]) { completion(nil, [NSError errorWithDomain:kErrorDomain code:-1 userInfo:nil]); return; }
            TDFolderResult *result = [self parseFolderResult:root];
            completion(result, nil);
        }];
        return;
    }

    NSMutableURLRequest *request = [self guestRequestWithURL:self.guestItemsURL
                                                   fieldMask:kItemsFieldMask
                                                        body:body];

    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSError *statusError = [NSError errorWithDomain:kErrorDomain
                                                       code:httpResponse.statusCode
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]}];
            completion(nil, statusError);
            return;
        }

        NSError *parseError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (parseError || ![json isKindOfClass:[NSArray class]]) {
            completion(nil, parseError ?: [NSError errorWithDomain:kErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid response format"}]);
            return;
        }

        NSArray *root = (NSArray *)json;
        TDFolderResult *result = [self parseFolderResult:root];
        completion(result, nil);
    }] resume];
}

- (void)fetchFolderDetails:(NSString *)folderId
                completion:(void(^)(TDFolderDetails * _Nullable, NSError * _Nullable))completion {

    NSString *body = [NSString stringWithFormat:
        @"[[\"%@\"],[null,null,null,null,null,[2,5]]]",
        [self jsonEscapeString:folderId]];

    NSMutableURLRequest *request = [self guestRequestWithURL:self.guestItemURL
                                                   fieldMask:kItemFieldMask
                                                        body:body];

    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            NSError *statusError = [NSError errorWithDomain:kErrorDomain
                                                       code:httpResponse.statusCode
                                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode]}];
            completion(nil, statusError);
            return;
        }

        NSError *parseError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (parseError || ![json isKindOfClass:[NSArray class]]) {
            completion(nil, parseError ?: [NSError errorWithDomain:kErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid response format"}]);
            return;
        }

        TDFolderDetails *details = [self parseDetailsFromResponse:(NSArray *)json];
        if (!details) {
            completion(nil, [NSError errorWithDomain:kErrorDomain code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Could not parse folder details"}]);
            return;
        }
        completion(details, nil);
    }] resume];
}

- (NSString *)imageURLForId:(NSString *)imageId {
    return [NSString stringWithFormat:@"https://drive.google.com/u/0/drive-usercontent/%@", imageId];
}

- (NSString *)fetchURLForId:(NSString *)imageId width:(NSInteger)width height:(NSInteger)height {
    NSString *base = [self imageURLForId:imageId];
    return [NSString stringWithFormat:@"%@=w10000", base];
}

- (NSString *)thumbnailURLForId:(NSString *)imageId {
    return [NSString stringWithFormat:@"%@=s220", [self imageURLForId:imageId]];
}

+ (nullable NSString *)folderIdFromURL:(NSString *)urlString {
    if (!urlString) return nil;

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"/folders/([^/?#]+)"
                                                                          options:0
                                                                            error:&error];
    if (error) return nil;

    NSTextCheckingResult *match = [regex firstMatchInString:urlString
                                                    options:0
                                                      range:NSMakeRange(0, urlString.length)];
    if (match && match.numberOfRanges > 1) {
        NSRange range = [match rangeAtIndex:1];
        if (range.location != NSNotFound) {
            return [urlString substringWithRange:range];
        }
    }
    return nil;
}

#pragma mark - Request Building

- (NSMutableURLRequest *)guestRequestWithURL:(NSString *)urlString
                                   fieldMask:(NSString *)fieldMask
                                        body:(NSString *)body {

    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

    [request setValue:@"application/json+protobuf" forHTTPHeaderField:@"content-type"];
    [request setValue:kGuestJSPBExtension forHTTPHeaderField:@"x-goog-ext-472780938-jspb"];
    [request setValue:fieldMask forHTTPHeaderField:@"x-goog-fieldmask"];
    [request setValue:@"*/*" forHTTPHeaderField:@"accept"];
    [request setValue:@"vi" forHTTPHeaderField:@"accept-language"];
    [request setValue:@"https://drive.google.com" forHTTPHeaderField:@"origin"];
    [request setValue:@"https://drive.google.com/" forHTTPHeaderField:@"referer"];

    return request;
}

- (void)authFetchWithBody:(NSString *)body
                fieldMask:(NSString *)fieldMask
               completion:(void(^)(NSData *, NSURLResponse *, NSError *))completion {

    // Step 1: fetch SAPISID + sync cookies from WKWebView
    [[TDGoogleAuth shared] refreshCookies:^{
        [[WKWebsiteDataStore defaultDataStore].httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
            for (NSHTTPCookie *c in cookies) {
                if ([c.domain containsString:@"google"]) {
                    [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:c];
                }
            }

            // Step 2: build authenticated request
            NSString *itemsURL = [NSString stringWithFormat:@"https://drivefrontend-pa.clients6.google.com/v1/items:list?key=%@", kAuthAPIKey];
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:itemsURL]];
            request.HTTPMethod = @"POST";
            request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

            TDGoogleAuth *auth = [TDGoogleAuth shared];
            NSUInteger ts = (NSUInteger)[[NSDate date] timeIntervalSince1970];
            NSString *sapisidHash = [auth sapisidHashForTimestamp:ts];

            [request setValue:@"application/json+protobuf" forHTTPHeaderField:@"content-type"];
            [request setValue:kAuthJSPBExtension forHTTPHeaderField:@"x-goog-ext-472780938-jspb"];
            [request setValue:fieldMask forHTTPHeaderField:@"x-goog-fieldmask"];
            [request setValue:@"*/*" forHTTPHeaderField:@"accept"];
            [request setValue:@"vi" forHTTPHeaderField:@"accept-language"];
            [request setValue:@"https://drive.google.com" forHTTPHeaderField:@"origin"];
            [request setValue:@"https://drive.google.com/" forHTTPHeaderField:@"referer"];
            if (sapisidHash) [request setValue:sapisidHash forHTTPHeaderField:@"authorization"];
            [request setValue:auth.authUser forHTTPHeaderField:@"x-goog-authuser"];

            // Step 3: use session with synced cookies
            NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
            config.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            config.HTTPShouldSetCookies = YES;
            NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

            [[session dataTaskWithRequest:request completionHandler:completion] resume];
        }];
    }];
}

#pragma mark - Response Parsing (items:list)

- (TDFolderResult *)parseFolderResult:(NSArray *)root {
    TDFolderResult *result = [[TDFolderResult alloc] init];
    result.images = @[];
    result.chapters = @[];

    // root[0] = array of items, root[1] = continuation token
    NSArray *items = [self safeArrayAtIndex:0 inArray:root];
    NSString *continuationToken = [self safeStringAtIndex:1 inArray:root];

    if (continuationToken.length > 0) {
        result.nextCursor = continuationToken;
    }

    if (!items || items.count == 0) {
        result.isEmpty = YES;
        return result;
    }

    NSMutableArray<TDDriveItem *> *parsedImages = [NSMutableArray array];
    NSMutableArray<TDChapter *> *parsedChapters = [NSMutableArray array];
    NSString *password = nil;

    for (id rawItem in items) {
        if (![rawItem isKindOfClass:[NSArray class]]) continue;
        NSArray *item = (NSArray *)rawItem;

        NSString *itemId   = [self safeStringAtIndex:0 inArray:item];
        NSString *title    = [self safeStringAtIndex:2 inArray:item];
        NSString *mimeType = [self safeStringAtIndex:3 inArray:item];

        if (!itemId || !mimeType) continue;

        // Check for password file
        if (title) {
            NSString *pw = [self extractPasswordFromName:title];
            if (pw) {
                password = pw;
                continue;
            }
        }

        // Skip shortcuts (would need resolve logic for full support)
        if ([mimeType isEqualToString:kMimeShortcut]) {
            continue;
        }

        // Folders
        if ([mimeType isEqualToString:kMimeFolder]) {
            TDChapter *chapter = [[TDChapter alloc] init];
            chapter.chapterId = itemId;
            chapter.name = title ?: @"";
            chapter.kind = @"folder";
            chapter.updatedAt = [self safeNumberAtIndex:9 inArray:item] / 1000.0;
            [parsedChapters addObject:chapter];
            continue;
        }

        // PDFs
        if ([mimeType isEqualToString:kMimePDF]) {
            TDChapter *chapter = [[TDChapter alloc] init];
            chapter.chapterId = itemId;
            chapter.name = title ?: @"";
            chapter.kind = @"pdf";
            chapter.updatedAt = [self safeNumberAtIndex:9 inArray:item] / 1000.0;
            [parsedChapters addObject:chapter];
            continue;
        }

        // Images
        if ([mimeType hasPrefix:@"image/"]) {
            TDDriveItem *image = [[TDDriveItem alloc] init];
            image.itemId = itemId;
            image.title = title ?: @"";
            image.mimeType = mimeType;
            image.requiresDecryption = NO;

            NSArray *dimArray = [self safeArrayAtIndex:26 inArray:item];
            if (dimArray) {
                image.width  = [self safeIntegerAtIndex:1 inArray:dimArray];
                image.height = [self safeIntegerAtIndex:2 inArray:dimArray];
            }

            [parsedImages addObject:image];
            continue;
        }
    }

    result.images = [parsedImages copy];
    result.chapters = [parsedChapters copy];
    result.password = password;
    result.isMixed = (parsedImages.count > 0 && parsedChapters.count > 0);
    result.isEmpty = (parsedImages.count == 0 && parsedChapters.count == 0);

    return result;
}

#pragma mark - Response Parsing (items:get)

- (nullable TDFolderDetails *)parseDetailsFromResponse:(NSArray *)root {
    // response[0] = array of response entries
    NSArray *responses = [self safeArrayAtIndex:0 inArray:root];
    if (!responses) return nil;

    // Search recursively for an item-like array: [0]=string id, [2]=string title, [3]=string mimeType
    NSArray *itemArray = [self findItemArrayInObject:responses];
    if (!itemArray) return nil;

    TDFolderDetails *details = [[TDFolderDetails alloc] init];
    details.title = [self safeStringAtIndex:2 inArray:itemArray] ?: @"";

    // Owner email at item[16][7]
    NSArray *ownerInfo = [self safeArrayAtIndex:16 inArray:itemArray];
    if (ownerInfo) {
        details.ownerEmail = [self safeStringAtIndex:7 inArray:ownerInfo] ?: @"";
    } else {
        details.ownerEmail = @"";
    }

    return details;
}

/// Recursively search for an array that looks like a Drive item:
/// index 0 is a string, index 2 is a string, index 3 is a string.
- (nullable NSArray *)findItemArrayInObject:(id)obj {
    if (![obj isKindOfClass:[NSArray class]]) return nil;
    NSArray *arr = (NSArray *)obj;

    // Check if this array itself looks like an item
    if (arr.count > 3) {
        NSString *idx0 = [self safeStringAtIndex:0 inArray:arr];
        NSString *idx2 = [self safeStringAtIndex:2 inArray:arr];
        NSString *idx3 = [self safeStringAtIndex:3 inArray:arr];
        if (idx0 && idx2 && idx3) {
            return arr;
        }
    }

    // Recurse into children
    for (id child in arr) {
        NSArray *found = [self findItemArrayInObject:child];
        if (found) return found;
    }

    return nil;
}

#pragma mark - Password Extraction

- (nullable NSString *)extractPasswordFromName:(NSString *)name {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^\\.password\\.(.+)\\.truyendrive$"
                                                                          options:0
                                                                            error:&error];
    if (error) return nil;

    NSTextCheckingResult *match = [regex firstMatchInString:name
                                                    options:0
                                                      range:NSMakeRange(0, name.length)];
    if (match && match.numberOfRanges > 1) {
        NSRange range = [match rangeAtIndex:1];
        if (range.location != NSNotFound) {
            return [name substringWithRange:range];
        }
    }
    return nil;
}

#pragma mark - Safe Accessors

- (nullable NSArray *)safeArrayAtIndex:(NSUInteger)index inArray:(NSArray *)array {
    if (index >= array.count) return nil;
    id obj = array[index];
    if ([obj isKindOfClass:[NSArray class]]) return obj;
    return nil;
}

- (nullable NSString *)safeStringAtIndex:(NSUInteger)index inArray:(NSArray *)array {
    if (index >= array.count) return nil;
    id obj = array[index];
    if ([obj isKindOfClass:[NSString class]]) return obj;
    return nil;
}

- (NSInteger)safeIntegerAtIndex:(NSUInteger)index inArray:(NSArray *)array {
    if (index >= array.count) return 0;
    id obj = array[index];
    if ([obj isKindOfClass:[NSNumber class]]) return [obj integerValue];
    return 0;
}

- (double)safeNumberAtIndex:(NSUInteger)index inArray:(NSArray *)array {
    if (index >= array.count) return 0;
    id obj = array[index];
    if ([obj isKindOfClass:[NSNumber class]]) return [obj doubleValue];
    return 0;
}

- (NSString *)jsonEscapeString:(NSString *)string {
    // Escape backslashes and double quotes for embedding in JSON string literals
    NSString *escaped = [string stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return escaped;
}

@end
