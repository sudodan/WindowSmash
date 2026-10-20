#import <UIKit/UIKit.h>
#import "ios/window.h"
#include "core_test.h"
#include "boot_test.h"
#include "shader_test.h"
@interface RuntimeController : UIViewController
@property(nonatomic, strong) UITextView *text;
@property(nonatomic, strong) UIBarButtonItem *memoryButton;
@property(nonatomic, strong) UIBarButtonItem *shaderButton;
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
    self.memoryButton=[[UIBarButtonItem alloc] initWithTitle:@"Boot synthetic guest" style:UIBarButtonItemStylePlain target:self action:@selector(testLayout)];
    self.memoryButton.enabled=NO;
    self.shaderButton=[[UIBarButtonItem alloc] initWithTitle:@"Test shaders" style:UIBarButtonItemStylePlain target:self action:@selector(testShaders)];
    self.shaderButton.enabled=NO;
    self.navigationItem.rightBarButtonItems=@[self.memoryButton,self.shaderButton];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        char report[4096]={0}; int result=ws_runtime_test(report,sizeof report);
        NSString *text=[NSString stringWithFormat:@"Apple runtime integration v0.3\nOS: %@\n\n%s\nCore status: %@\n\nSynthetic guest boot: NOT TESTED. Tap Boot synthetic guest to reserve the upstream address layout and run the loader/kernel fixture.\n\nShader execution: NOT TESTED. Tap Test shaders to run synthetic GPU comparisons. The full game renderer is not exercised. No game files included.\n",NSProcessInfo.processInfo.operatingSystemVersionString,report,result?@"FAIL":@"PASS"];
        dispatch_async(dispatch_get_main_queue(), ^{self.text.text=text; self.memoryButton.enabled=YES; self.shaderButton.enabled=YES;});
    });
}
- (void)testLayout {
    self.memoryButton.enabled=NO;
    self.text.text=[self.text.text stringByAppendingString:@"\nStarting synthetic boot: 512 GiB virtual guest window at 1 TiB, real loader/kernel, synthetic module images…\n"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSString *path=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"boot-fixtures"];
        char report[8192]={0};
        int result=ws_boot_test(path.fileSystemRepresentation,report,sizeof report);
        NSString *message=[NSString stringWithFormat:@"%s\nSynthetic boot status: %@\n",report,result?@"FAILED/BLOCKED":@"PASS"];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.text.text=[self.text.text stringByAppendingString:message];
        });
    });
}
- (void)testShaders {
    self.shaderButton.enabled=NO;
    self.text.text=[self.text.text stringByAppendingString:@"\nTranslating synthetic shaders and comparing Metal GPU output…\n"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        char report[32768]={0};
        int result=ws_shader_test(report,sizeof report);
        NSString *message=[NSString stringWithFormat:@"%s\nShader status: %@\n",report,result==77?@"BLOCKED":result?@"FAIL":@"PASS"];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.text.text=[self.text.text stringByAppendingString:message];
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
