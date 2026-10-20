#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <mach/mach.h>
_Static_assert(sizeof(vm_address_t) == 8, "Probe requires 64-bit VM addresses");
_Static_assert(sizeof(vm_size_t) == 8, "Probe requires 64-bit VM sizes");
#include "cpu_probe.h"

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
    vm_address_t owned[9] = {0};
    vm_size_t sizes[9] = {0};
    for (int i = 0; i < 9; ++i) {
        vm_address_t address = ranges[i].base;
        vm_size_t size = ranges[i].size ?: vm_page_size;
        /* FIXED without OVERWRITE: never replace an existing mapping. */
        kern_return_t kr = vm_allocate(mach_task_self(), &address, size, VM_FLAGS_FIXED);
        if (kr != KERN_SUCCESS) {
            [log appendFormat:@"FAIL %s: %s (%d)\n", ranges[i].name, mach_error_string(kr), kr];
            continue;
        }
        owned[i] = address; sizes[i] = size;
        kr = vm_protect(mach_task_self(), address, size, FALSE, VM_PROT_NONE);
        [log appendFormat:@"%@ %s: 0x%llx, %llu MiB reserved\n",
            kr == KERN_SUCCESS ? @"PASS" : @"FAIL protection", ranges[i].name,
            (unsigned long long)address, (unsigned long long)(size >> 20)];
        if (kr == KERN_SUCCESS) {
            kr = vm_protect(mach_task_self(), address, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE);
            if (kr == KERN_SUCCESS) {
                volatile uint64_t *p = (volatile uint64_t *)(uintptr_t)address;
                *p = 0x123456789abcdef0ull;
                [log appendFormat:@"  first-page write/read: %@\n", *p == 0x123456789abcdef0ull ? @"PASS" : @"FAIL"];
            } else [log appendFormat:@"  first-page protection FAIL: %s\n", mach_error_string(kr)];
        }
    }
    for (int i = 0; i < 9; ++i) if (owned[i]) {
        kern_return_t kr = vm_deallocate(mach_task_self(), owned[i], sizes[i]);
        if (kr != KERN_SUCCESS) [log appendFormat:@"Cleanup FAIL: %s\n", mach_error_string(kr)];
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
        char cpu[1024]; ws_cpu_probe(cpu, sizeof cpu);
        NSMutableString *report = [NSMutableString stringWithFormat:
            @"WindowSmash feasibility probe v1\nUpstream: bbef8862046fd98721924338f1b79f65b65ee698\nOS: %@\nArchitecture: arm64 device required\n\n%s\n%@\n",
            NSProcessInfo.processInfo.operatingSystemVersionString, cpu, memoryProbe()];
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        [report appendFormat:@"Metal device: %@\n", device.name ?: @"UNAVAILABLE"];
        [report appendString:@"NOT TESTED: game execution, translated shaders, GPU output, fibers, guest exceptions, sustained performance.\nA passing probe is NOT a working port.\n"];
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
