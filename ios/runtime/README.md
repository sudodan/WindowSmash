# Apple runtime integration for iPhone

Branch: `ios/apple-runtime`, based on upstream
`06f549807b98bd0f9fa307da035a01807919e068`.
The older `ios/feasibility-probe` branch remains a separate baseline.

This is a runtime-core diagnostic app, not a playable port. It uses upstream's
real Apple memory manager, Win32/POSIX thread/event shim, ARM64 fibers and C++
exception bridge. The synthetic guest routine is handwritten in the recompiler's
calling convention and memory helpers; it is not original game code.

## Changes

- `runtime/apple/vm_compat.h` selects SDK-supported `vm_*` APIs on 64-bit iOS and
  the existing `mach_vm_*` APIs on Mac. Address and size widths are checked.
- The memory manager retains upstream's 4 KB subpage bookkeeping and zero-on-
  recommit behavior on 16 KB Apple host pages. No 4 KB guest request is silently
  discarded by rounding it to a whole host page.
- The shared shim's Linux-only random header is excluded on Apple; its existing
  `arc4random_buf` path supplies randomness.
- iOS waits use public `os_sync_*` APIs (deployment target 18.0). Private ulock
  fallback remains Mac-only. CI checks the iPhone executable's undefined symbols
  for accidental private wait API imports.
- Metal display-sync toggles remain Mac-only; iOS does not advertise tearing.
  The Metal renderer is compiled for iOS but is not linked or run by this app.
- `runtime/ios/window.m` supplies a UIKit/CAMetalLayer surface and CADisplayLink
  wait adapter, with active-state notifications. It is not an SDL window. Full
  guest suspend/resume, input, text entry, and renderer size notifications remain
  integration work. UIKit owns the main loop; the desktop loader's `main` is not
  used as an iOS entry point.

## What the test exercises

1. A small real runtime reservation and 4 KB partial decommit within a 16 KB page:
   zero on recommit, neighboring data preserved, whole-page discard/recommit.
2. A synthetic `Cpu` call with the upstream relocated address helpers. Host-to-
   guest modular subtraction avoids needing the large guest window for this
   helper test; it does not establish a valid console address-space layout.
3. 1,000 switches between the thread's fiber and a new guarded-stack fiber,
   including a preserved local and callback argument.
4. An event timeout, a real thread signaling the event and thread completion.
5. A call through `rt_eh_raise` caught as `RtEhSignal`, checking its payload.

The app links the runtime core; loader/kernel/shader-translator/Metal-renderer
objects are a required separate compile target. Full loader/kernel linkage,
module startup, write-watch fault handling, cross-thread fiber migration and
exception unwinding through generated frames are not established by these tests.
`exception_test.cpp` provides only the diagnostic fatal/describe hooks normally
supplied by the loader; it does not implement or replace a tested runtime service.

## Build and run

The `iOS Apple runtime integration` workflow first executes the core tests on a
Mac ARM64 runner, then builds the iPhone app and required compile-audit objects.
It verifies architecture, checks private wait imports and packages
`WindowSmashRuntime-unsigned.ipa` with a SHA-256 checksum. Mac execution is not
an iPhone result. The unsigned artifact requires local signing before installation.

No game files, keys, signing certificates or game-derived generated C belong in
this public branch or its Actions artifacts. This app contains none.

When device testing is available, install a signed app and share its report.
The **Test address layout** button separately attempts upstream's 512 GiB guest
window starting at 1 TiB, with its optional guard reservations. This reserves
virtual space, not that much physical RAM. The reservation stays until the app
exits. Failure remains a major porting blocker, not a failed core-memory test.
This build requests no extended-address entitlement. No successful reservation,
game boot or performance on the user's phone is assumed.

## Next integration gates

- Device VM/layout and fault/write-watch checks.
- A synthetic module boot linking the actual loader/kernel and explicit test
  services, using an iOS entry point rather than the Mac process startup.
- Offscreen upstream shader/renderer tests and device capability/readback checks.
- iOS SDL/codecs, input/audio interruptions, sandboxed game-data/save/cache paths.
- Private game code generation, signing, startup and memory/performance testing.
