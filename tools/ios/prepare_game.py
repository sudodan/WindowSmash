#!/usr/bin/env python3
"""Prepare private real SSBU inputs and generate C; does NOT build an iPhone app.

Run from a dedicated checkout. Outputs remain in ignored dump/ and build/.
Never run this with game files/keys on the public GitHub Actions workflow.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def run(*args):
    subprocess.run([sys.executable, *map(str, args)], cwd=ROOT, check=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--game', type=Path, help='folder containing your XCI/NSP and update')
    ap.add_argument('--keys', type=Path, help='folder with your console keys (kept local)')
    ap.add_argument('--firmware', type=Path, help='folder containing your firmware NCAs')
    ap.add_argument('--prepared', action='store_true', help='use an already prepared dump/ in this checkout')
    ap.add_argument('--jobs', type=int, default=4)
    ap.add_argument('--inspect-only', action='store_true', help='validate prepared inputs without generating C')
    a = ap.parse_args()
    if a.jobs < 1:
        ap.error('--jobs must be positive')
    if not a.prepared:
        missing = [k for k in ('game', 'keys', 'firmware') if getattr(a, k) is None]
        if missing:
            ap.error('supply --game, --keys and --firmware, or --prepared')
        for name in ('game', 'keys', 'firmware'):
            if not getattr(a, name).is_dir():
                ap.error(f'--{name} must be an existing directory')
        if not (a.keys / 'prod.keys').is_file():
            ap.error('prod.keys is missing from --keys; do not post keys in GitHub')
        run(ROOT/'tools/build_game.py', '--data-only', '--game', a.game.resolve(),
            '--keys', a.keys.resolve(), '--firmware', a.firmware.resolve())
    sys.path.insert(0, str(ROOT/'tools'))
    import build_game
    if not build_game.prepared():
        raise SystemExit('Prepared data is incomplete. Run without --prepared to extract it first.')
    import arc
    cfg = ROOT/'dump/modules/romfs.cfg'
    form, layout, _ = arc.game_data_form(str(cfg))
    if not arc.readable(form, layout):
        raise SystemExit('This data.arc format is unsupported. Supply a compatible update with its base game.')
    from nso import Module
    modules = {}
    for name in ('main', 'subsdk0', 'sdk'):
        path = ROOT/'dump/exefs'/name
        module = Module(str(path))
        modules[name] = {'build_id': module.build_id, 'segment_hashes_verified': bool(module.verified),
                         'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    nro_count = len(list((ROOT/'dump/nro').glob('*.nro')))
    if not nro_count:
        raise SystemExit('No fighter NROs were extracted. Complete data preparation before generating the game.')
    print(json.dumps({'modules': modules, 'nro_count': nro_count}, indent=2))
    if a.inspect_only:
        return 0
    run(ROOT/'tools/recomp.py', 'all', ROOT/'dump/exefs', '--tree', ROOT,
        '--out', ROOT/'build', '--jobs', a.jobs, '--generate-only')
    generated = {name: len(list((ROOT/'build'/name).glob('*.c'))) for name in modules}
    if not all(generated.values()):
        raise SystemExit('Generation returned without C for all three main modules.')
    manifest = {'stage': 'generated-c-only', 'iphone_build': False, 'modules': modules,
                'generated_c_files': generated,
                'next': 'Compile generated game code and all required runtime services for iOS; link and device-test.'}
    out = ROOT/'build/ios-game-manifest.json'
    out.write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print(f'Real game C generated. Local manifest: {out}\nNo iPhone executable has been built by this command.')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        raise SystemExit(str(error))
