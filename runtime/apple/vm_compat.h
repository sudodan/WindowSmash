/* Darwin VM interfaces with SDK-supported entry points on 64-bit iOS.
 * Keep Mac calls unchanged. Never use VM_FLAGS_OVERWRITE for reservations. */
#pragma once
#include <TargetConditionals.h>
#include <mach/mach.h>
#if TARGET_OS_IPHONE
#if !__LP64__
#error This runtime requires a 64-bit iOS target
#endif
typedef vm_address_t rt_vm_address_t;
typedef vm_size_t rt_vm_size_t;
_Static_assert(sizeof(rt_vm_address_t) == 8, "64-bit iOS VM addresses required");
_Static_assert(sizeof(rt_vm_size_t) == 8, "64-bit iOS VM sizes required");
#define rt_vm_map vm_map
#define rt_vm_region vm_region_64
#define rt_vm_remap vm_remap
#define rt_vm_protect vm_protect
#define rt_vm_deallocate vm_deallocate
#define rt_vm_read_overwrite vm_read_overwrite
#else
#include <mach/mach_vm.h>
typedef mach_vm_address_t rt_vm_address_t;
typedef mach_vm_size_t rt_vm_size_t;
#define rt_vm_map mach_vm_map
#define rt_vm_region mach_vm_region
#define rt_vm_remap mach_vm_remap
#define rt_vm_protect mach_vm_protect
#define rt_vm_deallocate mach_vm_deallocate
#define rt_vm_read_overwrite mach_vm_read_overwrite
#endif
