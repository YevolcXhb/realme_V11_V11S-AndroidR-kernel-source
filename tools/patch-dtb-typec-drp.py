#!/usr/bin/env python3
"""Set mt-tcpc,role_def on type_c_port0 inside a boot image's appended DTB.

The stock DTB ships role_def = 0 (SNK Only), so the port can never source VBUS
and a passive USB-C dock stays completely unpowered: no attach event, no VBUS,
no hub. Setting role_def = 2 (DRP) lets the port toggle; when a sink (dock)
attaches the phone becomes DFP/source, powers the dock and enumerates it.

    ./patch-dtb-typec-drp.py boot.img boot-drp.img            # 0 -> 2
    ./patch-dtb-typec-drp.py boot.img out.img --role 1        # force source

The image length is unchanged - only the 4-byte property value is rewritten -
so the boot header, kernel and ramdisk are untouched. Flash the result to the
boot partition and keep the original image: reverting is flashing it back.
"""
import argparse, struct, sys

FDT_MAGIC = b'\xd0\x0d\xfe\xed'
PROP = 'mt-tcpc,role_def'
NODE = 'type_c_port0'


def find_fdts(data):
    out, start = [], 0
    while True:
        i = data.find(FDT_MAGIC, start)
        if i < 0:
            return out
        if i + 40 <= len(data):
            total = struct.unpack('>I', data[i + 4:i + 8])[0]
            if 40 < total <= len(data) - i:
                out.append((i, total))
                start = i + total
                continue
        start = i + 4


def locate(fdt, role_def_offset):
    """Return the absolute offset of the role_def value inside the FDT blob."""
    h = struct.unpack('>10I', fdt[:40])
    off_struct, off_strings, sz_str, sz_struct = h[2], h[3], h[8], h[9]
    strings = fdt[off_strings:off_strings + sz_str]
    blk = fdt[off_struct:off_struct + sz_struct]
    pos, stack = 0, []
    while pos + 4 <= len(blk):
        tok = struct.unpack('>I', blk[pos:pos + 4])[0]
        pos += 4
        if tok == 1:
            end = blk.index(b'\x00', pos)
            stack.append(blk[pos:end].decode('utf-8', 'replace'))
            pos = (end + 1 + 3) & ~3
        elif tok == 2:
            if stack:
                stack.pop()
        elif tok == 3:
            ln, noff = struct.unpack('>II', blk[pos:pos + 8])
            pos += 8
            end = strings.index(b'\x00', noff)
            name = strings[noff:end].decode('utf-8', 'replace')
            val_abs = role_def_offset + off_struct + pos
            if name == PROP and stack and stack[-1] == NODE:
                return val_abs, ln
            pos = (pos + ln + 3) & ~3
        elif tok == 9:
            break
        else:
            break
    return None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('dst')
    ap.add_argument('--role', type=int, default=2,
                    help='0=SNK Only, 1=SRC Only, 2=DRP (default 2)')
    a = ap.parse_args()

    data = bytearray(open(a.src, 'rb').read())
    for off, total in find_fdts(data):
        val_abs, ln = locate(bytes(data[off:off + total]), off)
        if val_abs is None:
            continue
        if ln != 4:
            sys.exit('role_def is %d bytes, expected a u32' % ln)
        old = struct.unpack('>I', bytes(data[val_abs:val_abs + 4]))[0]
        data[val_abs:val_abs + 4] = struct.pack('>I', a.role)
        open(a.dst, 'wb').write(data)
        print('fdt @0x%x: %s %d -> %d (0x%x)' % (off, PROP, old, a.role, val_abs))
        return
    sys.exit('no %s property for node %s found' % (PROP, NODE))


if __name__ == '__main__':
    main()
