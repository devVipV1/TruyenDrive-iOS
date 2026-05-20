#import "TDReaderViewController.h"
#import "TDDriveAPI.h"
#import "TDImageDecryptor.h"
#import <os/log.h>

static NSString *const kReaderCellId = @"TDReaderCell";
static const CGFloat kDefaultAspectRatio = 3.0 / 4.0; // height / width for 4:3
static const NSInteger kPreloadAhead = 5;
static const NSInteger kPreloadBehind = 2;
static const NSInteger kImageCacheLimit = 50;
static const NSTimeInterval kBarAutoHideDelay = 3.0;

#pragma mark - TDReaderCell

@interface TDReaderCell : UICollectionViewCell <UIScrollViewDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *downloadTask;

- (void)configureWithImage:(UIImage *)image;
- (void)showLoading;
- (void)resetZoom;

@end

@implementation TDReaderCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.blackColor;
        self.contentView.backgroundColor = UIColor.blackColor;

        _scrollView = [[UIScrollView alloc] initWithFrame:self.contentView.bounds];
        _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _scrollView.delegate = self;
        _scrollView.minimumZoomScale = 1.0;
        _scrollView.maximumZoomScale = 4.0;
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.bouncesZoom = YES;
        [self.contentView addSubview:_scrollView];

        _imageView = [[UIImageView alloc] init];
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.clipsToBounds = YES;
        [_scrollView addSubview:_imageView];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.color = UIColor.whiteColor;
        _spinner.hidesWhenStopped = YES;
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_spinner];

        [NSLayoutConstraint activateConstraints:@[
            [_spinner.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_spinner.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];

        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        [_scrollView addGestureRecognizer:doubleTap];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.downloadTask cancel];
    self.downloadTask = nil;
    self.imageView.image = nil;
    [self resetZoom];
    [self.spinner stopAnimating];
}

- (void)configureWithImage:(UIImage *)image {
    [self.spinner stopAnimating];
    self.imageView.image = image;
    [self layoutImageView];
}

- (void)showLoading {
    self.imageView.image = nil;
    [self.spinner startAnimating];
}

- (void)resetZoom {
    self.scrollView.zoomScale = 1.0;
    [self layoutImageView];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.scrollView.frame = self.contentView.bounds;
    [self layoutImageView];
}

- (void)layoutImageView {
    CGSize boundsSize = self.scrollView.bounds.size;
    if (boundsSize.width == 0 || boundsSize.height == 0) return;

    UIImage *image = self.imageView.image;
    if (image) {
        CGFloat imageAspect = image.size.height / image.size.width;
        CGFloat displayWidth = boundsSize.width * self.scrollView.zoomScale;
        CGFloat displayHeight = displayWidth * imageAspect;
        self.imageView.frame = CGRectMake(0, 0, boundsSize.width, boundsSize.width * imageAspect);
        self.scrollView.contentSize = CGSizeMake(displayWidth, displayHeight);
    } else {
        self.imageView.frame = CGRectMake(0, 0, boundsSize.width, boundsSize.height);
        self.scrollView.contentSize = boundsSize;
    }
}

#pragma mark - UIScrollViewDelegate (Zoom)

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    // Center the image when zoomed out smaller than the scroll view
    CGSize boundsSize = scrollView.bounds.size;
    CGRect frameToCenter = self.imageView.frame;

    if (frameToCenter.size.width < boundsSize.width) {
        frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2.0;
    } else {
        frameToCenter.origin.x = 0;
    }

    if (frameToCenter.size.height < boundsSize.height) {
        frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2.0;
    } else {
        frameToCenter.origin.y = 0;
    }

    self.imageView.frame = frameToCenter;
}

#pragma mark - Double-tap Zoom

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (self.scrollView.zoomScale > self.scrollView.minimumZoomScale) {
        [self.scrollView setZoomScale:self.scrollView.minimumZoomScale animated:YES];
    } else {
        CGPoint point = [recognizer locationInView:self.imageView];
        CGFloat newScale = 2.0;
        CGSize scrollSize = self.scrollView.bounds.size;
        CGFloat w = scrollSize.width / newScale;
        CGFloat h = scrollSize.height / newScale;
        CGRect zoomRect = CGRectMake(point.x - w / 2.0, point.y - h / 2.0, w, h);
        [self.scrollView zoomToRect:zoomRect animated:YES];
    }
}

@end

#pragma mark - TDReaderViewController

