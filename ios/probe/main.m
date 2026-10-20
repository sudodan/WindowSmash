#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#include <string.h>
#include "platform/vm.h"
#include "vm_probe.h"
#include "cpu_probe.h"
#include "recompiled_probe.h"
#import "metal_probe.h"

static NSString *memoryProbe(void) {
    /* Snapshot of host.h/recomp.py at bbef886. Module/shared sizes below are
       one-page samples, not the unknown sizes of the user's game modules. */
    const struct { const char *name; uint64_t base, size; } ranges[] = {
        {"alias", 0x6000000000, 0x1000000000},
        {"heap", 0x7400000000, 0x200000000},
        {"stack", 0x7700000000, 0x80000000},
        {"thread-local", 0x7780000000, 0x1000000},
        {"native", 0x7300000000, 0x100000},
        {"main sample", 0x7100000000, 0},
        {"subsdk sample", 0x7108000000, 0},
        {"sdk sample", 0x7109000000, 0},
        {"shared sample", 0x7800000000, 0}
    };
    NSMutableString *log = [NSMutableString stringWithString:@"Memory reservations (held simultaneously):\n"];
    WsVmRegion owned[9] = {0};
    for (int i = 0; i < 9; ++i) {
        size_t size = ranges[i].size ?: ws_vm_page_size();
        int error = ws_vm_reserve(&owned[i], ranges[i].base, size);
        if (error) {
            [log appendFormat:@"FAIL %s: %s (%d)\n", ranges[i].name, strerror(error), error];
            continue;
        }
        [log appendFormat:@"PASS %s: 0x%llx, %llu MiB reserved inaccessible\n",
            ranges[i].name, (unsigned long long)(uintptr_t)owned[i].base,
            (unsigned long long)(size >> 20)];
        error = ws_vm_protect(&owned[i], 0, ws_vm_page_size(), WS_VM_READ | WS_VM_WRITE);
        if (!error) {
            volatile uint64_t *p = owned[i].base;
            *p = 0x123456789abcdef0ull;
            [log appendFormat:@"  first-page write/read: %@\n", *p == 0x123456789abcdef0ull ? @"PASS" : @"FAIL"];
        } else [log appendFormat:@"  first-page protection FAIL: %s\n", strerror(error)];
    }
    for (int i = 0; i < 9; ++i) if (owned[i].base) {
        int error = ws_vm_release(&owned[i]);
        if (error) [log appendFormat:@"Cleanup FAIL: %s\n", strerror(error)];
    }
    [log appendString:@"Reservations are virtual, not RAM commitments. This does not measure game memory usage.\n"];
    return log;
}
@interface ProbeController : UIViewController
@property(nonatomic, strong) UITextView *text;
@end
@implementation ProbeController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WindowSmash feasibility";
    self.text = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.text.editable = NO;
    self.text.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.text.text = @"Running tests…";
    [self.view addSubview:self.text];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        char cpu[1024], recompiled[1024], vm[512];
        ws_vm_probe(vm, sizeof vm);
        ws_cpu_probe(cpu, sizeof cpu);
        ws_recompiled_probe(recompiled, sizeof recompiled);
        NSMutableString *report = [NSMutableString stringWithFormat:
            @"WindowSmash feasibility probe v3\nUpstream: bbef8862046fd98721924338f1b79f65b65ee698\nOS: %@\nArchitecture: arm64 device required\n\n%s\n%s\n%s\n%@\n",
            NSProcessInfo.processInfo.operatingSystemVersionString, cpu, recompiled, vm, memoryProbe()];
        NSString *metal = nil;
        ws_metal_probe(&metal);
        [report appendString:metal];
        [report appendString:@"NOT TESTED: game execution, translated game shaders, game rendering, fibers, guest exceptions, sustained performance.\nA passing probe is NOT a working port.\n"];
        dispatch_async(dispatch_get_main_queue(), ^{ self.text.text = report; });
    });
}
- (void)share {
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[self.text.text] applicationActivities:nil];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}
@end
@interface ProbeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation ProbeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[ProbeController new]];
    [self.window makeKeyAndVisible]; return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeDelegate.class)); }
}
