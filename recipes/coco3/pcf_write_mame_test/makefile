override RECIPE := coco3_pcf_write_mame_test
override BOOTMODS_EXTRA := pcf blkdrv llcocovhd dd_fat pc0
override CMDS_BASE := grfdrv shell mdir dir list copy cmp makdir del deldir attr dcheck pwd pxd pcfshare pcfrmdir
ROOT_TEST_FLAGS = --write-test
FAT_WRITE = 1
TEST_SECONDS = 420
include ../fat_root_mame_test/makefile

$(MODDIR)/pcfshare: $(NITROS9DIR)/scripts/fixtures/pcfshare.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@

$(addprefix $(MODDIR)/,attr dcheck pwd pxd deldir): $(NITROS9DIR)/level1/cmds/rbfguard.asm

$(MODDIR)/pcfrmdir: $(NITROS9DIR)/scripts/fixtures/pcfrmdir.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@
