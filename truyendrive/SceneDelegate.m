#import "SceneDelegate.h"
#import "ViewController.h"
#import "TDEncoderViewController.h"
#import "TDSettingsViewController.h"

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

    // Reader Tab
    ViewController *readerVC = [[ViewController alloc] init];
    UINavigationController *readerNav = [[UINavigationController alloc] initWithRootViewController:readerVC];
    readerNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Read"
        image:[UIImage systemImageNamed:@"book.pages"]
        selectedImage:[UIImage systemImageNamed:@"book.pages.fill"]];

    // Encoder Tab
    TDEncoderViewController *encoderVC = [[TDEncoderViewController alloc] init];
    UINavigationController *encoderNav = [[UINavigationController alloc] initWithRootViewController:encoderVC];
    encoderNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Encrypt"
        image:[UIImage systemImageNamed:@"lock.shield"]
        selectedImage:[UIImage systemImageNamed:@"lock.shield.fill"]];

    // Settings Tab
    TDSettingsViewController *settingsVC = [[TDSettingsViewController alloc] init];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
        image:[UIImage systemImageNamed:@"gearshape"]
        selectedImage:[UIImage systemImageNamed:@"gearshape.fill"]];

    UITabBarController *tabBar = [[UITabBarController alloc] init];
    tabBar.viewControllers = @[readerNav, encoderNav, settingsNav];

    tabBar.tabBar.tintColor = UIColor.systemBlueColor;

    self.window.rootViewController = tabBar;
    [self.window makeKeyAndVisible];
}

@end
