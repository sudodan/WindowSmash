#import "window.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <pthread.h>
#include <stdatomic.h>
#include <time.h>

static UIView *surface;
static CAMetalLayer *metalLayer;
static atomic_int active;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static uint64_t frames;

@interface WSRuntimeSurface : UIView
@property(nonatomic, strong) CADisplayLink *link;
@end
@implementation WSRuntimeSurface
+ (Class)layerClass { return CAMetalLayer.class; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
    self.contentScaleFactor = scale;
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    layer.contentsScale = scale;
    layer.drawableSize = CGSizeMake(self.bounds.size.width * scale, self.bounds.size.height * scale);
}
- (void)tick:(CADisplayLink *)sender {
    (void)sender;
    if (!atomic_load(&active)) return;
    pthread_mutex_lock(&lock);
    ++frames;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
}
@end
UIView *ws_ios_create_surface(void) {
    NSCAssert(NSThread.isMainThread, @"UIKit surface must be created on main thread");
    if (surface) return surface;
    WSRuntimeSurface *view = [WSRuntimeSurface new];
    surface = view;
    metalLayer = (CAMetalLayer *)view.layer;
    metalLayer.device = MTLCreateSystemDefaultDevice();
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    metalLayer.framebufferOnly = YES;
    metalLayer.allowsNextDrawableTimeout = YES;
    view.link = [CADisplayLink displayLinkWithTarget:view selector:@selector(tick:)];
    [view.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    return surface;
}
void ws_ios_set_active(int value) {
    atomic_store(&active, value);
    pthread_mutex_lock(&lock);
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
}
void *rt_window(void) { return (__bridge void *)surface; }
void *rt_metal_layer(void) { return (__bridge void *)metalLayer; }
void *GetForegroundWindow(void) { return atomic_load(&active) ? rt_window() : NULL; }
short GetAsyncKeyState(int key) { (void)key; return 0; } /* Hardware keyboard mapping pending. */
int rt_window_init(void) { return surface && metalLayer.device; }
int rt_window_wait_vblank(int n, int timeout_ms) {
    /* Never block UIKit; gpu_display.c falls back to clock pacing on failure. */
    if (NSThread.isMainThread || n <= 0 || timeout_ms <= 0 || !atomic_load(&active)) return 0;
    uint64_t end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + (uint64_t)timeout_ms * 1000000;
    pthread_mutex_lock(&lock);
    uint64_t target = frames + (unsigned)n;
    while (frames < target && atomic_load(&active)) {
        uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        if (now >= end) break;
        struct timespec left = {(time_t)((end-now)/1000000000), (long)((end-now)%1000000000)};
        pthread_cond_timedwait_relative_np(&changed, &lock, &left);
    }
    int ok = frames >= target;
    pthread_mutex_unlock(&lock);
    return ok;
}
/* rt_window_loop is intentionally absent: iOS enters UIApplicationMain, never
 * the desktop loader's process main. Text entry/input and guest suspend remain
 * integration tasks; no silent game-service stub is supplied here. */
