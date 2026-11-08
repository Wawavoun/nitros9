override RECIPE := coco3_pcf_write_mame_test
override BOOTMODS_EXTRA := pcf blkdrv llcocovhd dd_fat pc0
override CMDS_BASE := grfdrv shell mdir dir list copy cmp del attr dcheck pwd pxd pcfshare
ROOT_TEST_FLAGS = --write-test
FAT_WRITE = 1
include ../fat_root_mame_test/makefile

$(MODDIR)/pcfshare: $(NITROS9DIR)/scripts/fixtures/pcfshare.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@
