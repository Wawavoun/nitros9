# Running the PCF and RBF regressions locally

From the repository root, these recipe targets build their own disposable test
images. They do not use an attached physical disk and do not record video.
MAME runs a 512K CoCo 3 with an 80-column screen and `-nothrottle`.

```sh
# Watch both integrations: FAT32 (including randomized operations), then RBF.
make -C recipes/coco3/pcf_write_mame_test demo-all

# Watch either integration by itself.
make -C recipes/coco3/pcf_write_mame_test demo
make -C recipes/coco3/rbf_mame_test demo

# Run both integrations and the deeper CPU stress tests without MAME windows.
make -C recipes/coco3/pcf_write_mame_test check-all
```

Dependencies: the normal NitrOS-9 build tools (`lwasm`, `lwlink`, `os9`, and the
languages checkout), MAME with legally obtained CoCo 3/Disk BASIC ROMs, and a
Python 3.11+ environment containing `pyfatfs` and `MC6809`. On this workstation:

```sh
make -C recipes/coco3/pcf_write_mame_test demo-all \
  LANGUAGES=/Users/boisy/Projects/coco-shelf/nitros9-languages \
  PYTHON=/private/tmp/blkdev-venv/bin/python
```

`MAME_BINARY` and `MAME_ROMPATH` override the executable and ROM directory.
`FAT_CHECK` selects the read-only FAT checker (default `/sbin/fsck_msdos`;
on Linux, use `FAT_CHECK=fsck.fat`). It is required for FAT32 test success.
The default ROM directory is `~/Documents/Resources/Computing/mame/roms`.
Close a MAME window early to abort that run; incomplete runs fail verification.
Each finished window closes automatically, and the terminal prints PASS only
after the host-side checks succeed. RBF deliberately waits longer between
commands because keys sent during floppy HALT transfers can be lost.

## Randomized coverage and replay

The visible FAT32 run generates 120 operations using a recorded seed. It
creates nested directories, creates/appends/copies/deletes files, and removes
empty directories. A separate host directory receives the equivalent operations.
After MAME exits, PyFatFS independently compares every surviving name, directory,
and file byte with that host reference. Unexpected guest errors fail the run.
A second cold boot uses the written image; its hash must remain unchanged and
the host comparison must still pass. Each boot is followed by a mandatory
`fsck_msdos -n` integrity check, with its full output saved in `fsck.log`.
A nonzero checker result fails the target; the checker must leave the image
hash unchanged. The CPU suite applies the same check to each final image.

```sh
make -C recipes/coco3/pcf_write_mame_test demo RANDOM_SEED=42 RANDOM_STEPS=120
make -C recipes/coco3/pcf_write_mame_test check-random \
  RANDOM_CPU_SEEDS="17 20261108" RANDOM_CPU_STEPS=150
```

`check-random` executes the assembled pcf/blkdrv/VHD code on MC6809 for Levels
1 and 2. It adds binary overwrites, append, truncation/extension, sector-boundary
writes, and zero-filled seek gaps. Every surviving changed file is read back
through pcf and compared with a real host file. Every 25 operations, and at the
end, an independently opened FAT32 image is compared with the entire host
reference and both FAT copies are compared. This tests file-manager code with
mocked kernel services; it does not replace the real OS-9 MAME integration.

## Evidence saved by the targets

Paths below are relative to each recipe directory:

| Recipe/output | Evidence |
| --- | --- |
| `pcf_write_mame_test/.fat-root/` | `result.json`, `screen.png`, `console.txt`, `errors.log`, `fsck.log`, disk read/write traces |
| `.fat-root/reference/` | Independently generated expected files and directories |
| `.fat-root/random-trace.json` | Seed and ordered guest operations |
| `.fat-root/random-verified.json` | Verified file sizes and SHA-256 hashes |
| `.fat-root/reopen/` | Cold-boot console, screenshot, and verification result |
| `pcf_write_mame_test/.random-cpu/` | Per-level/seed replay traces, host files, resulting images, and results |
| `rbf_mame_test/.rbf-test/` | RBF screenshot, console, `result.json`, `dcheck.log`, and written floppy |

The RBF run exercises listing and cancellation inside a subtree, recursive
removal of a three-level tree and empty sibling, regular-file deletion, and
preservation of an unrelated file. It verifies disk contents using host OS-9
Tools. `dcheck` reports the reserved 18-sector kernel track as allocated outside
the file structure; it is not an orphan introduced by directory deletion.

All images and screenshots are generated outputs. Re-running a target replaces
its previous evidence, so copy it elsewhere before starting another seed if
needed. A passing finite regression is not a proof for every input, concurrent
schedule, media failure, or hardware configuration. Real Wildbits hardware and
power-loss behavior still need separate validation.
