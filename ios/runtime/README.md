# Apple runtime integration for iPhone

Branch: `ios/apple-runtime`, based on upstream
`06f549807b98bd0f9fa307da035a01807919e068`.
The older `ios/feasibility-probe` branch remains a separate baseline.

This is a runtime diagnostic app, not a playable port. It uses upstream's
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

The app also links the real loader and kernel through `rt_embedded_boot`, called
on a dedicated worker with a 16 MiB stack. It bypasses desktop process startup.
The **Boot synthetic guest** button runs 19 additional checks:

- Three original synthetic module images, dependency-order initialization,
  cross-module relocation/addend, native imports and unresolved weak imports.
- Kernel heap allocation/query, stack mapping and copy-back on unmap.
- Real write faults, write-watch reset/rearming, and partial decommit/recommit
  through watched aliases while preserving neighboring data.
- Guest thread creation, start, exit and wait through the actual kernel SVCs.

`generate_boot_images.py` creates the small original fixtures at build time.
`boot_services.c` supplies explicit peripheral test doubles: unexpected IPC is
fatal, while unused GPU resource cleanup and networking cleanup are no-ops.
Graphics, audio and game services are not established by this test. The shader
translator and Metal renderer remain required compile-only targets.
Cross-thread fiber migration and exception unwinding through generated game
frames are also untested. The embedded boot is one-shot; restart the app to retry.
Loader fatal paths and guest process termination still need production handling.

## Build and run

The `iOS Apple runtime integration` workflow first executes the core tests on a
Mac ARM64 runner, boots the synthetic guest there, then builds the iPhone app
and required compile-audit objects.
It verifies architecture, checks private wait imports and packages
`WindowSmashRuntime-unsigned.ipa` with a SHA-256 checksum. Mac execution is not
an iPhone result. The unsigned artifact requires local signing before installation.

No game files, keys, signing certificates or game-derived generated C belong in
this public branch or its Actions artifacts. This app contains none.

When device testing is available, install a signed app and share its report.
The **Boot synthetic guest** button first attempts upstream's 512 GiB guest
window starting at 1 TiB, with its optional guard reservations. This reserves
virtual space, not that much physical RAM. The reservation stays until the app
exits. Failure remains a major porting blocker, not a failed core-memory test.
This build requests no extended-address entitlement. No successful reservation,
synthetic boot, game boot or performance on the user's phone is assumed.

## Next integration gates

- Device VM/layout and fault/write-watch checks.
- Offscreen upstream shader/renderer tests and device capability/readback checks.
- iOS SDL/codecs, input/audio interruptions, sandboxed game-data/save/cache paths.
- Private game code generation, signing, startup and memory/performance testing.

## Validation — 2026-10-20

Successful v0.2 run: https://github.com/sudodan/WindowSmash/actions/runs/39491966955
Build commit: `73e93c222aedd4a35c396050d46c8e124361da63`.

- Mac ARM64 execution: 20/20 runtime-core checks and 19/19 synthetic boot checks.
- Xcode 16.4 / iPhoneOS 18.5 SDK: app including actual loader/kernel compiled
  and linked for arm64 with deployment target iOS 18.0.
- Required object target compiled the shader translator and adapted Metal
  renderer for iOS; neither is linked into the diagnostic executable.
- Binary architecture, Info.plist, three bundled fixtures and absence of private
  ulock imports passed.
- Unsigned IPA and checksum packaged in artifact `ios-runtime-unsigned`.

The earlier v0.1 core-only run was
https://github.com/sudodan/WindowSmash/actions/runs/39490837684.
There has been no iPhone execution, renderer execution, original game startup,
or game performance measurement for this branch. A successful synthetic boot
on Mac does not establish that iOS permits the same address layout or faults.
