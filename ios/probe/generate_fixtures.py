"""Compile original synthetic AArch64 fixtures through WindowSmash's real lifter.
No game input. Identical words are also emitted as native Apple ARM64 assembly
for differential checks. Generated files belong in the build directory.
"""
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from lift import Lifter

RET = 0xD65F03C0
FIXTURES = {
    'add': [0x8B010000, RET],                  # add x0,x0,x1
    'mul': [0x9B017C00, RET],                  # mul x0,x0,x1
    'sum': [0xD2800001, 0xB4000080,           # mov x1,0; cbz x0, +16
            0x8B000021, 0xF1000400,          # add x1,x1,x0; subs x0,x0,1
            0x54FFFFC1, 0xAA0103E0, RET],    # b.ne -8; mov x0,x1
    'memory': [0xF9400001, 0x91001C21,        # ldr x1,[x0]; add x1,x1,7
               0xF9000001, 0xAA0103E0, RET], # str x1,[x0]; mov x0,x1
    'fpadd': [0x1E612800, RET],               # fadd d0,d0,d1
    'vector': [0x4EA18400, RET],              # add v0.4s,v0.4s,v1.4s
}

def generate(destination):
    destination.mkdir(parents=True, exist_ok=True)
    c = ['/* Synthetic fixtures generated with tools/lift.py. */', '#include "recomp.h"']
    asm = ['// Same synthetic words, executed directly on Apple ARM64.', '.text']
    for index, (name, words) in enumerate(FIXTURES.items()):
        base = 0x7100000000 + index * 0x1000
        image = struct.pack('<' + 'I' * len(words), *words)
        source, unsupported, callees = Lifter(image, {0}, base=base).lift_function(0, len(image))
        if unsupported or callees:
            raise RuntimeError(f'{name}: unsupported={unsupported}, callees={callees}')
        c += [source, f'void ws_fixture_{name}(Cpu *c) {{ f_{base:x}(c); }}']
        asm += ['.p2align 2', f'.globl _ws_native_{name}', f'_ws_native_{name}:']
        asm += [f'  .long 0x{word:08x}' for word in words]
    (destination / 'fixtures.c').write_text('\n'.join(c) + '\n')
    (destination / 'native_fixtures.S').write_text('\n'.join(asm) + '\n')
    print(f'Generated {len(FIXTURES)} synthetic functions in {destination}')

if __name__ == '__main__':
    generate(Path(sys.argv[1]))
