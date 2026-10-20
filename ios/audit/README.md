# Mac-to-iPhone source audit

Reviewed upstream: `06f549807b98bd0f9fa307da035a01807919e068` (2026-10-20).
Our existing probe baseline: `5b7c840915932f06665cd4374f52bd0fb142383c`.
This directory records an audit, not an integrated game port.

## Decision

Use the upstream Apple runtime as the next integration base. Keep the existing
probe as a diagnostic baseline. Do not independently reimplement its Metal
renderer, ARM64 fibers, or guest-page bookkeeping. Do not simply drop the new
`recomp.h` into the old probe: its memory helpers now add RT_MEMBASE, whereas our
synthetic fixtures currently pass host pointers directly. Reconcile tests and
runtime together on a separate integration branch.

## Findings from source

| Component | Existing upstream implementation | iPhone work still required |
|---|---|---|
| CPU translation | `tools/lift.py`, `runtime/recomp.h`, `runtime/host.h`: Apple ARM64 and guest-to-host address helpers | Regenerate game code against matching runtime; retain floating-point and atomic semantics; update pointer-based probes |
| Guest memory | `runtime/macos/memory.c`: tracks 4 KB commitments within 16 KB host pages; preserves neighboring pages on partial decommit | Replace unsupported SDK interfaces; test reservation and write-watch faults on device |
| Address layout | `recomp.h`: RT_MEMBASE is 1 TB; `memory.c`: 512 GB guest window, optional 64 GB lower and 512 GB upper guards | Critical device gate. Our old identity-address probe does NOT test this layout. A failure requires a different memory layout/translation design |
| Shader translator | `runtime/gpu_shader.c`: Maxwell to Metal Shading Language as well as HLSL | Compile emitted shaders with the device compiler, then verify GPU outputs; C object compilation alone proves neither |
| Renderer | `runtime/macos/gpu_metal.m`: Metal render/compute passes, upload and texture caches, GPU-address buffer bindings, runtime MSL compilation | SDK calls/availability, pixel formats and GPU capabilities, memory budget, integration with an iPhone CAMetalLayer |
| Fibers | `runtime/macos/fiber.c`, `fiber_arm64.S`: guarded stacks and ARM64 context switches | Link and exercise register preservation, cross-thread resumption and exception unwinding on device; object compilation is insufficient |
| C++ exceptions | `runtime/linux/eh.cpp`, generated landing-site wrappers | Compile/link with iOS C++ runtime and test unwinding across generated frames and fibers |
| Window/lifecycle | `runtime/macos/window.m`: AppKit, CVDisplayLink, SDL desktop window, menus | Replace with iOS lifecycle/window code, pacing, suspend/resume and text entry |
| Platform waits/diagnostics | `runtime/macos/platform.c`: Mach time, os_sync waits, private ulock fallback, stack walking | Explicit iOS availability checks; exclude private fallback from iOS path; adapt Mach calls and optional diagnostics |
| Input/audio | Shared SDL paths (`hle_pad.c` and audio code) | Build SDL and codecs for iOS; validate controller connection and audio interruption handling |
| Packaging | `tools/mac/build_mac.py`: macOS bundle, AppKit/IOKit frameworks and ad-hoc signing | iOS app target and dependency builds, sandboxed data/save/cache locations, device provisioning |

The Mac memory layer conservatively makes an entire host page accessible when a
subpage is committed. Its write watch reports all committed subpages touched by a
host-page fault. This is an existing compatibility strategy, not exact independent
4 KB host protection. The renderer accounts for conservative dirty reports.

`docs/MACOS.md` reports opening/menu checks for 13.0.5 on an M5 Pro, not full-match
validation. We have not reproduced those game results, and they provide no iPhone
performance measurement.

## Reproducible SDK audit

`.github/workflows/ios-upstream-audit.yml` checks out the exact upstream revision
and calls `compile_upstream.py` on 11 selected, unchanged translation units. It
uses the iPhone SDK, arm64 iOS 18.0 target, and errors for unguarded newer APIs.
No SDL or codec dependencies are installed in this narrow audit. A missing header
can hide later errors in the same file. This is not exhaustive runtime coverage.

The workflow deliberately fails if any unit does not compile. It still uploads
all compiler logs, JSON results and a Markdown summary. A compiled unit is only
an object: unresolved functions, linking, emitted MSL, signing and execution are
not tested. The existing iPhone probe workflow remains separate.

## Integration order

1. Add a device probe of the upstream relocated address window using supported
   iOS interfaces, recording baseline/entitlement configuration. Device test pending.
2. Make an integration branch based on the pinned Apple runtime; adapt API calls
   and the iOS application entry point. Preserve the existing diagnostic branch.
3. Link a synthetic guest boot test with the real kernel and runtime; exercise
   memory, fault-based write tracking, fibers and guest exceptions.
4. Port upstream `tools/mac/msltest.m` and `gfxtest.m` to an offscreen iOS test
   harness. Confirm capability support and compare GPU output.
5. Prepare the user's executable/data inputs locally, generate matching C, build
   and sign privately, then attempt game startup. Measure physical memory and
   rendering behavior before any playable-game claim.

The source review and SDK audit require no game upload or access to the user's PC.

## Measured SDK results

Audit run: https://github.com/sudodan/WindowSmash/actions/runs/39488840322
Audit harness commit: `813d132bb868728f027ed08dfaa29e650d1cbfee`.
Xcode 16.4, iPhoneOS 18.5 SDK, arm64 iOS 18.0 target. Completed with the expected
nonzero audit result because 5 units failed. Compiler evidence is preserved in
artifact `upstream-iphone-compile-audit`.

| Unchanged source | Object compilation result |
|---|---|
| `runtime/gpu_shader.c` | Compiled |
| `runtime/macos/fiber.c` | Compiled |
| `runtime/macos/fiber_arm64.S` | Compiled |
| `runtime/linux/eh.cpp` | Compiled |
| `runtime/kernel.c` | Compiled |
| `runtime/host.c` | Compiled |
| `runtime/macos/memory.c` | Blocked: iOS SDK rejects mach/mach_vm.h; mach_vm_map/region and other calls need adaptation |
| `runtime/macos/platform.c` | Blocked: mach/mach_vm.h and mach_vm_read_overwrite |
| `runtime/macos/gpu_metal.m` | Blocked: mach/mach_vm.h, mach_vm_read_overwrite, CAMetalLayer.displaySyncEnabled |
| `runtime/macos/window.m` | Blocked: AppKit/AppKit.h absent from iPhone SDK |
| `runtime/linux/win32.c` | Blocked: sys/random.h absent from iPhone SDK |

Six selected units compiled unchanged; five did not. This does not mean six of
eleven total porting tasks are complete. Most of the runtime was not compiled by
this audit, dependencies were not linked, and no binary was run on an iPhone.
The C shader translator compiling does not establish generated Metal shader
compatibility. Further diagnostics can appear after the first errors are fixed.

The next implementation milestone is an isolated integration branch with iOS VM
API wrappers, guarded desktop-only Metal presentation settings, a UIKit host,
and an iOS-compatible randomness path. Then rerun the SDK audit and link the
synthetic guest harness, while keeping the relocated memory test as a device gate.
