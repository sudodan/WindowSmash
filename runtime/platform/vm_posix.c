/* Used by iOS/macOS; also testable on Linux. No Windows emulation or CPU JIT. */
#define _DEFAULT_SOURCE
#include "vm.h"
#include <errno.h>
#include <sys/mman.h>
#include <unistd.h>

size_t ws_vm_page_size(void) {
    long size = sysconf(_SC_PAGESIZE);
    return size > 0 ? (size_t)size : 0;
}
static int aligned(size_t n) {
    size_t page = ws_vm_page_size();
    return page && n % page == 0;
}
static int range(WsVmRegion *r, size_t offset, size_t size) {
    return r && r->base && size && aligned(offset) && aligned(size) &&
        offset <= r->size && size <= r->size - offset;
}
int ws_vm_reserve(WsVmRegion *r, uintptr_t address, size_t size) {
    if (!r || r->base || r->size || !size || !aligned(size) ||
        !aligned(address) || size > UINTPTR_MAX - address) return EINVAL;
    /* A hint can never overwrite another mapping. If the OS chooses a different
     * address, undo it and fail: guest pointers require identity mapping. */
    void *p = mmap((void *)address, size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) return errno;
    if (!p || (address && (uintptr_t)p != address)) {
        munmap(p, size);
        return EADDRNOTAVAIL;
    }
    r->base = p; r->size = size;
    return 0;
}
int ws_vm_protect(WsVmRegion *r, size_t offset, size_t size, unsigned permission) {
    if (!range(r, offset, size) || permission & ~(WS_VM_READ | WS_VM_WRITE)) return EINVAL;
    int prot = (permission & WS_VM_READ ? PROT_READ : 0) |
               (permission & WS_VM_WRITE ? PROT_WRITE : 0);
    return mprotect((char *)r->base + offset, size, prot) == 0 ? 0 : errno;
}
int ws_vm_decommit(WsVmRegion *r, size_t offset, size_t size) {
    if (!range(r, offset, size)) return EINVAL;
    /* MAP_FIXED is allowed ONLY within this live owned reservation. Replacing
     * in one operation avoids an unmap/reallocate race and guarantees fresh
     * zero pages on recommit (madvise alone doesn't give that contract). */
    void *p = mmap((char *)r->base + offset, size, PROT_NONE,
                  MAP_FIXED | MAP_PRIVATE | MAP_ANON, -1, 0);
    return p == MAP_FAILED ? errno : 0;
}
int ws_vm_release(WsVmRegion *r) {
    if (!r || !r->base || !r->size) return EINVAL;
    if (munmap(r->base, r->size)) return errno;
    r->base = NULL; r->size = 0;
    return 0;
}
