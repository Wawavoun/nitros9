# pcf: FAT32 file manager

`pcf` is an OS-9 file manager using the [blkdrv ABI](blkdrv.md). It reads
native 512-byte sectors without RBF deblocking. Block addresses, partition
arithmetic, cluster values, file sizes and seek positions use 32-bit values;
FAT entries retain FAT32's defined 28-bit cluster numbering.

The initial implementation supports open, read, ReadLn, seek, close, chd/chx,
and the status calls used by `dir`, `dir -e`, `list` and `copy`. `pcf` implements
[SS.ReadDir](ss-readdir.md) for the updated `dir`: names-only (32 bytes) and
extended metadata (45 bytes), with dot/deleted/long-name entries filtered.
Enumeration shares the path position and rewinds with Seek to zero. Writable
descriptors also support create, write, WriteLn, resize, and delete. Directory
creation, rename, and long-name mutations are not implemented. Names use case-insensitive ASCII
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

In a Wildbits recipe, `make fat32-modules` builds pcf, pc0, blkdrv and its
backends without adding them to the normal boot image. `FAT_BASE` supplies the
partition's starting 512-byte LBA; `FAT_LENGTH` supplies its length (zero means
the remainder of the device). The default base is zero, for a volume whose BPB
is at LBA zero. Partition tables are not automatically scanned. The descriptor
selects `llwbsdblk`; pcf does not own or program SD hardware directly.

## Tests

Install the `MC6809` Python package, then run:

```
python3 scripts/test-blkdrv.py
python3 scripts/test-fat32.py
python3 scripts/test-cocovhd.py
make -C recipes/coco3/fat_mame_test check PYTHON=/path/to/python \
  LANGUAGES=/path/to/nitros9-languages MAME_ROMPATH=/path/to/mame/roms
```

The CPU suite executes assembled Level 1 and Level 2 modules, including actual
blkdrv and backend code. It covers reads across sectors and fragmented chains,
ReadLn, seeking, directory metadata, failed transfers, malformed geometry,
active FAT selection, cycles, and addresses and clusters above 24 bits.

The main MAME recipe boots an 80-column CoCo 3 from an OS-9 floppy, with a
separate **64 MiB FAT32 image** attached as `-hard1`. `/pc0` selects
`pcf -> blkdrv -> llcocovhd` and starts at LBA zero of that image.
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
records into each 512-byte blkdrv block. Its own maximum is 4 GiB; blkdrv and
pcf retain their 32-bit block addresses. `BC.Port` is $FF80, `BC.Unit` is 0
or 1, and `BC.Base` gives the image's inclusive last 512-byte LBA because the
emulator has no capacity-query register. The descriptor must match the image
size. The backend uses a page-aligned bounce buffer; `BC.Flags` controls write
protection. Descriptors default to read-only; `-DFATWrite=1` enables writes.
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

## Booting OS9Boot from FAT32 (CoCo 3 / MAME VHD)

`level1/coco1/modules/boot_fat32.asm` is a standalone **464-byte Boot module**,
including its OS-9 header and CRC. It fits the existing `$EE30..$EFFF` Level 2
slot without changing Rel, Krn, or the kernel-track layout. Assembly fails if
code plus CRC exceeds that slot. The same code assembles for 6809 and 6309.

The loader looks for root short name `OS9BOOT`, reads the exact file length,
and follows both root-directory and file cluster chains. The file need not
be contiguous or reside in the root directory's first cluster. It reads the
BPB rather than compiling in a particular FAT size or data-area offset.
It calls `F$BtMem` and returns the normal Boot contract (`X` = file address,
`D` = byte count). The kernel performs module validation afterward.

This early loader cannot depend on pcf or blkdrv, which are inside OS9Boot.
Its small VHD reader accesses the emulator registers directly. After boot,
normal FAT32 access still uses `pcf -> blkdrv -> llcocovhd`.

Build-time settings are `FATBase` (512-byte volume-start LBA, default 0),
`DEVADDR` (default `$FF80`), and `DISKNUM` (0 or 1, default 0). The supported
media contract is a valid FAT32 volume with 512-byte sectors, a power-of-two
cluster size, one or two FATs, and an authoritative FAT #0. With mirroring
disabled, FAT #0 must be the active FAT. The entire accessed volume must fit
within the VHD interface's 4 GiB address space. There is no partition-table
search, long-name lookup, subdirectory boot path, or hardware SD variant yet.

