#include "cpu_probe.h"
#include "recomp.h"
#include <stdio.h>
#include <pthread.h>
#include <stddef.h>

static u64 counter;
static void *increment(void *unused) {
    (void)unused;
    for (int i = 0; i < 10000; ++i) {
        u64 old;
        do { old = __atomic_load_n(&counter, __ATOMIC_SEQ_CST); }
        while (!cas64((u64)(uintptr_t)&counter, old, old + 1));
    }
    return NULL;
}
int ws_cpu_probe(char *report, unsigned long capacity) {
    int failures = 0, checks = 0;
#define CHECK(x) do { checks++; if (!(x)) failures++; } while (0)
    Cpu cpu = {0};
    CHECK(sizeof(V128) == 16);
    CHECK(offsetof(Cpu, v) % 16 == 0);
    unsigned char bytes[32] = {0};
    u64 address = (u64)(uintptr_t)(bytes + 1);
    st64(address, 0x0123456789abcdefull);
    CHECK(ld64(address) == 0x0123456789abcdefull);
    CHECK(udiv64(123, 0) == 0);
    CHECK(sdiv64(0x8000000000000000ull, ~0ull) == 0x8000000000000000ull);
    CHECK(umulh64(~0ull, ~0ull) == ~1ull);
    CHECK(ror64(1, 1) == 0x8000000000000000ull);
    CHECK(rt_h2f(0x3c00) == 1.0f);
    CHECK(rt_d2h(1.0) == 0x3c00);
    CHECK(signbit(fminS(0.0f, -0.0f)));
    CHECK(!signbit(fmaxS(0.0f, -0.0f)));
    CHECK(isnan(fmaxS(NAN, 1.0f)));
    cpu.v[0].d[0] = cpu.v[0].d[1] = ~0ull;
    wS(&cpu, 0, 1.0f);
    CHECK(cpu.v[0].d[0] == 0x3f800000 && cpu.v[0].d[1] == 0);
    counter = 0;
    pthread_t workers[2];
    int started[2];
    for (int i = 0; i < 2; ++i) {
        started[i] = pthread_create(&workers[i], NULL, increment, NULL) == 0;
        CHECK(started[i]);
    }
    for (int i = 0; i < 2; ++i) if (started[i]) CHECK(pthread_join(workers[i], NULL) == 0);
    CHECK(counter == 20000);
    snprintf(report, capacity,
        "CPU helper checks: %d/%d passed\nConcurrent CAS increments: %llu/20000\n"
        "Tests upstream recomp.h helpers only. No game code, fibers, exception unwinding, or renderer tested.\n",
        checks - failures, checks, (unsigned long long)counter);
    return failures;
}
#ifdef WS_PROBE_CLI
int main(void) { char report[1024]; int result = ws_cpu_probe(report, sizeof report); puts(report); return result ? 1 : 0; }
#endif
