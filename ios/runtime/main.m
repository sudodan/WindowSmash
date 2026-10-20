#import <UIKit/UIKit.h>
#import "ios/window.h"
#include "core_test.h"
@interface RuntimeController : UIViewController
@property(nonatomic, strong) UITextView *text;
@property(nonatomic, strong) UIBarButtonItem *memoryButton;
@end
@implementation RuntimeController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"Apple runtime integration";
    UIView *surface=ws_ios_create_surface();
    surface.frame=self.view.bounds; surface.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:surface];
    self.text=[[UITextView alloc] initWithFrame:self.view.bounds];
    self.text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.text.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.text.editable=NO; self.text.text=@"Testing upstream runtime core…";
    [self.view addSubview:self.text];
    self.memoryButton=[[UIBarButtonItem alloc] initWithTitle:@"Test address layout" style:UIBarButtonItemStylePlain target:self action:@selector(testLayout)];
    self.memoryButton.enabled=NO;
    self.navigationItem.rightBarButtonItem=self.memoryButton;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        char report[4096]={0}; int result=ws_runtime_test(report,sizeof report);
        NSString *text=[NSString stringWithFormat:@"Apple runtime integration v0.1\nOS: %@\n\n%s\nCore status: %@\n\nLarge guest address layout: NOT TESTED. Tap Test address layout to try the upstream reservation. Success is not a game boot.\n\nGraphics source compiles separately; this app does not run the game renderer. No game files included.\n",NSProcessInfo.processInfo.operatingSystemVersionString,report,result?@"FAIL":@"PASS"];
        dispatch_async(dispatch_get_main_queue(), ^{self.text.text=text; self.memoryButton.enabled=YES;});
    });
}
- (void)testLayout {
    self.memoryButton.enabled=NO;
    self.text.text=[self.text.text stringByAppendingString:@"\nAttempting 512 GiB virtual guest window at 1 TiB (not physical RAM allocation)…\n"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        int result=rt_guest_window();
        dispatch_async(dispatch_get_main_queue(), ^{
            self.text.text=[self.text.text stringByAppendingFormat:@"Guest window reservation: %@. No full game memory commitment tested.\n",result?@"PASS":@"FAIL"];
        });
    });
}
- (void)share {
    UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:@[self.text.text] applicationActivities:nil];
    sheet.popoverPresentationController.barButtonItem=self.navigationItem.leftBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}
@end
@interface RuntimeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation RuntimeDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:[RuntimeController new]];
    [self.window makeKeyAndVisible]; return YES;
}
- (void)applicationDidBecomeActive:(UIApplication *)app { ws_ios_set_active(1); }
- (void)applicationWillResignActive:(UIApplication *)app { ws_ios_set_active(0); }
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(RuntimeDelegate.class)); } }
