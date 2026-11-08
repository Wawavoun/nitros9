# Read-only FAT32

`FAT` is an OS-9 file manager using the [BlkDev ABI](blkdev.md). It reads
native 512-byte sectors without RBF deblocking. Block addresses, partition
arithmetic, cluster values, file sizes and seek positions use 32-bit values;
FAT entries retain FAT32's defined 28-bit cluster numbering.

The initial implementation supports open, read, ReadLn, seek, close, chd/chx,
and the status calls used by `dir`, `dir -e`, `list` and `copy`. FAT implements
[SS.ReadDir](ss-readdir.md) for the updated `dir`: names-only (32 bytes) and
extended metadata (45 bytes), with dot/deleted/long-name entries filtered.
Enumeration shares the path position and rewinds with Seek to zero. All mutation
calls, including `SS.Rename`, return E$WP. Names use case-insensitive ASCII
8.3 aliases; long-name entries are skipped. Directory reads synthesize OS-9 records and metadata,
including `.` and `..`. Their 24-bit FD cookies identify directory slots within
an open directory, not disk addresses or cluster numbers. Raw RBF sector/FD
editing utilities are not supported.

Each system path allocates 2048 bytes, including separate data and FAT sector
caches. Duplicated paths share this allocation until the final close. FAT chains
are checked for invalid/reserved/free clusters, premature end and cycles.
Geometry and address arithmetic are checked before access. Media must remain
unchanged while paths are open; unmount before replacing a card.

## Building

In a Wildbits recipe, `make fat32-modules` builds FAT, fat0, BlkDev and its
backends without adding them to the normal boot image. `FAT_BASE` supplies the
partition's starting 512-byte LBA; `FAT_LENGTH` supplies its length (zero means
the remainder of the device). The default base is zero, for a volume whose BPB
is at LBA zero. Partition tables are not automatically scanned. The descriptor
selects `llwbsdblk`; FAT does not own or program SD hardware directly.

## Tests

Install the `MC6809` Python package, then run:

```
python3 scripts/test-blkdev.py
python3 scripts/test-fat32.py
make -C recipes/coco3/fat_mame_test check PYTHON=/path/to/python \
  LANGUAGES=/path/to/nitros9-languages MAME_ROMPATH=/path/to/mame/roms
```

The CPU suite executes assembled Level 1 and Level 2 modules, including actual
BlkDev and backend code. It covers reads across sectors and fragmented chains,
ReadLn, seeking, directory metadata, failed transfers, malformed geometry,
active FAT selection, cycles, and addresses and clusters above 24 bits.

The MAME recipe boots an 80-column CoCo 3 with a local RBF floppy and exposes `/fat0`
through a test-only sparse backend. Its FAT32 geometry is valid while only
nonzero sectors consume module space. Guest command output is extracted from
the floppy and compared with known text and binary bytes. This validates the
OS-9/file-manager/BlkDev integration; it does not validate a physical SD card
or Wildbits hardware timing.

For an unthrottled screen recording, add
`MAME_VIDEO=/absolute/path/fat32.avi` to the MAME make command. MAME writes
uncompressed AVI, so allow substantial disk space; convert with FFmpeg for
sharing. The runner types through the keyboard matrix at a CoWin-safe rate,
then allows two emulated seconds for execution. `mdir` precedes the FAT32
checks. It uses a disposable copy of the boot floppy under `.fat-test/`,
leaving the built image pristine.

The CoCo test also requires the kernel's fixed interrupt-vector tail to remain
anchored at $FEEE. The accompanying kernel fix anchors graphics-task return
and interrupt code in the always-mapped $FE00 page, pads both CPU variants, and
asserts the final $FF00 boundary; it does not alter Wildbits layout.
