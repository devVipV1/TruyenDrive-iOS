#import <UIKit/UIKit.h>

@class TDDriveItem, TDChapter;

@protocol TDDriveBrowserDelegate <NSObject>
- (void)driveBrowserDidSelectFolderWithId:(NSString *)folderId title:(NSString *)title;
@end

@interface TDDriveBrowserViewController : UIViewController
@property (nonatomic, weak) id<TDDriveBrowserDelegate> delegate;
@property (nonatomic, copy) NSString *folderId; // nil = My Drive root
@property (nonatomic, copy) NSString *folderTitle;
@end
