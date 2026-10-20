/* Explicit test doubles for peripherals NOT covered by synthetic boot.
 * No GPU/network/application service is reported as implemented by this test.
 * Unexpected service use fails loudly rather than returning a success stub. */
#include "host.h"
void gpu_memory_unmapping(u64 addr, u64 size) { (void)addr; (void)size; } /* No GPU resources exist. */
void gfx_report_compiles(void (*line)(const char *)) { line("synthetic boot: renderer not linked\n"); }
void rt_upnp_remove(void) {} /* No network mapping was created. */
void *ipc_connect(const char *port) { rt_fatal("synthetic boot unexpectedly requested IPC: %s", port); }
u32 ipc_request(Cpu *c, void *session, u64 message, u64 size) {
    (void)c; (void)session; (void)message; (void)size;
    rt_fatal("synthetic boot unexpectedly requested IPC");
}
void ipc_close(void *session) { (void)session; rt_fatal("synthetic boot unexpectedly closed IPC"); }