@interface TDReaderViewController () <UICollectionViewDataSource, UICollectionViewDelegate,
                                       UICollectionViewDelegateFlowLayout,
                                       UICollectionViewDataSourcePrefetching>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UICollectionViewFlowLayout *flowLayout;

// Top bar
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIVisualEffectView *topBarBackground;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic, assign) BOOL topBarVisible;
@property (nonatomic, strong, nullable) NSTimer *autoHideTimer;

// Image cache & loading
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *imageCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDataTask *> *activeTasks;
@property (nonatomic, strong) NSURLSession *downloadSession;

// State
@property (nonatomic, assign) NSInteger currentPage;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *cachedImageSizes;

@end

@implementation TDReaderViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.blackColor;
    self.currentPage = 0;
    self.topBarVisible = YES;

    [self setupImageCache];
    [self setupCollectionView];
    [self setupTopBar];
    [self scheduleAutoHide];

    // Tap to toggle top bar
    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    singleTap.delaysTouchesBegan = NO;
    singleTap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:singleTap];

    // Do not interfere with double-tap on cells
    for (UIGestureRecognizer *gr in self.collectionView.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
            [singleTap requireGestureRecognizerToFail:gr];
        }
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self updatePageLabel];
    [self preloadImagesAroundIndex:self.currentPage];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.autoHideTimer invalidate];
    self.autoHideTimer = nil;
}

- (void)dealloc {
    [self.autoHideTimer invalidate];
    [self cancelAllDownloads];
}

#pragma mark - Status Bar

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

#pragma mark - Setup

- (void)setupImageCache {
    self.imageCache = [[NSCache alloc] init];
    self.imageCache.countLimit = kImageCacheLimit;
    [self.imageCache removeAllObjects];
    self.activeTasks = [NSMutableDictionary dictionary];
    self.cachedImageSizes = [NSMutableDictionary dictionary];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 60;
    config.HTTPMaximumConnectionsPerHost = 6;
    self.downloadSession = [NSURLSession sessionWithConfiguration:config];
}

- (void)setupCollectionView {
    self.flowLayout = [[UICollectionViewFlowLayout alloc] init];
    self.flowLayout.scrollDirection = UICollectionViewScrollDirectionVertical;
    self.flowLayout.minimumLineSpacing = 0;
    self.flowLayout.minimumInteritemSpacing = 0;

    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds
                                             collectionViewLayout:self.flowLayout];
    self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.collectionView.backgroundColor = UIColor.blackColor;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.prefetchDataSource = self;
    self.collectionView.showsVerticalScrollIndicator = YES;
    self.collectionView.showsHorizontalScrollIndicator = NO;
    self.collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.collectionView.alwaysBounceVertical = YES;

    [self.collectionView registerClass:[TDReaderCell class] forCellWithReuseIdentifier:kReaderCellId];

    [self.view addSubview:self.collectionView];
}

- (void)setupTopBar {
    self.topBar = [[UIView alloc] init];
    self.topBar.translatesAutoresizingMaskIntoConstraints = NO;

    // Glass / blur background
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *glass = [[UIGlassEffect alloc] init];
        self.topBarBackground = [[UIVisualEffectView alloc] initWithEffect:glass];
    } else {
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        self.topBarBackground = [[UIVisualEffectView alloc] initWithEffect:blur];
    }
    self.topBarBackground.translatesAutoresizingMaskIntoConstraints = NO;
    [self.topBar addSubview:self.topBarBackground];

    // Back button
    UIImageSymbolConfiguration *btnConfig = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backButton setImage:[UIImage systemImageNamed:@"chevron.left" withConfiguration:btnConfig] forState:UIControlStateNormal];
    self.backButton.tintColor = UIColor.whiteColor;
    self.backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backButton addTarget:self action:@selector(dismissReader) forControlEvents:UIControlEventTouchUpInside];
    self.backButton.contentEdgeInsets = UIEdgeInsetsMake(8, 8, 8, 8);

    // Title label
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = self.folderTitle ?: @"";
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.titleLabel.textAlignment = NSTextAlignmentCenter;

    // Page counter
    self.pageLabel = [[UILabel alloc] init];
    self.pageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pageLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.8];
    self.pageLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    self.pageLabel.textAlignment = NSTextAlignmentRight;
    [self.pageLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    [self.topBar addSubview:self.backButton];
    [self.topBar addSubview:self.titleLabel];
    [self.topBar addSubview:self.pageLabel];

    [self.view addSubview:self.topBar];

    CGFloat topPadding = [UIApplication sharedApplication].connectedScenes.allObjects.firstObject
        ? 0 : 20;

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        // Top bar frame
        [self.topBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        // Glass background fills entire top bar
        [self.topBarBackground.topAnchor constraintEqualToAnchor:self.topBar.topAnchor],
        [self.topBarBackground.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
        [self.topBarBackground.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor],
        [self.topBarBackground.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor],

        // Back button
        [self.backButton.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:8],
        [self.backButton.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor constant:-8],
        [self.backButton.widthAnchor constraintEqualToConstant:40],
        [self.backButton.heightAnchor constraintEqualToConstant:40],

        // Title
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor constant:4],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.pageLabel.leadingAnchor constant:-8],

        // Page label
        [self.pageLabel.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
        [self.pageLabel.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-16],

        // Top bar height: safe area top + content
        [self.topBar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:48],
    ]];

    [self updatePageLabel];
}

