#include "recomp.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
/* Test-harness diagnostics only; the real loader supplies these in a game build. */
#ifndef WS_EMBEDDED_HOST
extern "C" void rt_fatal(const char *fmt, ...) {
    va_list args; va_start(args,fmt); vfprintf(stderr,fmt,args); va_end(args); abort();
}
extern "C" const char *rt_describe(u64 addr, char *buf, size_t n) {
    snprintf(buf,n,"synthetic:%llx",(unsigned long long)addr); return buf;
}
#endif
extern "C" void rt_eh_raise(u64 lp, u64 sp);
extern "C" int ws_exception_test(void) {
    try { rt_eh_raise(0x7100001234ull,0x7700001000ull); }
    catch (const RtEhSignal &e) { return e.lp==0x7100001234ull && e.sp==0x7700001000ull; }
    return 0;
}
