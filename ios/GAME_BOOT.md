# Real Smash Ultimate boot work

The target is the original game's executable running through the iOS runtime.
The repository is already cloned/forked. Synthetic tests validate components but
are not a game boot, and no complete iPhone game executable exists yet.

## Real input preparation on Windows

Use a dedicated checkout of the `ios/apple-runtime` branch, Python 3.10 or newer,
and sufficient space (upstream recommends roughly 60 GB plus the game dumps).
Have these local folders ready:

- `D:\MyDump`: your base XCI/NSP and compatible update, plus optional DLC.
- `D:\MyKeys`: your console's `prod.keys` and applicable `title.keys`.
- `D:\MyFirmware`: your firmware's NCA files, for the game's fonts.

The upstream README states that unupdated 1.0.0 data is unsupported; 11.0.0 and
13.0.5 have been tested upstream. Container names/sizes do not identify the
installed game version. The scan and data.arc check must establish compatibility.

From the checkout, run:

```powershell
python tools/ios/prepare_game.py --game "D:\MyDump" --keys "D:\MyKeys" --firmware "D:\MyFirmware" --jobs 4
```

This calls the real upstream extraction/update/font/fighter preparation, validates
its inputs, then invokes the real recompiler with `--generate-only`. The new
`build_game.py --data-only` option skips desktop compiler setup and the desktop
build. Python dependencies are still installed if missing. Game files stay local.

Outputs are ignored by git:

- `dump/exefs`: the actual executable modules.
- `dump/modules`: relocated images and game-data configuration.
- `dump/nro`: actual fighter modules.
- `build`: generated C and `ios-game-manifest.json` with module build IDs/hashes.

For an already prepared checkout:

```powershell
python tools/ios/prepare_game.py --prepared --inspect-only
python tools/ios/prepare_game.py --prepared --jobs 4
```

Do not upload these outputs or keys to the public repository/Actions artifacts.
Do not put game files through the public diagnostic workflow. Generation can take
a long time; the upstream recompiler resumes/reuses completed modules.

## What still separates generated C from an iPhone boot

1. Compile the generated real modules for arm64 iOS and link them with the actual
   runtime services, not the synthetic module tables or peripheral test doubles.
2. Finish iOS integration for game services, codecs/audio/controllers, filesystem
   access and app lifecycle. Translate desktop game-data paths into sandbox paths.
3. Resolve renderer initialization/execution problems and device memory-layout
   restrictions. The offscreen renderer CI test is currently unverified/stalled;
   a bounded run with progress logging is queued to diagnose it.
4. Sign/install a private build and capture the first real loader/startup error.
   Iterate toward title-screen boot, then gameplay correctness and performance.

The preparation command does not produce an IPA and does not prove that the
whole game fits or works on iOS. No real-game extraction/generation has been run
in this workspace: the necessary console keys/firmware/update have not been supplied.