#pragma mark - Top Bar Visibility

- (void)scheduleAutoHide {
    [self.autoHideTimer invalidate];
    self.autoHideTimer = [NSTimer scheduledTimerWithTimeInterval:kBarAutoHideDelay
                                                          target:self
                                                        selector:@selector(autoHideTopBar)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)autoHideTopBar {
    [self setTopBarVisible:NO animated:YES];
}

- (void)handleSingleTap:(UITapGestureRecognizer *)recognizer {
    [self toggleTopBar];
}

- (void)toggleTopBar {
    [self setTopBarVisible:!self.topBarVisible animated:YES];
}

- (void)setTopBarVisible:(BOOL)visible animated:(BOOL)animated {
    if (self.topBarVisible == visible) return;
    self.topBarVisible = visible;

    [self.autoHideTimer invalidate];
    self.autoHideTimer = nil;

    if (visible) {
        [self scheduleAutoHide];
    }

    NSTimeInterval duration = animated ? 0.3 : 0;
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.topBar.alpha = visible ? 1.0 : 0.0;
    } completion:nil];
}

#pragma mark - Page Tracking

- (void)updatePageLabel {
    NSInteger total = self.images.count;
    if (total == 0) {
        self.pageLabel.text = @"";
        return;
    }
    self.pageLabel.text = [NSString stringWithFormat:@"%ld / %ld", (long)(self.currentPage + 1), (long)total];
}

- (void)updateCurrentPageFromScrollPosition {
    CGFloat viewportCenter = self.collectionView.contentOffset.y + self.collectionView.bounds.size.height / 2.0;

    NSArray<UICollectionViewCell *> *visibleCells = self.collectionView.visibleCells;
    CGFloat bestDistance = CGFLOAT_MAX;
    NSInteger bestIndex = self.currentPage;

    for (UICollectionViewCell *cell in visibleCells) {
        NSIndexPath *indexPath = [self.collectionView indexPathForCell:cell];
        if (!indexPath) continue;

        CGFloat cellCenter = cell.frame.origin.y + cell.frame.size.height / 2.0;
        CGFloat distance = fabs(cellCenter - viewportCenter);

        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = indexPath.item;
        }
    }

    if (bestIndex != self.currentPage) {
        self.currentPage = bestIndex;
        [self updatePageLabel];
    }
}

#pragma mark - Dismiss

