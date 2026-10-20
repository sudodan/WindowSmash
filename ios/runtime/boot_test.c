/* Original synthetic modules executed by the real loader and kernel. */
#include "host.h"
#include "boot_test.h"
#include <stdarg.h>
#include <stdio.h>

#define MAIN 0x7100000000ull
#define SUB  0x7108000000ull
#define SDK  0x7109000000ull
static int checks, failures, init_order;
static char details[4096];
static size_t used;
static void check(int ok, const char *what) {
    ++checks;
    if (!ok) ++failures;
    if (used < sizeof details) {
        int n=snprintf(details+used,sizeof details-used,"%s %s\n",ok?"PASS":"FAIL",what);
        if(n>0) used+=(size_t)n;
    }
}
static void init_main(Cpu *c) { (void)c; init_order=init_order*10+1; }
static void init_sub(Cpu *c) { (void)c; init_order=init_order*10+2; }
static void init_sdk(Cpu *c) { (void)c; init_order=init_order*10+3; }
static void native_test(Cpu *c) { c->x[0]=0xcafe; }
static void guest_thread(Cpu *c) { st32(HEAP_BASE+0x6000,0xbeef); rt_svc(c,0x0a); }
static void guest_start(Cpu *c) {
    rt_call(c,c->x[3]);
    check(init_order==321,"SDK, subsdk0, main initializers in dependency order");
    check(ld64(MAIN+0x8000)==0x1234 && ld64(SUB+0x8000)==0x5678 && ld64(SDK+0x8000)==0x9abc,"three module images mapped");
    check(ld64(MAIN+0x9000)==SDK+0x8008,"cross-module symbol relocation and addend");
    check(ld64(MAIN+0x9010)==0,"missing weak import resolves to zero");
    c->x[0]=0; rt_call(c,ld64(MAIN+0x9008));
    check(c->x[0]==0xcafe,"native import dispatched by real loader");
    c->x[1]=4<<20; rt_svc(c,0x01);
    check(c->x[0]==0 && c->x[1]==HEAP_BASE,"kernel heap allocation");
    if(c->x[0]) return;
    st64(HEAP_BASE+0x1000,42);
    c->x[0]=HEAP_BASE+0x4000; c->x[2]=HEAP_BASE+0x10; rt_svc(c,0x06);
    check(ld64(HEAP_BASE+0x4000)==HEAP_BASE && ld32(HEAP_BASE+0x4010)==5,"kernel memory query");
    u64 dst=STACK_BASE+0x100000;
    c->x[0]=dst;c->x[1]=HEAP_BASE;c->x[2]=0x10000;rt_svc(c,0x04);
    check(c->x[0]==0 && ld64(dst+0x1000)==42,"kernel stack mapping copies data");
    if(c->x[0]) return;
    st64(dst+0x1000,77);
    c->x[0]=dst;c->x[1]=HEAP_BASE;c->x[2]=0x10000;rt_svc(c,0x05);
    MEMORY_BASIC_INFORMATION mi;
    check(c->x[0]==0 && ld64(HEAP_BASE+0x1000)==77 && VirtualQuery(G2H(dst),&mi,sizeof mi) && mi.State==MEM_RESERVE,"unmap copies back and decommits");
    u64 alias=ALIAS_BASE+0x100000;
    c->x[0]=alias;c->x[1]=0x8000;rt_svc(c,0x2c);
    check(c->x[0]==0,"watched alias memory committed");
    if(c->x[0]) return;
    /* Actual protection fault handled by host.c; not rt_ww_prepare_write. */
    st32(alias+0x1000,0xdead);
    void *pages[16]; ULONG_PTR count=16; ULONG gran=0;
    int error=GetWriteWatch(WRITE_WATCH_FLAG_RESET,G2H(alias),0x8000,pages,&count,&gran);
    check(!error && count==4 && gran==4096 && pages[0]==G2H(alias),"write fault records four guest subpages");
    st32(alias+0x2000,0xbead);
    count=16;error=GetWriteWatch(WRITE_WATCH_FLAG_RESET,G2H(alias),0x8000,pages,&count,&gran);
    check(!error && count==4 && pages[0]==G2H(alias),"reset rearms fault-based write tracking");
    /* Partial decommit while watched/read-only exercises vm_remap alias path. */
    check(VirtualFree(G2H(alias+0x1000),0x1000,MEM_DECOMMIT),"watched subpage decommit");
    void *again=VirtualAlloc(G2H(alias+0x1000),0x1000,MEM_COMMIT,PAGE_READWRITE);
    check(again==G2H(alias+0x1000),"watched subpage recommit");
    if(again) check(ld32(alias+0x1000)==0 && ld32(alias+0x2000)==0xbead,"decommit zeroes subpage and preserves neighbor");
    c->x[0]=alias;c->x[1]=0x8000;rt_svc(c,0x2d);
    check(VirtualQuery(G2H(alias),&mi,sizeof mi) && mi.State==MEM_RESERVE,"alias physical memory unmapped");
    c->x[1]=MAIN+0x200;c->x[2]=0;c->x[3]=STACK_BASE+0x1000;c->x[4]=44;c->x[5]=0;rt_svc(c,0x08);
    check(c->x[0]==0,"kernel guest thread created");
    if(c->x[0]) return;
    u32 thread=(u32)c->x[1]; c->x[0]=thread;rt_svc(c,0x09);
    check(c->x[0]==0,"kernel guest thread started");
    st32(HEAP_BASE+0x5000,thread);
    c->x[1]=HEAP_BASE+0x5000;c->x[2]=1;c->x[3]=5000000000ull;rt_svc(c,0x18);
    check(c->x[0]==0 && ld32(HEAP_BASE+0x6000)==0xbeef,"guest thread ran, exited and joined through kernel SVCs");
    /* Return, so UIKit survives. svcExitProcess is not an app lifecycle API. */
}
static const RtFunc main_funcs[]={{MAIN+0x100,init_main},{MAIN+0x200,guest_thread}};
static const char *const imports[]={"sdk_value","synthetic_native","missing_weak"};
static const u8 weak[]={0,0,1};
static const RtReloc relocs[]={{0x9000,8,0},{0x9008,0,1},{0x9010,0,2}};
const RtModule rt_module_main={"main",MAIN,0x10000,0x8000,MAIN+0x100,main_funcs,2,NULL,0,imports,weak,3,relocs,3,""};
static const RtFunc sub_funcs[]={{SUB+0x100,init_sub}};
const RtModule rt_module_subsdk0={"subsdk0",SUB,0x10000,0x8000,SUB+0x100,sub_funcs,1,NULL,0,NULL,NULL,0,NULL,0,""};
static const RtFunc sdk_funcs[]={{SDK+0x100,init_sdk},{SDK+0x200,guest_start}};
static const RtSym exports[]={{"_ZN2nn4init5StartEmmPFvvES2_",SDK+0x200},{"sdk_value",SDK+0x8000}};
const RtModule rt_module_sdk={"sdk",SDK,0x10000,0x8000,SDK+0x100,sdk_funcs,2,exports,2,NULL,NULL,0,NULL,0,""};
const RtModule *const rt_nro_modules[]={NULL};
const u32 rt_nro_count=0;
const HleEntry hle_table[]={{"synthetic_native",native_test}};
const u32 hle_count=1;
static int boot_result;
static DWORD boot_worker(void *dir) { boot_result=rt_embedded_boot(dir);return 0; }
int ws_boot_test(const char *images,char *report,size_t capacity) {
    /* Process-global loader state is intentionally one-shot, with no teardown. */
    static int attempted;
    if(__atomic_exchange_n(&attempted,1,__ATOMIC_ACQ_REL)) {
        snprintf(report,capacity,"Synthetic boot already attempted; restart the app.\n");return 1;
    }
    HANDLE worker=CreateThread(NULL,16<<20,boot_worker,(void *)images,0,NULL);
    if(!worker) {snprintf(report,capacity,"Could not create boot worker.\n");return 1;}
    WaitForSingleObject(worker,INFINITE);CloseHandle(worker);
    if(boot_result) {
        snprintf(report,capacity,"Synthetic boot BLOCKED (startup code %d). No guest success claimed.\nCode 1: 512 GiB relocated guest window unavailable.\n",boot_result);return 1;
    }
    snprintf(report,capacity,"Synthetic boot: %d/%d checks passed.\n%s\nNo game code, GPU rendering or IPC services tested.\n",checks-failures,checks,details);
    return failures || checks!=19;
}
#ifdef WS_BOOT_CLI
int main(int argc,char **argv) {
    if(argc!=2) return 2;
    char report[8192];int result=ws_boot_test(argv[1],report,sizeof report);fputs(report,stdout);return result;
}
#endif