The loader rejects zero/invalid cluster sizes, non-512-byte sectors, missing
files, early end-of-chain, read failures, and unrepresentable boot-file sizes.
Boot-file length must be 1..65,280 bytes and fit available kernel boot memory.
To fit 464 bytes it relies on a valid, consistent filesystem: it does not do
full BPB/range validation or detect directory-chain cycles. Use a filesystem
checker on media suspected of corruption. This limitation belongs to the
minimal booter; pcf retains its more extensive validation.

The CoCo Level 2 early stack is below `$0800`. The booter uses the reserved,
not-yet-active system-stack page `$0800..$08FF` as a 256-byte DMA buffer, keeping
kernel process/dispatch tables untouched and avoiding VHD 8K boundary splits.
It uses 24 bytes of stack-local state plus subroutine/system-call stack space.
The scratch page is reusable after boot; no persistent fixture is loaded.

Run the instruction-level and real MAME tests with:

```
LWASM=lwasm.orig python3 scripts/test-boot-fat32.py
make -C recipes/coco3/fat_boot_mame_test check PYTHON=/path/to/python \
  LANGUAGES=/path/to/nitros9-languages MAME_ROMPATH=/path/to/mame/roms
```

The dedicated recipe puts the usual `rel_80`, this Boot, and Krn on the floppy
kernel track. It writes the actual recipe bootfile as `/OS9BOOT` in an external
64 MiB FAT32 image, deliberately fragments it, and places its directory entry
beyond the first root cluster. Before MAME starts, the runner **deletes the
floppy OS9Boot and clears DD.BT/DD.BSZ**, eliminating an RBF boot-file fallback.
It then requires the existing `mdir`, directory, text, copy/compare, and
working/execution-directory checks to complete and verifies unchanged FAT32
media. `MAME_VIDEO=/absolute/path/boot.avi` records the run with `-nothrottle`.

The floppy still supplies the initial kernel track, `/dd`, commands, and
saved test results. This proves loading OS9Boot from FAT32; it does not claim
a floppy-free ROM/bootstrap path or a FAT32 root system disk.

## FAT32 as the read-only system disk

`recipes/coco3/fat_root_mame_test` takes the next step: `/dd`, `/dd/cmds`,
`sysgo`, `startup`, selected `/dd/sys` files, and `OS9Boot` all reside on the
external FAT32 volume. Build it with:

```
make -C recipes/coco3/fat_root_mame_test prepare PYTHON=/path/to/python \
  LANGUAGES=/path/to/nitros9-languages
make -C recipes/coco3/fat_root_mame_test check PYTHON=/path/to/python \
  LANGUAGES=/path/to/nitros9-languages MAME_ROMPATH=/path/to/mame/roms
```

The outputs are `bootstrap.dsk` and `.fat-root/fat32-root.vhd`. Mount them as
MAME `-flop1` and `-hard1`, then enter `DOS`. The floppy contains only the
initial kernel track and empty formatting structures: no OS9Boot, SysGo,
commands, or startup file. The Boot module remains exactly 464 bytes.

The descriptor template accepts `-DDD=1` to name the FAT32 device `dd`; without
that option it still produces the byte-identical `pc0` descriptor. The root
boot includes `pcf`, `blkdrv`, `llcocovhd`, and this `dd` descriptor. It omits
RBF, rb1773, and floppy descriptors entirely. SysGo, shell and GrfDrv are not
resident boot modules: OS-9 loads them as ordinary FAT32 files. SysGo selects
`/dd` and `/dd/cmds`, executes the FAT32 startup script, and starts the normal
interactive shell. The script runs `mdir` first.

The test uses the existing 8.3 lookup and read/execute support; no FAT32 write
support is implied. Startup must not rely on creating files on `/dd`. The
included command set is the minimal demonstration set (`mdir`, `dir`, `list`,
`copy`, `cmp`, GrfDrv and the Shell+ module group), not a complete distribution.
The host image builder copies an explicitly staged 8.3 system tree and rejects
long path components rather than silently creating inaccessible long names.
The existing RBF-specific `pwd`/`pxd` utilities assume disk-wide directory IDs
and are not included; use `dir` / `dir -x` for this demonstration. Working and
execution-directory changes themselves are supported and tested.

