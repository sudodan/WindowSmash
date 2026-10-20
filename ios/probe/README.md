# iPhone feasibility probe — CPU translation and Metal milestones

Target: iPhone 16 Pro Max, iOS 26, unmodified device.
Upstream inspected: bbef8862046fd98721924338f1b79f65b65ee698.
Branch: ios/feasibility-probe.

This is a diagnostic app, NOT a Smash port. It contains no game data or generated game code.

## What exists

- CPU tests exercise the actual upstream `runtime/recomp.h`: layout, unaligned loads/stores, division edge cases, multiplication, rotate, half precision, signed zero/NaN, vector clearing, and concurrent compare-and-swap.
- An iOS UIKit app runs those checks and attempts simultaneous fixed-address reservations for the runtime's heap, alias, stack, thread-local and native regions. Module and shared-region checks use one page only; actual module sizes require game inputs.
- Successful reservations start inaccessible, then their first page is made writable and tested. Only those pages are touched, not tens of GiB of physical memory. Reservation hints never overwrite mappings; an OS-chosen address different from the requested address is released and reported as a failure. Allocations are released after the probe.
- Version 2 compiles a synthetic Metal compute shader at runtime, dispatches it, and checks 257 results plus 63 guard values. This exercises MSL compilation and GPU readback, not Maxwell translation or game rendering.
- Version 2 sends six original instruction fixtures through upstream `tools/lift.py` at build time. It compares generated C with high-level expectations and, on Apple ARM64, directly executed copies of the same instruction words. It covers add, multiply, a conditional loop, loads/stores, floating-point add and SIMD add. Generated fixtures contain no game code.
- The Share button exports the report.
- An opt-in entitlement supports a later comparison with Extended Virtual Addressing. A compatible provisioning profile is necessary; merely adding the file cannot grant the entitlement.

The memory constants are a snapshot of host.h and tools/recomp.py at the commit above. Recheck them if updating upstream. A failed fixed allocation means this layout failed in this app/configuration, not that an alternative memory design is impossible.

## Current validation

Linux x86-64 GCC: 18/18 CPU helper checks passed, including 20,000 atomic increments. AddressSanitizer and UndefinedBehaviorSanitizer also passed with leak detection disabled (LeakSanitizer cannot inspect processes in this environment). Both plist files parsed successfully.
The first GitHub Actions run passed all 18 CPU checks on a macOS ARM64 runner using Apple Clang. Its initial iOS app compile exposed an unsupported mach_vm.h include; the probe now uses the iOS SDK vm_* interfaces with compile-time 64-bit size checks. The second build successfully compiled and linked the iOS ARM64 app using Xcode 16.4 / iOS 18.5 SDK (deployment target iOS 16). Packaging then failed due to lipo argument order, corrected in the following revision. The third run passed compilation, ARM64 verification, plist validation and unsigned IPA packaging: https://github.com/sudodan/WindowSmash/actions/runs/39353295281 (commit 583d5820c0fe54a6ff52deb093f54c5229693351). Its artifact is `ios-probe-unsigned`. No iPhone execution or iOS 26 runtime compatibility is claimed.

## Build on macOS / hosted runner

Install Xcode and CMake, then from the repository root:

```sh
cmake -S ios/probe -B build/ios-probe -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0
xcodebuild -project build/ios-probe/WindowSmashProbe.xcodeproj \
  -scheme WindowSmashProbe -configuration Release -sdk iphoneos \
  -derivedDataPath build/derived CODE_SIGNING_ALLOWED=NO build
```

The manual GitHub Actions workflow `.github/workflows/ios-probe.yml` performs this unsigned compile check. It is published on the ios/feasibility-probe branch of sudodan/WindowSmash and runs on pushes to that branch. A macOS runner may consume account minutes; check the account's available allocation before dispatching.

An unsigned app cannot run on the phone. For a signed build, open the generated Xcode project on a Mac, select your developer team, set a unique bundle identifier, and configure device provisioning. A hosted Mac can compile/sign, but device installation and provisioning must still be arranged. Do not put certificates, passwords or private keys into the repository.

