/* Reuse upstream's synthetic Maxwell instruction corpus and GPU comparisons.
 * Capture only this translation unit's diagnostics, never process-wide stdout.
 * This tests the real translator and Metal, not gpu_metal.m's renderer. */
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include "shader_test.h"
static char *report_out;
static size_t report_size, report_used;
static int report_truncated;
static int shader_log(const char *format, ...) {
    va_list args;
    va_start(args, format);
    size_t remaining = report_used < report_size ? report_size - report_used : 0;
    int n = vsnprintf(remaining ? report_out + report_used : NULL, remaining, format, args);
    va_end(args);
    if (n > 0) {
        if ((size_t)n >= remaining) {
            report_truncated = 1;
            report_used = report_size ? report_size - 1 : 0;
        } else report_used += (size_t)n;
    }
    return n;
}
#define printf shader_log
#define main ws_upstream_msl_cli_unused
#include "../../tools/mac/msltest.m"
#undef main
#undef printf

int ws_shader_test(char *report, size_t capacity) {
    static int attempted;
    if (!report || !capacity) return 1;
    report[0] = 0;
    if (__atomic_exchange_n(&attempted, 1, __ATOMIC_SEQ_CST)) {
        snprintf(report, capacity, "Shader test already attempted; restart the app to retry.\n");
        return 1;
    }
    report_out = report; report_size = capacity; report_used = 0; report_truncated = 0;
    int result;
    @autoreleasepool {
        dev = MTLCreateSystemDefaultDevice();
        queue = [dev newCommandQueue];
        if (!dev || !queue) {
            shader_log("BLOCKED: no usable Metal device/command queue.\n");
            result = 77;
        } else {
            shader_log("Real shader translator + Metal GPU comparisons\nSynthetic instructions only; no game data.\n");
            build_corpus();
            result = run_gpu();
            if (!checks) { shader_log("FAIL: no GPU comparisons executed.\n"); result = 1; }
        }
        queue = nil; dev = nil;
    }
    if (report_truncated && capacity > 32)
        snprintf(report + capacity - 32, 32, "\n[diagnostic text truncated]\n");
    report_out = NULL; report_size = report_used = 0;
    return result;
}
#ifdef WS_SHADER_CLI
int main(void) {
    char report[32768];
    int result = ws_shader_test(report, sizeof report);
    fputs(report, stdout);
    return result;
}
#endif