`scripts/fat32-root-mame.py` verifies the boot-module set and records each
required file's FAT data records. Passive MAME Lua taps observe VHD reads and
OS-9 console writes/F$PErr calls without modifying guest memory. Verification
requires startup completion before the interactive shell banner, complete
VHD reads of SysGo/shell/GrfDrv and every test command, correct text and binary
comparison output, relative traversal and execution-directory listings, and
only the expected write-mode rejection. The runner ejects the floppy after
startup and before interactive checks; both media hashes must remain unchanged.
The console, VHD record trace and `result.json` are saved under `.fat-root/`.

Add `MAME_VIDEO=/absolute/path/fat32-root.avi` to `check` for an unthrottled,
80-column recording. The same `pyfatfs`, `setuptools<81`, MAME ROMs and tools
used by the earlier boot test are required. The memory taps use MAME's
[Lua address-space API](https://docs.mamedev.org/luascript/ref-mem.html), and
floppy ejection uses the
[image-device API](https://docs.mamedev.org/luascript/ref-devices.html).


## Writable pcf system disk and utility guards

`recipes/coco3/pcf_write_mame_test` enables writes and supplies both `/dd` and
`/pc0` on the external FAT32 image. The runtime file-manager name is `pcf`,
and its device type is `DT.pcf`. Regular files advertise execute access;
FAT32 has no OS-9 execute bit to enforce. The OS-9 loader validates modules.
FAT read-only attributes and backend write protection remain enforced.

```
make -C recipes/coco3/pcf_write_mame_test check PYTHON=/path/to/python \
  LANGUAGES=/path/to/nitros9-languages MAME_ROMPATH=/path/to/mame/roms \
  MAME_VIDEO=/absolute/path/pcf-write.avi
/sbin/fsck_msdos -n recipes/coco3/pcf_write_mame_test/.fat-root/media.vhd
```

The 80-column test runs `mdir` at startup, ejects the bootstrap floppy, then
creates and appends text, copies and compares a fragmented binary file,
deletes a copy, and creates a file in an existing subdirectory. Shell+
append syntax is `echo SECOND>+/pc0/new.txt`. The runner independently
reopens the resulting image and verifies exact file contents and deletion.

`attr`, `dcheck`, `pxd`, and `pwd` check the device type before interpreting
RBF metadata. On pcf they print `rbf only` and return E$BTyp (249). The MAME
run requires exactly four such rejections and monitors VHD writes throughout
the rejection sequence, requiring none. These utilities remain RBF-specific;
`dir` uses the portable SS.ReadDir interface.

`LWASM=lwasm.orig python3 scripts/test-pcf-write.py` also exercises assembled
Level 1 and Level 2 pcf/blkdrv/VHD code: sector-crossing writes, WriteLn,
zero-filled seek gaps, truncate/extend, reopen, deletion, directory growth,
and FAT mirrors. Writes are not transactional: interruption or a media error
partway through metadata updates may require filesystem repair. Initial write
support is for short-name files; mkdir/rmdir, rename, and LFN mutation remain
outside this implementation.

### Multi-process sharing checks

The writable MAME recipe also runs `pcfshare`, built from
`scripts/fixtures/pcfshare.asm`. Its parent holds a file open while 13 children
are forked and waited for in turn. These are real OS-9 processes with separate
opens, not simulated process IDs. The checks cover:

- Concurrent readers through `/dd` and `/pc0`, with independent read positions.
- Writer and delete rejection while a reader holds the file (`E$Share`).
- Reader, writer, and delete rejection while a writer holds the file.
- Access to a different file while the first file has a writer.
- Exclusion surviving closure of one duplicated path until its final close.
- Successful access after close and after a child exits with a path still open.
- Successful deletion after all references close.

The parent also requires `SS.Lock` to return `E$UnkSvc`: record locking is not
implemented. The runner requires the success marker, checks every child's exit
status through the test program, and verifies that both temporary files were
deleted. This validates sharing rules and cleanup across the two aliases; it
is not a stress test of arbitrary scheduler interleavings or interrupted I/O.

See [the pcf size audit](pcf-size.md) for the measured section breakdown and
behavior-preserving size reductions.

## Known legacy test limitation

The `fat_mame_test` and `fat_boot_mame_test` recipes retain RBF/floppy `/dd`
alongside pcf. Their latest combined-stack MAME regressions did not complete;
a diagnostic late-load attempt also encountered `E$NoRAM`. System-memory
pressure in these configurations remains unresolved. Do not treat these older
recipes as passing verification for the writable implementation. The validated
system-disk recipes are `fat_root_mame_test` and `pcf_write_mame_test`, which
keep `/dd` on FAT32 and omit RBF/floppy drivers from OS9Boot.
