#pragma once
#import <UIKit/UIKit.h>
/* UIKit owns the main loop. Attach exactly once, on the main thread, before
 * starting guest threads. The attached view is retained for app lifetime. */
UIView *ws_ios_create_surface(void);
void ws_ios_set_active(int active);
