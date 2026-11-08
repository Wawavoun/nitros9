# pcf size audit

Current modules with directory creation/removal: **6,855 bytes (Level 2)**
and **6,844 bytes (Level 1)**. Directory creation added 254 bytes to each;
empty-directory removal and in-use checks add another 392/394 bytes. The optimization
breakdown below records the preceding files-only implementation.

Measured 6809 Level 2 OS-9 modules, including header and CRC. This compares
this audit's starting source with the branch, workspace-layout, and shared-decoder changes;
it does not compare against the older read-only implementation in git.
Section boundaries follow routine labels, so shared helpers are counted once.

| Section | Before | After | Saved |
|---|---:|---:|---:|
| Header, dispatch, errors, arithmetic | 265 | 224 | 41 |
| Driver calls and sector caches | 146 | 111 | 35 |
| Mount and geometry validation | 589 | 542 | 47 |
| Cluster traversal and cycle checks | 554 | 474 | 80 |
| Open/create setup and pathname parsing | 861 | 706 | 155 |
| Directory lookup and entry adoption | 372 | 320 | 52 |
| Read, ReadLn, directory records, path lifecycle | 745 | 638 | 107 |
| Status, SS.ReadDir, OS-9 metadata | 707 | 553 | 154 |
| Operation lock, sharing, write permissions | 450 | 399 | 51 |
| Write geometry, block I/O, FAT/FSInfo updates | 473 | 413 | 60 |
| Cluster allocation and freeing | 391 | 344 | 47 |
| Timestamps, directory updates, create/grow | 677 | 611 | 66 |
| Write, WriteLn, zero-filled gaps | 494 | 415 | 79 |
| Delete and file resizing | 442 | 394 | 48 |
| WriteLn terminator scan | 75 | 62 | 13 |
| Module CRC | 3 | 3 | 0 |
| **Total** | **7,244** | **6,209** | **1,035** |

## Changes applied

- Short branches/subroutine calls where the assembled displacement fits:
  **750 bytes saved** in Level 2 (7,244 → 6,494). All candidates were checked
  against Level 1/2 and 6809/6309 builds. The fixed three-byte entry table is
  unchanged. There are 426 changed source sites, including conditional code
  that is not emitted in every variant.
- Move `F.Val`, `F.Move`, and `F.Pos` to the beginning of the private path
  workspace: **201 additional bytes saved** (6,494 → 6,293). These fields now
  use compact indexed operands. No workspace fields or buffers were removed.
  Some other accesses became slightly larger; the figure is the net saving.

- Share ReadData/ReadFat cache filling: **21 additional bytes saved**
  (6,293 → 6,272). Each cache descriptor has a valid byte followed by its LBA;
  the common routine keeps Y as the OS-9 path descriptor during driver calls.
  Failed fills invalidate the affected cache and retain the original error.
- Share direct FAT-entry metadata decoding between SS.FD/SS.FDInf and
  SS.ReadDir: **63 additional bytes saved** (6,272 → 6,209). The portable
  record's name remains in place while metadata is written immediately after
  it. Removed the entry scratch copy and name/metadata save-and-restore loops.
  The unused 32-byte F.Meta field was removed; fixed buffer offsets and the
  2,048-byte workspace allocation remain unchanged.

Total Level 2 saving: **1,035 bytes (14.3%)**. The measured RBF module is 5,454
bytes, so pcf is now **755 bytes (13.8%) larger**, down from 1,790 bytes (32.8%).
Level 1 changed from 7,237 to 6,196 bytes. Both CPU assembly modes have the
same size for a given OS level. Per-open workspace remains **2,048 bytes**,
with data and FAT buffers still at offsets $400 and $600. `blkdrv`, backend
modules, descriptors, and workspace allocations are excluded from the table.

## Remaining opportunities

1. **Pathname handling.** Parsing and opening remain large sections. Any
   consolidation must preserve dot traversal, caller pathname consumption,
   error handling, and short-name creation rules.
2. **Workspace ordering.** More frequently accessed flags could be moved nearer
   the base. Measure the net instruction-size change: making one field cheaper
   can make another more expensive. Keep the fixed sector-buffer boundaries.
3. **Local control-flow layout.** There are still long branches whose destinations
   genuinely lie outside short range. Moving error exits nearer their callers
   may help, but duplicated exits cost bytes and increase maintenance work.

Do not reduce block addresses or file sizes to 24 bits, remove chain validation,
or drop sharing checks simply to match RBF's module size. No such changes were
made here. This audit addresses code size, not runtime memory reduction or a
performance benchmark.

## Reproducing the breakdown

Assemble with lwasm's `--symbol-dump=/tmp/pcf.sym`, then run:

```
python3 scripts/pcf-size.py /tmp/pcf.sym
python3 scripts/pcf-size.py /tmp/pcf-after.sym --before /tmp/pcf-before.sym
```

Use matching CPU and OS-level configurations for comparisons. The script
computes section lengths from the symbol offsets and accounts for the CRC.

## Validation

All four Level 1/2 × 6809/6309 variants assembled. The Level 1/2 read and write
CPU regression suites passed, including added tests for second-half data/FAT
read failures, invalidation and retry, byte-for-byte metadata equivalence across
SS.ReadDir and SS.FDInf, and full SS.FD clearing without caller-buffer overrun. The 6809 Level 2 writable-root MAME recipe passed
boot, startup, file operations, all five utilities' E$BTyp (249) rejections (deldir through both device aliases), 13 parent/child
sharing checks, independent reader positions, and unsupported SS.Lock reporting.
The post-test image passed `fsck_msdos -n`. The recorded video was not changed.