- (void)dismissReader {
    if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.images.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {

    TDReaderCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kReaderCellId forIndexPath:indexPath];

    // Cancel any previous download for this cell
    [cell.downloadTask cancel];
    cell.downloadTask = nil;
    [cell resetZoom];

    TDDriveItem *item = self.images[indexPath.item];
    NSString *itemId = item.itemId;

    // Check cache first
    UIImage *cachedImage = [self.imageCache objectForKey:itemId];
    if (cachedImage) {
        [cell configureWithImage:cachedImage];
        return cell;
    }

    // Load the image
    [cell showLoading];
    [self loadImageForItem:item inCell:cell atIndexPath:indexPath];

    return cell;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {

    CGFloat width = collectionView.bounds.size.width;
    if (width == 0) width = UIScreen.mainScreen.bounds.size.width;

    TDDriveItem *item = self.images[indexPath.item];

    // Check if we have a loaded image size that overrides the metadata
    NSValue *cachedSize = self.cachedImageSizes[@(indexPath.item)];
    if (cachedSize) {
        CGSize imageSize = cachedSize.CGSizeValue;
        if (imageSize.width > 0 && imageSize.height > 0) {
            CGFloat height = (imageSize.height / imageSize.width) * width;
            return CGSizeMake(width, height);
        }
    }

    // Use metadata dimensions
    if (item.width > 0 && item.height > 0) {
        CGFloat height = ((CGFloat)item.height / (CGFloat)item.width) * width;
        return CGSizeMake(width, height);
    }

    // Default 4:3 aspect ratio
    return CGSizeMake(width, width * kDefaultAspectRatio);
}

#pragma mark - UICollectionViewDataSourcePrefetching

- (void)collectionView:(UICollectionView *)collectionView prefetchItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    for (NSIndexPath *indexPath in indexPaths) {
        TDDriveItem *item = self.images[indexPath.item];
        if ([self.imageCache objectForKey:item.itemId]) continue;
        if (self.activeTasks[item.itemId]) continue;
        [self startDownloadForItem:item atIndex:indexPath.item];
    }
}

- (void)collectionView:(UICollectionView *)collectionView cancelPrefetchingForItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    for (NSIndexPath *indexPath in indexPaths) {
        if (indexPath.item >= (NSInteger)self.images.count) continue;
        TDDriveItem *item = self.images[indexPath.item];
        NSURLSessionDataTask *task = self.activeTasks[item.itemId];
        if (task) {
            [task cancel];
            [self.activeTasks removeObjectForKey:item.itemId];
        }
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    NSInteger prevPage = self.currentPage;
    [self updateCurrentPageFromScrollPosition];
    if (self.currentPage != prevPage) {
        [self preloadImagesAroundIndex:self.currentPage];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self preloadImagesAroundIndex:self.currentPage];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self preloadImagesAroundIndex:self.currentPage];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        [self preloadImagesAroundIndex:self.currentPage];
    }
}

#pragma mark - Image Loading

- (void)loadImageForItem:(TDDriveItem *)item inCell:(TDReaderCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    NSString *itemId = item.itemId;

    // Build the fetch URL using the API
    NSString *urlString = [[TDDriveAPI shared] fetchURLForId:item.itemId width:item.width height:item.height];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [cell.spinner stopAnimating];
        return;
    }

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.downloadSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        [strongSelf.activeTasks removeObjectForKey:itemId];

        if (error) {
            if (error.code == NSURLErrorCancelled) return;
            NSLog(@"[TDReader] Download failed for %@: %@", itemId, error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                [cell.spinner stopAnimating];
            });
            return;
        }

        if (!data || data.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [cell.spinner stopAnimating];
            });
            return;
        }

        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if ([httpResp isKindOfClass:[NSHTTPURLResponse class]] && httpResp.statusCode != 200) {
            NSLog(@"[TDReader] HTTP %ld for %@", (long)httpResp.statusCode, itemId);
            dispatch_async(dispatch_get_main_queue(), ^{ [cell.spinner stopAnimating]; });
            return;
        }

        os_log_error(OS_LOG_DEFAULT, "[TDReader] Downloaded %{public}@ (%lu bytes) from %{public}@",
            itemId, (unsigned long)data.length, url.absoluteString);

        // Debug: save first raw download
        static int rawDebug = 0;
        if (rawDebug < 1) {
            NSString *rawPath = [NSString stringWithFormat:@"/tmp/app_raw_%@.png", itemId];
            [data writeToFile:rawPath atomically:YES];
            os_log_error(OS_LOG_DEFAULT, "[TDDebug] Saved raw %{public}@", rawPath);
            rawDebug++;
        }

        if (strongSelf.password.length > 0) {
            [TDImageDecryptor decryptImageData:data password:strongSelf.password completion:^(UIImage *decryptedImage, NSError *decryptError) {
                if (!decryptedImage) {
                    UIImage *plainImage = [UIImage imageWithData:data];
                    if (plainImage) {
                        [strongSelf cacheAndDisplayImage:plainImage forItemId:itemId atIndex:indexPath.item cell:cell];
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [cell.spinner stopAnimating];
                        });
                    }
                    return;
                }
                [strongSelf cacheAndDisplayImage:decryptedImage forItemId:itemId atIndex:indexPath.item cell:cell];
            }];
        } else {
            // No decryption needed
            UIImage *image = [UIImage imageWithData:data];
            if (!image) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [cell.spinner stopAnimating];
                });
                return;
            }
            [strongSelf cacheAndDisplayImage:image forItemId:itemId atIndex:indexPath.item cell:cell];
        }
    }];

    cell.downloadTask = task;
    self.activeTasks[itemId] = task;
    [task resume];
}

