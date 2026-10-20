#include "vm_probe.h"
#include "platform/vm.h"
#include <errno.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

int ws_vm_probe(char *report, size_t capacity) {
    int total = 0, failed = 0;
    WsVmRegion r = {0}, collision = {0};
    size_t page = ws_vm_page_size();
#define CHECK(x) do { ++total; if (!(x)) { ++failed; } } while (0)
    CHECK(page >= 4096);
    if (!page) goto done;
    CHECK(ws_vm_reserve(&r, 0, page * 3) == 0);
    if (!r.base) goto done;
    CHECK(ws_vm_reserve(&r, 0, page) == EINVAL);
    CHECK(ws_vm_protect(&r, 0, page * 3, WS_VM_READ | WS_VM_WRITE) == 0);
    if (failed) goto done; /* Do not touch memory unless initial setup passed. */
    unsigned char *p = r.base;
    memset(p, 0x31, page); memset(p + page, 0x72, page); memset(p + 2 * page, 0x53, page);
    CHECK(ws_vm_reserve(&collision, (uintptr_t)r.base, page) != 0);
    CHECK(!collision.base && !collision.size && p[0] == 0x31);
    CHECK(ws_vm_protect(&r, 1, page, WS_VM_READ) == EINVAL);
    CHECK(ws_vm_protect(&r, 0, page - 1, WS_VM_READ) == EINVAL);
    CHECK(ws_vm_protect(&r, page * 3, page, WS_VM_READ) == EINVAL);
    CHECK(ws_vm_decommit(&r, SIZE_MAX - page + 1, page) == EINVAL);
    CHECK(ws_vm_protect(&r, 0, page, 4) == EINVAL); /* No execute permission. */
    CHECK(ws_vm_decommit(&r, page, 0) == EINVAL);
    CHECK(ws_vm_protect(&r, 0, page, WS_VM_READ) == 0);
    CHECK(p[page - 1] == 0x31);
    CHECK(ws_vm_protect(&r, 0, page, WS_VM_READ | WS_VM_WRITE) == 0);
    CHECK(ws_vm_decommit(&r, page, page) == 0);
    int enable = ws_vm_protect(&r, page, page, WS_VM_READ | WS_VM_WRITE);
    CHECK(enable == 0);
    if (!enable) {
        int zero = 1, neighbors = 1;
        for (size_t i = 0; i < page; ++i) {
            if (p[page + i]) zero = 0;
            if (p[i] != 0x31 || p[page * 2 + i] != 0x53) neighbors = 0;
        }
        CHECK(zero); CHECK(neighbors);
        p[page] = 0x9a; CHECK(p[page] == 0x9a);
    }
    CHECK(ws_vm_release(&r) == 0);
    CHECK(!r.base && !r.size);
    CHECK(ws_vm_release(&r) == EINVAL);
    CHECK(ws_vm_protect(&r, 0, page, WS_VM_READ) == EINVAL);
done:
    if (r.base) ws_vm_release(&r);
    if (collision.base) ws_vm_release(&collision);
    snprintf(report, capacity, "Host memory backend: %d/%d checks passed; host page %zu bytes.\n"
             "Guest 4096-byte subpage permissions/aliasing are NOT implemented.\n",
             total - failed, total, page);
    return failed ? 1 : 0;
#undef CHECK
}
#ifdef WS_VM_CLI
int main(void) { char report[512]; int rc = ws_vm_probe(report, sizeof report); fputs(report, stdout); return rc; }
#endif
