#import <UIKit/UIKit.h>
#include "renderer_test.h"
@interface RendererController:UIViewController
@property(nonatomic,strong) UITextView *text;
@property(nonatomic,strong) UIBarButtonItem *runButton;
@end
@implementation RendererController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Renderer diagnostic";
    self.text=[[UITextView alloc] initWithFrame:self.view.bounds];
    self.text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.text.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];self.text.editable=NO;
    self.text.text=@"Actual Metal renderer test v0.1\n\nOffscreen drawing, textures, blending and compute, with pixel/data comparisons. Synthetic fixtures only.\n\nRequires the guest virtual-address layout and 64 MiB of committed fixture memory. Keep this app in the foreground.\n\nTap Run renderer. No game file required.";
    [self.view addSubview:self.text];
    self.runButton=[[UIBarButtonItem alloc] initWithTitle:@"Run renderer" style:UIBarButtonItemStylePlain target:self action:@selector(run)];
    self.navigationItem.rightBarButtonItem=self.runButton;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
}
- (void)run {
    self.runButton.enabled=NO;self.text.text=[self.text.text stringByAppendingString:@"\n\nRUNNING…\n"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSString *root=[NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"renderer-test/modules"];
        NSError *error=nil;
        BOOL created=[[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&error];
        char report[32768]={0};int result=created?ws_renderer_test(root.fileSystemRepresentation,report,sizeof report):1;
        NSString *message=created?[NSString stringWithFormat:@"%s\nStatus: %@\n",report,result==77?@"BLOCKED":result?@"FAIL":@"PASS"]:[NSString stringWithFormat:@"Directory creation failed: %@",error];
        dispatch_async(dispatch_get_main_queue(),^{self.text.text=[self.text.text stringByAppendingString:message];});
    });
}
- (void)share {
    UIActivityViewController *sheet=[[UIActivityViewController alloc] initWithActivityItems:@[self.text.text] applicationActivities:nil];
    sheet.popoverPresentationController.barButtonItem=self.navigationItem.leftBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}
@end
@interface RendererDelegate:UIResponder<UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation RendererDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:[RendererController new]];
    [self.window makeKeyAndVisible];return YES;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(RendererDelegate.class));}}
