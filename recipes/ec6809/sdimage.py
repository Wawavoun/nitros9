#!/usr/bin/env python3
"""Lay out an OS-9 disk image for an EC-6809 SPI SD card.

The I/O board EPROM (io_eprom_nos9.asm) keeps one 256-byte OS-9 sector
in the first half of each 512-byte SD block: sector N is at byte 512*N of the card, followed by 256
zero bytes. This writes that layout, from block 0, so the result can be
copied to the whole card:

    python3 sdimage.py NOS9_6809_L1_DEV_ec6809.dsk NOS9_6809_L1_DEV_ec6809.sd
    sudo dd if=NOS9_6809_L1_DEV_ec6809.sd of=/dev/sdX bs=512 conv=fsync

The card can then hold only this disk. P_RDSEC takes a 24-bit LSN, so a
larger image than 16777216 sectors is refused. The card must also have
that many blocks.
"""
import argparse
from pathlib import Path

SECTOR = 256
MAX_SECTORS = 1 << 24


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('dsk', type=Path, help='OS-9 disk image, 256-byte sectors')
    parser.add_argument('sd', type=Path, help='output, SD card layout')
    args = parser.parse_args()

    data = args.dsk.read_bytes()
    if len(data) % SECTOR:
        data += bytes(SECTOR - len(data) % SECTOR)
    count = len(data) // SECTOR
    if count > MAX_SECTORS:
        raise SystemExit(f'{args.dsk}: {count} sectors, the SD layout holds {MAX_SECTORS}')

    pad = bytes(SECTOR)
    with args.sd.open('wb') as out:
        for n in range(count):
            out.write(data[n * SECTOR:(n + 1) * SECTOR])
            out.write(pad)
    print(f'{args.sd}: {count} sectors, {count * 2 * SECTOR} bytes')


if __name__ == '__main__':
    main()
