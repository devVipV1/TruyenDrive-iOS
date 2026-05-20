#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Data Models

@interface TDDriveItem : NSObject
@property (nonatomic, copy) NSString *itemId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@property (nonatomic, assign) BOOL requiresDecryption;
@end

@interface TDChapter : NSObject
@property (nonatomic, copy) NSString *chapterId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *kind; // "folder" or "pdf"
@property (nonatomic, assign) NSTimeInterval updatedAt;
@end

@interface TDFolderResult : NSObject
@property (nonatomic, strong) NSArray<TDDriveItem *> *images;
@property (nonatomic, strong) NSArray<TDChapter *> *chapters;
@property (nonatomic, copy, nullable) NSString *password;
@property (nonatomic, copy, nullable) NSString *nextCursor;
@property (nonatomic, assign) BOOL isMixed;
@property (nonatomic, assign) BOOL isEmpty;
@end

@interface TDFolderDetails : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *ownerEmail;
@end

#pragma mark - API

@interface TDDriveAPI : NSObject

+ (instancetype)shared;

- (void)fetchFolderItems:(NSString *)folderId
                  cursor:(nullable NSString *)cursor
              completion:(void(^)(TDFolderResult * _Nullable result, NSError * _Nullable error))completion;

- (void)fetchFolderDetails:(NSString *)folderId
                completion:(void(^)(TDFolderDetails * _Nullable details, NSError * _Nullable error))completion;

- (NSString *)imageURLForId:(NSString *)imageId;
- (NSString *)fetchURLForId:(NSString *)imageId width:(NSInteger)width height:(NSInteger)height;
- (NSString *)thumbnailURLForId:(NSString *)imageId;

+ (nullable NSString *)folderIdFromURL:(NSString *)urlString;

@end

NS_ASSUME_NONNULL_END
