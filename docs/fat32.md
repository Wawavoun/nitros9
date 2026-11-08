# Read-only FAT32

`fatfm` is an OS-9 file manager using the [BlkDev ABI](blkdev.md). It reads
native 512-byte sectors without RBF deblocking. Block addresses, partition
arithmetic, cluster values, file sizes and seek positions use 32-bit values;
FAT entries retain FAT32's defined 28-bit cluster numbering.

The initial implementation supports open, read, ReadLn, seek, close, chd/chx,
and the status calls used by `dir`, `dir -e`, `list` and `copy`. `fatfm` implements
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

In a Wildbits recipe, `make fat32-modules` builds fatfm, fat0, BlkDev and its
backends without adding them to the normal boot image. `FAT_BASE` supplies the
partition's starting 512-byte LBA; `FAT_LENGTH` supplies its length (zero means
the remainder of the device). The default base is zero, for a volume whose BPB
is at LBA zero. Partition tables are not automatically scanned. The descriptor
selects `llwbsdblk`; fatfm does not own or program SD hardware directly.

## Tests

Install the `MC6809` Python package, then run:

```
python3 scripts/test-blkdev.py
python3 scripts/test-fat32.py
python3 scripts/test-cocovhd.py
make -C recipes/coco3/fat_mame_test check PYTHON=/path/to/python \
  LANGUAGES=/path/to/nitros9-languages MAME_ROMPATH=/path/to/mame/roms
```

The CPU suite executes assembled Level 1 and Level 2 modules, including actual
BlkDev and backend code. It covers reads across sectors and fragmented chains,
ReadLn, seeking, directory metadata, failed transfers, malformed geometry,
active FAT selection, cycles, and addresses and clusters above 24 bits.

The main MAME recipe boots an 80-column CoCo 3 from an OS-9 floppy, with a
separate **64 MiB FAT32 image** attached as `-hard1`. `/fat0` selects
`fatfm -> BlkDev -> llcocovhd` and starts at LBA zero of that image.
`llfatfixture` is not in this boot image; sparse embedded media is used only
by isolated CPU tests.

Install `pyfatfs` and `setuptools<81` in the test Python environment.
`scripts/make-fat32-image.py` formats `.fat-test/fat32.vhd` using PyFatFS,
populates files and subdirectories, and deliberately fragments `FRAG.BIN`
across clusters 4, 6 and 8. It reopens the file system to verify the contents
and refreshes both FSInfo copies. On macOS, independently validate it with:

```
/sbin/fsck_msdos -n recipes/coco3/fat_mame_test/.fat-test/fat32.vhd
```

The runner attaches a disposable copy, extracts guest command results from
the OS-9 floppy, compares text and all 1,300 binary bytes, and checks that the
FAT32 image's SHA-256 did not change. This exercises MAME disk-image I/O,
not physical Wildbits SD hardware. `scripts/test-cocovhd.py` additionally
checks register transfers, both units, high addresses, unaligned and 8K-crossing
buffers, first/second-half failures, retries, and read-only enforcement.

The VHD backend uses [MAME's CoCo VHD interface](https://github.com/mamedev/mame/blob/mame0288/src/mame/trs/coco_vhd.cpp),
with 24-bit **256-byte records**, joining two
records into each 512-byte BlkDev block. Its own maximum is 4 GiB; BlkDev and
fatfm retain their 32-bit block addresses. `BC.Port` is $FF80, `BC.Unit` is 0
or 1, and `BC.Base` gives the image's inclusive last 512-byte LBA because the
emulator has no capacity-query register. The descriptor must match the image
size. The backend uses a page-aligned bounce buffer and rejects writes.
Do not access the same VHD port concurrently through EmuDsk.

For an unthrottled screen recording, add
`MAME_VIDEO=/absolute/path/fat32.avi` to the MAME make command. MAME writes
uncompressed AVI, so allow substantial disk space; convert with FFmpeg for
sharing. The runner types through the keyboard matrix at a CoWin-safe rate,
then pauses about 1.7 emulated seconds between commands. `mdir` precedes the FAT32
checks. It uses a disposable copy of the boot floppy under `.fat-test/`,
leaving the built image pristine.

The CoCo test also requires the kernel's fixed interrupt-vector tail to remain
anchored at $FEEE. The accompanying kernel fix anchors graphics-task return
and interrupt code in the always-mapped $FE00 page, pads both CPU variants, and
asserts the final $FF00 boundary; it does not alter Wildbits layout.
