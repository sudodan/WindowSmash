#!/usr/bin/env python3
"""Compile selected unchanged upstream units for iPhone; NOT an app/link/run test.

Usage: python3 compile_upstream.py UPSTREAM_CHECKOUT OUTPUT_DIR
Exit 1 means at least one selected unit is blocked; logs are retained for all units.
No game files, keys, generated game code, or downloaded dependencies are used.
"""
import json
from pathlib import Path
import subprocess
import sys

PIN = '06f549807b98bd0f9fa307da035a01807919e068'
SOURCES = [
    'runtime/gpu_shader.c', 'runtime/macos/fiber.c',
    'runtime/macos/fiber_arm64.S', 'runtime/linux/eh.cpp',
    'runtime/macos/memory.c', 'runtime/macos/platform.c',
    'runtime/macos/gpu_metal.m', 'runtime/macos/window.m',
    'runtime/linux/win32.c', 'runtime/kernel.c', 'runtime/host.c',
]

def main():
    root, out = (Path(p).resolve() for p in sys.argv[1:])
    out.mkdir(parents=True, exist_ok=True)
    def query(*cmd):
        return subprocess.check_output(cmd, text=True).strip()
    revision = query('git', '-C', str(root), 'rev-parse', 'HEAD')
    if revision != PIN:
        raise SystemExit(f'Expected upstream {PIN}, got {revision}')
    if query('git', '-C', str(root), 'status', '--porcelain'):
        raise SystemExit('Upstream must be unmodified for this audit')
    sdk = query('xcrun', '--sdk', 'iphoneos', '--show-sdk-path')
    compiler = query('xcrun', '--sdk', 'iphoneos', '--find', 'clang')
    sdk_version = query('xcrun', '--sdk', 'iphoneos', '--show-sdk-version')
    rows = []
    for source in SOURCES:
        name = source.replace('/', '_')
        flags = ['-target', 'arm64-apple-ios18.0', '-isysroot', sdk,
                 '-O2', '-fno-strict-aliasing', '-ffp-contract=off',
                 '-Werror=unguarded-availability-new']
        for include in ('runtime/macos/include', 'runtime/linux/include', 'runtime'):
            flags += ['-I', str(root / include)]
        if source.endswith('.m'):
            flags += ['-fobjc-arc']
        if source.endswith('.cpp'):
            flags += ['-std=gnu++20', '-fexceptions']
        command = [compiler, *flags, '-c', str(root / source), '-o', str(out / (name + '.o'))]
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        log = result.stdout + result.stderr
        (out / (name + '.log')).write_text(log)
        errors = [line.strip() for line in log.splitlines() if 'error:' in line]
        row = dict(source=source, compiled=result.returncode == 0,
                   returncode=result.returncode, errors=errors, command=command)
        rows.append(row)
        print(f"{'COMPILED' if row['compiled'] else 'BLOCKED'}: {source}", flush=True)
        for line in errors[:3]:
            print('  ' + line, flush=True)
    report = dict(upstream=revision, sdk=sdk_version, target='arm64-apple-ios18.0', units=rows,
                  limitation='Individual objects only. No linking, shader execution, app signing, or phone/game execution.')
    (out / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['# Upstream iPhone SDK compile audit', '', f'Upstream: `{revision}`',
             f'iPhone SDK: {sdk_version}; target: arm64 iOS 18.0', '',
             report['limitation'], '', '| Source | Result | First compiler error |', '|---|---|---|']
    for row in rows:
        first = row['errors'][0] if row['errors'] else ''
        first = first.replace(str(root) + '/', '').replace('|', '\\|')
        lines.append(f"| `{row['source']}` | {'COMPILED' if row['compiled'] else 'BLOCKED'} | {first} |")
    (out / 'SUMMARY.md').write_text('\n'.join(lines) + '\n')
    return int(any(not r['compiled'] for r in rows))

if __name__ == '__main__':
    sys.exit(main())
