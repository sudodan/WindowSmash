#!/usr/bin/env python3
"""Create original synthetic module data, not extracted or derived game assets."""
from pathlib import Path
import struct
import sys
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for name, value in [('main', 0x1234), ('subsdk0', 0x5678), ('sdk', 0x9abc)]:
    image = bytearray(0x10000)
    struct.pack_into('<Q', image, 0x8000, value)
    (out / (name + '.reloc.bin')).write_bytes(image)
