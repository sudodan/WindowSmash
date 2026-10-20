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
Graphics, audio and game services are not established by this test. The Metal
renderer remains a required compile-only target. The shader translator is also linked and exercised by the separate shader test below.
Cross-thread fiber migration and exception unwinding through generated game
frames are also untested. The embedded boot is one-shot; restart the app to retry.
Loader fatal paths and guest process termination still need production handling.

## Translated shader GPU test (v0.3)

**Test shaders** runs upstream `tools/mac/msltest.m`'s eight GPU test groups with
our real `gpu_shader.c` translator: arithmetic, control flow, memory, textures,
points, triangles, dual-source blending and texture LOD bias. Results are read
back and compared with CPU expectations. It uses original hand-assembled Maxwell
programs, with no game dump and no guest virtual-address reservation required.
This exercises shader translation and Metal execution, not the full
`gpu_metal.m` rendering backend or the game's command stream.

`shader_test.m` embeds the existing tests and captures their printf diagnostics
locally for the app's shareable report. Run it once per app launch, in the
foreground, and wait for completion before starting the other test. A missing
Metal device/queue is explicitly BLOCKED (CLI exit 77), not a pass. CI records
that condition and continues the SDK build; other nonzero returns fail CI.
The first hardware run may expose shader or texture-format compatibility issues.

## Actual renderer diagnostic

`WindowSmashRenderer` is a separate app, with bundle identifier
`org.windowsmash.renderer-test`. It links the actual `gpu_metal.m` renderer,
`gpu_shader.c` translator, `gpu_texture.c` texture decoder and Apple memory/thread
backend. Its fixture reuses selected tests from `tools/mac/gfxtest.m`:

- Color/depth clears; triangles, indices, points, depth and stencil.
- Textures and CPU texture updates, render targets used as textures.
- GPU constant updates, render state, dual-source blending and scaled blits.
- Compute outputs, GPU-resident data, drawing from compute results and copying
  results back to guest memory.

Each workload reads back pixels or data and checks expected values. This is an
integration of the renderer with synthetic GPU register state; it does not run
the game, its command processor, or its services. The suite excludes presentation,
overlay, screenshots, cache persistence checks and the upstream 1.5 GB upload
stress test. Display/input/network/profile functions are fixture implementations;
the overlay callback is a no-op and is not tested.

The app owns its guest-memory map, fault handler and renderer for its lifetime.
It reserves the upstream address layout, commits 64 MiB for synthetic guest data
and allocates additional renderer/GPU resources. Run once per launch. It uses an
absolute cache path under the app sandbox, with no working-directory change.
A missing Metal device or failed memory reservation reports BLOCKED; unexpected
renderer fatal errors may still close the diagnostic app.

Install the `ios-renderer-unsigned` artifact separately after signing. Open
**Smash Renderer**, tap **Run renderer**, keep it in the foreground until it
finishes, then share the report. The earlier **Smash Runtime** app remains useful
for independent shader checks when the guest memory layout is unavailable.

## Build and run

The `iOS Apple runtime integration` workflow first executes the core tests on a
Mac ARM64 runner, boots the synthetic guest there, then builds the iPhone app
and required compile-audit objects. It also attempts the translated shader GPU
checks on the Mac runner and includes their report with the build artifact.
It verifies architecture, checks private wait imports and packages
`WindowSmashRuntime-unsigned.ipa` with a SHA-256 checksum. Mac execution is not
an iPhone result. The unsigned artifact requires local signing before installation.

No game files, keys, signing certificates or game-derived generated C belong in
this public branch or its Actions artifacts. This app contains none.

When device testing is available:

1. Install a signed copy of the latest unsigned IPA, then open the app.
2. Wait for the automatic runtime-core report.
3. Tap **Test shaders**, keep the app in the foreground, and wait for its status.
4. Share that report before attempting guest boot, so it survives a possible crash.
5. Tap **Boot synthetic guest**, then share the resulting report. If the app closes,
   report which button was running and save the matching iOS crash log if available.

These tests need no XCI file. They are diagnostics, not a playable game.

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

Successful v0.3 run: https://github.com/sudodan/WindowSmash/actions/runs/39493189608
Build commit: `26fce6607d5740c7bed5f500247ee1f15ddcb2b0`.

- All eight shader GPU groups passed: **16,287 comparisons, zero failures**.
- The runner reports **Apple Paravirtual device**, not an iPhone GPU. These results
  establish execution through that virtual Metal device only.
- Runtime-core 20/20 and synthetic loader/kernel boot 19/19 checks still passed.
- iPhone app including the real shader translator compiled, linked and packaged.
- Unsigned IPA, checksum and shader execution report are in `ios-runtime-unsigned`.
- No iPhone execution or full renderer execution has occurred.

### Earlier loader/kernel milestone

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
