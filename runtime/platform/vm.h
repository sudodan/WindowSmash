/* Host-page memory ownership for the Apple port. Not a guest memory manager. */
#pragma once
#include <stddef.h>
#include <stdint.h>

typedef struct WsVmRegion { void *base; size_t size; } WsVmRegion;
enum { WS_VM_NONE = 0, WS_VM_READ = 1, WS_VM_WRITE = 2 };
size_t ws_vm_page_size(void);
/* All results are errno values (0 = success). Zero-initialize region before use.
 * address=0 permits any address; otherwise require an exact, non-overwriting map.
 * Never copy a live region. Caller serializes operations and all accesses.
 * Offsets/sizes MUST be host-page aligned. No executable memory is supported. */
int ws_vm_reserve(WsVmRegion *region, uintptr_t address, size_t size);
int ws_vm_protect(WsVmRegion *region, size_t offset, size_t size, unsigned permission);
/* Discard owned pages and replace with inaccessible zero-backed pages. Re-enable
 * with protect. This is destructive; never call while another thread uses them. */
int ws_vm_decommit(WsVmRegion *region, size_t offset, size_t size);
int ws_vm_release(WsVmRegion *region);
