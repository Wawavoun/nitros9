# Local floppy OS, read-only sparse FAT32 fixture through the real FAT/BlkDev stack.
override NITROS9DIR := $(abspath ../../..)
LEVEL = 2
TERM_COLS = 32
RECIPE = coco3_fat_mame_test
STARTUP =
CMDS_BASE = grfdrv shell utilpak1 cmp
BOOTMODS_EXTRA = fat blkdev llfatfixture fat0
RECIPE_DEPS = fatauto
RECIPE_INSTALL = $(CPL) fatauto $(1),fatauto
include ../coco3.mak
vpath %.asm $(NITROS9DIR)/level1/coco1/modules
PYTHON ?= python3
MAME_BINARY ?= mame
MAME_ROMPATH ?= $(HOME)/Documents/Resources/Computing/mame/roms
TEST_SECONDS ?= 400
MAME_VIDEO ?=

$(MODDIR)/fatfixture-data.asm: $(NITROS9DIR)/scripts/test-fat32.py $(NITROS9DIR)/scripts/fixtures/llfatfixture.asm | $(MODDIR)
	$(PYTHON) $(NITROS9DIR)/scripts/test-fat32.py --fixture-directory $(MODDIR)
$(MODDIR)/llfatfixture: $(MODDIR)/fatfixture-data.asm
	$(AS) $(AFLAGS) -I$(MODDIR) $(MODDIR)/llfatfixture.asm $(ASOUT)$@
$(MODDIR)/fat: $(DEFSDIR)/blkdev.d $(DEFSDIR)/fat32.d
$(MODDIR)/blkdev: $(DEFSDIR)/blkdev.d
$(MODDIR)/fat0: fatdesc.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DFATFixture=1 -DFATBase=2048 -DFATLength=70000 -DFATPort=0
check: $(DSKIMAGE)
	$(PYTHON) $(NITROS9DIR)/scripts/fat32-mame.py --disk $(DSKIMAGE) --mame "$(MAME_BINARY)" --rompath "$(MAME_ROMPATH)" --seconds $(TEST_SECONDS) $(if $(MAME_VIDEO),--video "$(MAME_VIDEO)")
.PHONY: check
