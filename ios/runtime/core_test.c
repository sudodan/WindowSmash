/* Synthetic guest operations linked to the actual upstream platform runtime.
 * No original game data; no fake implementations of memory, threads or fibers. */
#include <windows.h>
#include "recomp.h"
#include "core_test.h"
#include <stdio.h>

static void *root_fiber;
static int visits;
static void fiber_body(void *arg) {
    volatile u64 local = 0x123456789abcdef0ull;
    for (;;) {
        if (local != 0x123456789abcdef0ull || arg != &visits) abort();
        ++visits;
        SwitchToFiber(root_fiber);
    }
}
static DWORD signal_event(void *arg) { SetEvent(arg); return 73; }
static void synthetic_guest(Cpu *c) {
    st64(c->x[0], ld64(c->x[0]) + c->x[1]);
    c->x[0] = ld64(c->x[0]);
}
int ws_exception_test(void);
int ws_runtime_test(char *report, size_t capacity) {
    int checks = 0, failures = 0;
    size_t used = 0;
#define CHECK(condition) do { ++checks; if (!(condition)) { ++failures; \
    if (used < capacity) { int written = snprintf(report + used, capacity-used, "FAIL line %d: %s\n", __LINE__, #condition); \
    if (written > 0) used += (size_t)written; } } } while (0)
    unsigned char *p = VirtualAlloc(NULL, 0x8000, MEM_RESERVE, PAGE_NOACCESS);
    CHECK(p != NULL);
    if (p) {
        void *committed = VirtualAlloc(p, 0x4000, MEM_COMMIT, PAGE_READWRITE);
        CHECK(committed == p);
        if (committed) {
            memset(p, 0x11, 0x1000); memset(p+0x1000, 0x22, 0x1000);
            memset(p+0x2000, 0x33, 0x2000);
            CHECK(VirtualFree(p+0x1000, 0x1000, MEM_DECOMMIT));
            CHECK(VirtualAlloc(p+0x1000, 0x1000, MEM_COMMIT, PAGE_READWRITE) == p+0x1000);
            int zero = 1, neighbors = 1;
            for (size_t i=0; i<0x1000; ++i) {
                if (p[0x1000+i]) zero=0;
                if (p[i]!=0x11 || p[0x2000+i]!=0x33 || p[0x3000+i]!=0x33) neighbors=0;
            }
            CHECK(zero); CHECK(neighbors);
            /* H2G modular subtraction tests the same address helpers without
             * requiring the large fixed guest window. This isn't guest boot. */
            Cpu c = {0}; c.x[0] = (u64)(uintptr_t)p - RT_MEMBASE; c.x[1]=7;
            st64(c.x[0], 35); synthetic_guest(&c); CHECK(c.x[0] == 42);
            CHECK(VirtualFree(p, 0x4000, MEM_DECOMMIT));
            CHECK(VirtualAlloc(p, 0x4000, MEM_COMMIT, PAGE_READWRITE) == p);
            int allzero=1; for(size_t i=0;i<0x4000;++i) if(p[i]) allzero=0;
            CHECK(allzero);
        }
        CHECK(VirtualFree(p, 0, MEM_RELEASE));
    }
    root_fiber = ConvertThreadToFiberEx(NULL, FIBER_FLAG_FLOAT_SWITCH);
    CHECK(root_fiber != NULL);
    if (root_fiber) {
        visits=0;
        void *fiber=CreateFiberEx(0x10000, 0x100000, FIBER_FLAG_FLOAT_SWITCH, fiber_body, &visits);
        CHECK(fiber != NULL);
        if (fiber) {
            for (int i=0;i<1000;++i) SwitchToFiber(fiber);
            CHECK(visits==1000); DeleteFiber(fiber);
        }
    }
    HANDLE event=CreateEventW(NULL, TRUE, FALSE, NULL);
    CHECK(event != NULL);
    if (event) {
        CHECK(WaitForSingleObject(event, 2) == WAIT_TIMEOUT);
        HANDLE thread=CreateThread(NULL, 0, signal_event, event, 0, NULL);
        CHECK(thread != NULL);
        if (thread) {
            CHECK(WaitForSingleObject(event, 2000) == WAIT_OBJECT_0);
            CHECK(WaitForSingleObject(thread, INFINITE) == WAIT_OBJECT_0);
            CloseHandle(thread);
        }
        CloseHandle(event);
    }
    CHECK(ws_exception_test());
    if (used < capacity) snprintf(report+used, capacity-used,
        "Runtime core: %d/%d checks passed.\nSynthetic guest arithmetic, 4 KB subpages, 1000 fiber switches, event/thread waits, C++ exception bridge.\n"
        "NOT full guest boot; renderer/loader/kernel are not linked into this test.\n", checks-failures, checks);
    return failures ? 1 : 0;
#undef CHECK
}
#ifdef WS_RUNTIME_CLI
int main(void) { char report[4096]={0}; int result=ws_runtime_test(report,sizeof report); fputs(report,stdout); return result; }
#endif
