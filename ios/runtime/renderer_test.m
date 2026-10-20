/* Offscreen subset of the upstream renderer suite, in a separate process/app.
 * The actual renderer, translator, textures and memory backend are linked.
 * Peripheral test doubles come from gfxtest; overlay is deliberately excluded. */
#include <stdio.h>
#include <stdarg.h>
#include "renderer_test.h"
static char *report_out;
static size_t report_cap, report_used;
static int capture_vprintf(const char *fmt, va_list ap) {
#ifdef WS_RENDERER_CLI
    va_list copy;va_copy(copy,ap);vfprintf(stderr,fmt,copy);va_end(copy);fflush(stderr);
#endif
    size_t left=report_used<report_cap?report_cap-report_used:0;
    int n=vsnprintf(left?report_out+report_used:NULL,left,fmt,ap);
    if(n>0) report_used+=(size_t)n<left?(size_t)n:left?left-1:0;
    return n;
}
static int capture_printf(const char *fmt, ...) {
    va_list ap;va_start(ap,fmt);int n=capture_vprintf(fmt,ap);va_end(ap);return n;
}
#define printf capture_printf
#define vprintf capture_vprintf
#define main ws_unused_gfxtest_cli
#include "../../tools/mac/gfxtest.m"
#undef main
#undef printf
#undef vprintf
void overlay_present_metal(id<MTLDevice> d,id<MTLRenderCommandEncoder> e,MTLPixelFormat f,unsigned x,unsigned y,unsigned w,unsigned h,int show,const char *detail) {
    (void)d;(void)e;(void)f;(void)x;(void)y;(void)w;(void)h;(void)show;(void)detail;
}
static DWORD renderer_work(void *directory) {
    @autoreleasepool {
        if(!MTLCreateSystemDefaultDevice()) { capture_printf("BLOCKED: no Metal device.\n");return 77; }
        if(!rt_guest_window()) { capture_printf("BLOCKED: guest address reservation failed.\n");return 77; }
        struct sigaction sa={0};sa.sa_sigaction=on_fault;sa.sa_flags=SA_SIGINFO;
        sigaction(SIGBUS,&sa,NULL);sigaction(SIGSEGV,&sa,NULL);
        if(!VirtualAlloc(G2H(ALIAS_BASE),ALIAS_SIZE,MEM_RESERVE|MEM_WRITE_WATCH,PAGE_READWRITE)||
           !VirtualAlloc(G2H(ALIAS_BASE),GSIZE,MEM_COMMIT,PAGE_READWRITE)) {
            capture_printf("BLOCKED: watched guest memory allocation failed.\n");return 77;
        }
        /* Absolute app-owned path; no process-wide working-directory changes. */
        rt_data_dir=directory;
        test_layer=[CAMetalLayer layer];test_layer.pixelFormat=MTLPixelFormatBGRA8Unorm;
        test_layer.framebufferOnly=NO;test_layer.drawableSize=CGSizeMake(640,360);
        Prog p;
        vs_pass(&p);place(VS_PASS,&p,0);vs_cbuf(&p);place(VS_CBUF,&p,0);
        ps_color(&p);place(PS_COLOR,&p,0);ps_texture(&p);place(PS_TEXTURE,&p,0);
        cs_copy(&p);place(CS_COPY_PROG,&p,1);ps_dual(&p);place(PS_DUAL,&p,0);
        capture_printf("Actual Metal renderer: offscreen synthetic workloads\n64 MiB committed guest fixture.\n");
        test_clears();test_triangles();test_textures();test_targets_as_textures();
        test_kept_constants();test_state();test_dual_source();test_blit();test_compute();
        capture_printf("Renderer: %d checks, %d failed; %llu draws, %llu GPU errors, %llu shader failures\n",
            checks,failures,gfx_stat_drawn,gfx_stat_gpu_errors,gfx_stat_shader_failures);
        return failures||!checks||gfx_stat_gpu_errors||gfx_stat_shader_failures?1:0;
    }
}
static DWORD worker_result;
static DWORD renderer_worker(void *directory) { return worker_result=renderer_work(directory); }
int ws_renderer_test(const char *directory,char *report,size_t capacity) {
    static int attempted;
    if(!directory||!report||!capacity)return 1;
    report[0]=0;
    if(__atomic_exchange_n(&attempted,1,__ATOMIC_SEQ_CST)) {
        snprintf(report,capacity,"Restart the app before retrying renderer tests.\n");return 1;
    }
    report_out=report;report_cap=capacity;report_used=0;
    /* Renderer cache workers may retain this path for the lifetime of the process. */
    char *path=strdup(directory);
    HANDLE worker=path?CreateThread(NULL,16<<20,renderer_worker,path,0,NULL):NULL;
    if(!worker){capture_printf("FAIL: worker allocation.\n");return 1;}
    WaitForSingleObject(worker,INFINITE);CloseHandle(worker);
    return (int)worker_result;
}
#ifdef WS_RENDERER_CLI
int main(int argc,char **argv) {
    if(argc!=2)return 2;
    char report[32768];int result=ws_renderer_test(argv[1],report,sizeof report);
    fputs(report,stdout);return result;
}
#endif
