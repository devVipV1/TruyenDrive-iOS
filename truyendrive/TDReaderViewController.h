#import <UIKit/UIKit.h>

@class TDDriveItem;

NS_ASSUME_NONNULL_BEGIN

@interface TDReaderViewController : UIViewController

@property (nonatomic, copy) NSString *folderTitle;
@property (nonatomic, copy, nullable) NSString *password;
@property (nonatomic, strong) NSArray<TDDriveItem *> *images;

@end

NS_ASSUME_NONNULL_END