- (void)startDownloadForItem:(TDDriveItem *)item atIndex:(NSInteger)index {
    NSString *itemId = item.itemId;
    if ([self.imageCache objectForKey:itemId]) return;
    if (self.activeTasks[itemId]) return;

    NSString *urlString = [[TDDriveAPI shared] fetchURLForId:item.itemId width:item.width height:item.height];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [self.downloadSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        [strongSelf.activeTasks removeObjectForKey:itemId];

        if (error || !data || data.length == 0) return;

        if (strongSelf.password.length > 0) {
            [TDImageDecryptor decryptImageData:data password:strongSelf.password completion:^(UIImage *decryptedImage, NSError *decryptError) {
                UIImage *finalImage = decryptedImage ?: [UIImage imageWithData:data];
                if (finalImage) {
                    [strongSelf cacheImageOnly:finalImage forItemId:itemId atIndex:index];
                }
            }];
        } else {
            UIImage *image = [UIImage imageWithData:data];
            if (image) {
                [strongSelf cacheImageOnly:image forItemId:itemId atIndex:index];
            }
        }
    }];

    self.activeTasks[itemId] = task;
    [task resume];
}

- (void)cacheAndDisplayImage:(UIImage *)image forItemId:(NSString *)itemId atIndex:(NSInteger)index cell:(TDReaderCell *)cell {
    [self.imageCache setObject:image forKey:itemId];

    // Check if the cell size needs updating (metadata was missing or wrong)
    BOOL needsReload = NO;
    if (index < (NSInteger)self.images.count) {
        TDDriveItem *item = self.images[index];
        if (item.width == 0 || item.height == 0) {
            self.cachedImageSizes[@(index)] = [NSValue valueWithCGSize:image.size];
            needsReload = YES;
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        // Verify the cell is still displaying the same item
        NSIndexPath *cellIndexPath = [self.collectionView indexPathForCell:cell];
        if (cellIndexPath && cellIndexPath.item == index) {
            [cell configureWithImage:image];
        }

        if (needsReload) {
            [UIView performWithoutAnimation:^{
                [self.collectionView.collectionViewLayout invalidateLayout];
            }];
        }
    });
}

- (void)cacheImageOnly:(UIImage *)image forItemId:(NSString *)itemId atIndex:(NSInteger)index {
    [self.imageCache setObject:image forKey:itemId];

    if (index < (NSInteger)self.images.count) {
        TDDriveItem *item = self.images[index];
        if (item.width == 0 || item.height == 0) {
            self.cachedImageSizes[@(index)] = [NSValue valueWithCGSize:image.size];
            dispatch_async(dispatch_get_main_queue(), ^{
                [UIView performWithoutAnimation:^{
                    [self.collectionView.collectionViewLayout invalidateLayout];
                }];
            });
        }
    }
}

#pragma mark - Preloading

- (void)preloadImagesAroundIndex:(NSInteger)centerIndex {
    NSInteger count = self.images.count;
    if (count == 0) return;

    NSInteger startIndex = MAX(0, centerIndex - kPreloadBehind);
    NSInteger endIndex = MIN(count - 1, centerIndex + kPreloadAhead);

    for (NSInteger i = startIndex; i <= endIndex; i++) {
        TDDriveItem *item = self.images[i];
        if ([self.imageCache objectForKey:item.itemId]) continue;
        if (self.activeTasks[item.itemId]) continue;
        [self startDownloadForItem:item atIndex:i];
    }
}

#pragma mark - Cleanup

- (void)cancelAllDownloads {
    for (NSURLSessionDataTask *task in self.activeTasks.allValues) {
        [task cancel];
    }
    [self.activeTasks removeAllObjects];
}

#pragma mark - Rotation

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    NSInteger currentIndex = self.currentPage;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.collectionView.collectionViewLayout invalidateLayout];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Scroll back to current page after rotation
        if (currentIndex < (NSInteger)self.images.count) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:currentIndex inSection:0];
            [self.collectionView scrollToItemAtIndexPath:indexPath
                                       atScrollPosition:UICollectionViewScrollPositionTop
                                               animated:NO];
        }
    }];
}

@end
