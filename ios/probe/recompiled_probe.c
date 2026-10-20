#include "recompiled_probe.h"
#include "recomp.h"
#include <stdio.h>
#include <stdlib.h>

void ws_fixture_add(Cpu *);
void ws_fixture_mul(Cpu *);
void ws_fixture_sum(Cpu *);
void ws_fixture_memory(Cpu *);
void ws_fixture_fpadd(Cpu *);
void ws_fixture_vector(Cpu *);
#ifdef WS_NATIVE_REFERENCE
#if !defined(__aarch64__)
#error Native reference fixtures require Apple ARM64
#endif
typedef u32 NativeVector __attribute__((vector_size(16)));
extern u64 ws_native_add(u64, u64), ws_native_mul(u64, u64), ws_native_sum(u64);
extern u64 ws_native_memory(u64 *);
extern double ws_native_fpadd(double, double);
extern NativeVector ws_native_vector(NativeVector, NativeVector);
#endif

_Noreturn void rt_trap(Cpu *c, u64 pc, const char *why) {
    (void)c;
    fprintf(stderr, "Synthetic fixture trap at %llx: %s\n", (unsigned long long)pc, why);
    abort();
}
static u64 next(u64 *seed) {
    *seed ^= *seed << 13; *seed ^= *seed >> 7; *seed ^= *seed << 17;
    return *seed;
}
int ws_recompiled_probe(char *report, unsigned long capacity) {
    unsigned checks = 0, failures = 0;
    u64 seed = 0x5eed1234;
#define VERIFY(x) do { checks++; if (!(x)) failures++; } while (0)
    for (int i = 0; i < 1024; ++i) {
        u64 a = next(&seed), b = next(&seed);
        Cpu cpu = {0};
        cpu.x[0] = a; cpu.x[1] = b; ws_fixture_add(&cpu);
        VERIFY(cpu.x[0] == a + b);
#ifdef WS_NATIVE_REFERENCE
        VERIFY(cpu.x[0] == ws_native_add(a, b));
#endif
        cpu.x[0] = a; cpu.x[1] = b; ws_fixture_mul(&cpu);
        VERIFY(cpu.x[0] == a * b);
#ifdef WS_NATIVE_REFERENCE
        VERIFY(cpu.x[0] == ws_native_mul(a, b));
#endif
        u64 n = i % 128;
        cpu.x[0] = n; ws_fixture_sum(&cpu);
        VERIFY(cpu.x[0] == n * (n + 1) / 2);
#ifdef WS_NATIVE_REFERENCE
        VERIFY(cpu.x[0] == ws_native_sum(n));
#endif
        u64 value = a;
        cpu.x[0] = (u64)(uintptr_t)&value; ws_fixture_memory(&cpu);
        VERIFY(value == a + 7 && cpu.x[0] == value);
#ifdef WS_NATIVE_REFERENCE
        u64 native_value = a;
        VERIFY(ws_native_memory(&native_value) == cpu.x[0] && native_value == value);
#endif
        double fa = (double)(i - 512) / 8.0, fb = (double)(i % 17) / 4.0;
        cpu.v[0].g[0] = fa; cpu.v[1].g[0] = fb; ws_fixture_fpadd(&cpu);
        VERIFY(cpu.v[0].g[0] == fa + fb);
#ifdef WS_NATIVE_REFERENCE
        VERIFY(cpu.v[0].g[0] == ws_native_fpadd(fa, fb));
#endif
        u32 va[4], vb[4];
        for (int j = 0; j < 4; ++j) {
            va[j] = (u32)next(&seed); vb[j] = (u32)next(&seed);
            cpu.v[0].s[j] = va[j]; cpu.v[1].s[j] = vb[j];
        }
        ws_fixture_vector(&cpu);
        for (int j = 0; j < 4; ++j) VERIFY(cpu.v[0].s[j] == va[j] + vb[j]);
#ifdef WS_NATIVE_REFERENCE
        NativeVector na, nb; memcpy(&na, va, 16); memcpy(&nb, vb, 16);
        NativeVector nr = ws_native_vector(na, nb);
        VERIFY(memcmp(&nr, &cpu.v[0], 16) == 0);
#endif
    }
    snprintf(report, capacity,
        "Recompiled synthetic code: %u/%u checks passed\n"
        "6 functions: integer add/multiply, branch loop, memory, floating point, SIMD\n"
#ifdef WS_NATIVE_REFERENCE
        "Includes comparison against the same instruction words executing natively on ARM64.\n"
#else
        "C semantic reference only; native ARM64 comparison not enabled on this host.\n"
#endif
        "No game code, guest OS, fibers, or exception unwinding tested.\n", checks - failures, checks);
    return (int)failures;
}
#ifdef WS_RECOMPILED_CLI
int main(void) { char report[1024]; int failed = ws_recompiled_probe(report, sizeof report); puts(report); return failed ? 1 : 0; }
#endif