Test the baseline first. For a separate extended-addressing build, configure with `-DWS_EXTENDED_ADDRESSING=ON` and use a provisioning profile that actually grants that entitlement. Preserve reports separately and record the signing configuration manually.

## Run and interpret

1. Install a properly signed device build; run it outside the debugger for representative results.
2. Share its entire report, including OS version and failures. Record whether the extended entitlement was enabled and accepted.
3. If the app closes, preserve the device crash/termination report; an interrupted run is not a pass.
4. Do not substitute a Simulator result for device behavior.

A successful report only supports continuing the investigation. It does not validate full module mappings, physical RAM budget, write tracking, fibers, guest exceptions, full-game recompiler coverage, translated game shaders, or sustained gameplay.

## Next gates

1. Compile this app for iOS ARM64, sign and execute it on the target phone.
2. If fixed mappings fail, evaluate relocation or explicit guest-to-host memory translation before renderer work.
3. Extend the synthetic instruction checks to guest exception/fiber behavior.
4. Translate a representative game shader and validate output through Metal using locally supplied game inputs.
5. Only then attempt full game startup and measure memory/thermal/performance behavior.

## Run the CPU-only checks on Linux

```sh
cc -std=c11 -O2 -Wall -Wextra -fno-fast-math -ffp-contract=off \
  -DWS_PROBE_CLI -Iruntime ios/probe/cpu_probe.c -pthread -lm -o /tmp/ws-cpu-probe
/tmp/ws-cpu-probe
```

## Windows installation route

After the workflow succeeds, download its `ios-probe-unsigned` artifact and extract `WindowSmashProbe-unsigned.ipa`. It must still be signed. Sideloadly (https://sideloadly.io/) documents Windows installation with a free or paid Apple account and iOS 26 support. Enter credentials only in your local signing tool, never in this repository or chat. Follow its current Windows dependency instructions. Free-account apps require periodic re-signing. This baseline build does not request extended addressing; do not interpret a failure as a test of that entitlement.

After local signing/installation, enable Developer Mode if prompted (Settings > Privacy & Security > Developer Mode, restart and confirm). Open Smash Probe and use its Share button to return the full report. If installation fails, preserve the exact error; if the app terminates, return the crash log rather than treating it as a passing run.

## Version 2 validation — Apple build passed

Linux generated-code checks: 9,216 passed, also with AddressSanitizer and UndefinedBehaviorSanitizer (leak detection disabled for this environment). GitHub Actions run https://github.com/sudodan/WindowSmash/actions/runs/39353958956 passed on commit 810058211b5189309c9e17389ce1e25e8acfc1b7: 18/18 CPU helper checks, 15,360/15,360 generated-code checks including native ARM64 comparisons, and 320/320 Metal outputs/guards on the Apple Paravirtual device. The iOS ARM64 app compiled and its unsigned IPA was packaged successfully. These are Mac runner results, not iPhone results. Physical iPhone memory behavior, full-game semantics, guest exceptions/fibers and translated game shaders remain unverified.

## Version 3 — reusable host memory backend

`runtime/platform/vm.h` and `vm_posix.c` implement owned host-page reservations,
permission changes, zero-on-recommit decommit, and release. The iPhone probe now
uses this backend for all fixed-address tests. It also checks collision safety,
invalid/overflowing ranges, decommit/recommit zeroing and neighboring page data.
GitHub Actions runs the same backend on macOS before compiling the device app.

This is the memory foundation for the Apple port, not yet a replacement of the
Windows kernel/loader. API ownership and threading rules are in `vm.h`. Decommit
uses MAP_FIXED only inside a live owned reservation; initial reservations never
use it. A requested address is a non-destructive mmap hint, accepted only when the
returned address matches exactly. No executable mappings or JIT are requested.

The backend rejects non-host-page-aligned operations. Upstream `kernel.c` allocates
thread-local regions in 4096-byte increments, so it cannot simply call this API on
a host with larger pages. A guest-page layer must track subpage commitments and
avoid discarding neighboring guest pages. Independent permissions and true aliases
also need design work. This limitation is deliberate and appears in the report.
Windows runtime behavior is unchanged. No game startup or phone test is claimed.
