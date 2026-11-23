# EC-6809 V6 build recipe (NitrOS-9 Level 2, 6809).
#
# For the V6 CPU board: 8 KB DAT blocks, 32 tasks, DAT written at
# $FF00 + 8 x task + slot, task register $FE00 with bit 5 ROMOFF (RAM at
# $F000-$FEFF for the kernel). See level2/ec6809/defs/ec6809_l2.d and
# EC6809-V6/EC6809_New_Cpu_V6/CPU_board_V6_DAT_memo.txt.
# The Level 1 recipe (../ec6809) is separate and unchanged.
#
# Products:
#
#   bootrom   4 KB ROM image for $F000-$FFFF: one 4 KB bank of the CPU
#             board EPROM (A12/A13 jumpers). Loads OS9Boot from the SD
#             card and starts krn (level2/ec6809/modules/rom_ec6809.asm).
#   bootfile  OS9Boot: krnp2 init ioman drivers clock shell, padded at its
#             start so it ends at $E000, then a $1000 gap (the I/O page)
#             and krn ($F00 bytes) for the kernel window $F000-$FEFF.
#   $(DSKIMAGE)  disk image with OS9Boot (os9 gen), CMDS, SYS, DEFS and
#             startup, 65536 sectors (16 MB)
#   $(SDIMAGE)   the same disk laid out for the SD card: sector N in the
#             first half of block N. Write it to the whole card with dd.
#
# The I/O board EPROM part (io_eprom_nos9.bin) is the one of the Level 1
# recipe: both levels use it the same way.
# BOOTCS picks the boot card and /DD: 0 = CS0, 1 = CS1.
#
# Sources: level2/ec6809 first, then level1/ec6809 (rbec6809spi,
# clock2_ec6809rtc, init, sysgo, sc6850, term_sc6850, rbdesc), then the
# generic trees. level1/ec6809/modules also holds the Level 1 krn and
# clock: krn has an explicit rule below, and the Level 2 clock is in
# level2/ec6809/modules, which is searched first.

PORT ?= ec6809
RECIPE ?= ec6809_l2
CPU ?= 6809
LEVEL = 2
MACHINE ?= EC-6809 V6
MODDIR = .mods
include ../rules.mak

# Assembler search. level2/ec6809/defs comes before level1/ec6809/defs so
# that level1/cmds/defsfile ("use ../defsfile") resolves to the Level 2
# port defsfile; level1/ec6809/defs then gives ec6809.d.
AFLAGS += -I. -I$(L2PD) -I$(L2PD)/defs -I$(L2PMD) -I$(L2MD) -I$(L2MD)/kernel
AFLAGS += -I$(L1PMD) -I$(L1MD) -I$(L1MD)/kernel -I$(L1PD)/defs
AFLAGS += $(AFLAGS_EXTRA)

ifeq ($(CPU),6309)
  $(error the EC-6809 V6 Level 2 build is for the 6809 only)
endif
NOS9_LIB = libnos96809l2.a
LIB_NAMES = $(NOS9_LIB) libnet.a libalib.a
LFLAGS += -L$(LIBDIR) -lnos96809l2 -lnet -lalib
LFLAGS += $(LFLAGS_EXTRA)

DISTRONAME = NOS9_$(CPU)_L$(LEVEL)
DISTROVER  = $(DISTRONAME)_$(NITROS9VER)_$(RECIPE)
DSKIMAGE  ?= $(DISTROVER).dsk
SDIMAGE   ?= $(DISTROVER).sd
DSKSECT   ?= 65536
BOOTCS    ?= 0
AFLAGS    += -DBOOTCS=$(BOOTCS)

# Modules
KERNEL   = krn krnp2
SYSMODS  = ioman init sysgo
CLOCKS   = clock clock2_ec6809rtc
RBF      = rbf.mn rbec6809spi.dr ddh0.dd h0.dd h1.dd
SCF      = scf.mn sc6850.dr term_sc6850.dt nil.dr nil.dd
PIPE     = pipeman.mn piper.dr pipe.dd
MODULES  = $(KERNEL) $(SYSMODS) $(CLOCKS) $(RBF) $(SCF) $(PIPE)

# OS9Boot below $E000 (krn goes in the kernel window, see bootfile)
BOOTMODS = krnp2 init ioman $(RBF) $(SCF) $(PIPE) $(CLOCKS) sysgo shell

# Commands
CMDS = asm attr backup bawk binex build cmp copy \
	date dcheck debug ded deiniz del deldir devs dir dirsort disasm \
	display dmem dmode dsave dump echo edit error exbin format free \
	help ident iniz irqs link list load login makdir mdir megaread \
	merge mfree mmap modpatch more padrom park pmap proc procs printerr \
	prompt pwd pxd rename save setime sleep smap tee tmode touch tsmon \
	unlink verify xmode
# Ready-made command modules (third-party, no source) in level1/ec6809/cmds,
# shared with the Level 1 build: every file there without a source or text
# extension is copied as it is to /DD/CMDS, for example kermit.
BINCMDS := $(notdir $(filter-out %.asm %.a %.txt %.md %.lst,$(wildcard $(L1PCD)/*)))
CMDS += $(BINCMDS)

# BASIC09 comes from the sibling nitros9-languages checkout, when present.
# The same binaries run at Level 1 and Level 2. gfx/gfx2 are CoCo graphics
# packages and are left out.
ifneq ($(wildcard $(LANGUAGES)/basic09),)
vpath %.asm $(LANGUAGES)/basic09
AFLAGS += -I$(LANGUAGES)/basic09
BASIC09_CPU = 6809
CMDS += basic09 runb inkey syscall
endif

# Merged command packs added to /CMDS
CMDS_MERGED = shell utilpak1
CMDS_DISK = $(CMDS) $(CMDS_MERGED)

SHELLMODS = shellplus echo iniz link load save unlink
UTILPAK1  = attr copy date del deldir dir display list makdir mdir \
	merge mfree procs rename tmode unlink

# SYS directory
vpath %.hp $(L2D)/sys:$(L1D)/sys
HELPFILES = asm.hp attr.hp backup.hp binex.hp build.hp chd.hp chx.hp cmp.hp \
	copy.hp date.hp dcheck.hp debug.hp ded.hp deiniz.hp del.hp \
	deldir.hp devs.hp dir.hp dirsort.hp disasm.hp display.hp dmem.hp \
	dmode.hp dsave.hp dump.hp echo.hp edit.hp error.hp ex.hp exbin.hp \
	format.hp free.hp help.hp ident.hp iniz.hp irqs.hp link.hp list.hp \
	load.hp login.hp makdir.hp mdir.hp megaread.hp merge.hp mfree.hp \
	mmap.hp modpatch.hp padrom.hp park.hp pmap.hp proc.hp \
	procs.hp prompt.hp pwd.hp pxd.hp rename.hp save.hp setime.hp \
	setpr.hp shell.hp sleep.hp smap.hp tee.hp tmode.hp touch.hp \
	tsmon.hp unlink.hp verify.hp xmode.hp
SYSTEXT = $(L1D)/sys/errmsg $(L2D)/sys/motd $(L1D)/sys/password helpmsg

# DEFS directory.  Generated in .defs so the preprocessed defsfile cannot
# shadow the port defsfile through -I.
DEFDIR  = .defs
DEFOPTS = --preprocess -DLevel=2
DEFS    = os9.d rbf.d scf.d ec6809.d ec6809_l2.d

STARTUP = $(L2PD)/startup

all: banner libs bootrom $(DSKIMAGE) $(SDIMAGE)

banner:
	@$(ECHO) "************************************************************"
	@$(ECHO) "*"
	@$(ECHO) "*      NitrOS-9/$(CPU) Level $(LEVEL) $(MACHINE) ($(PORT))"
	@$(ECHO) "*"
	@$(ECHO) "************************************************************"

include ../libs.mak

modules: $(addprefix $(MODDIR)/,$(MODULES))

cmds: $(addprefix $(MODDIR)/,$(CMDS_DISK))

# Boot ROM: a raw 4 KB image for $F000-$FFFF.
bootrom: $(L2PMD)/rom_ec6809.asm
	$(ASROM) $(AFLAGS) $< -o$@ -lbootrom.lst
	@SIZE=$$(wc -c <$@) ; \
	if [ $$SIZE -ne 4096 ] ; then \
		echo "bootrom is $$SIZE bytes; it must be 4096" ; \
		rm -f $@ ; exit 1 ; \
	fi
	@ls -l $@

# krn is the Level 2 kernel, not the Level 1 krn of level1/ec6809/modules.
# It is the whole kernel window: $F00 bytes, register stack and vector
# table included (the module pads itself to put them at $FEDF/$FEEE).
$(MODDIR)/krn: $(L2MD)/kernel/krn.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@
	@SIZE=$$(wc -c <$@) ; \
	if [ $$SIZE -ne 3840 ] ; then \
		echo "krn is $$SIZE bytes; it must be 3840 (\$$F00)" ; \
		rm -f $@ ; exit 1 ; \
	fi

# OS9Boot: the modules padded at their start to whole pages so that they
# end at $E000, the $1000 gap of the I/O page, then krn.
KRN_GAP  = 0x1000
BT_LOW_MAX = 0xA000

bootfile: $(addprefix $(MODDIR)/,$(BOOTMODS) krn)
	$(MERGE) $(addprefix $(MODDIR)/,$(BOOTMODS)) > $@
	$(PADROM) -b $$(( ($$(wc -c <$@) + 255) / 256 * 256 )) $@
	@SIZE=$$(wc -c <$@) ; \
	if [ $$SIZE -gt $$(($(BT_LOW_MAX))) ] ; then \
		echo "the modules are $$SIZE bytes; they must fit $$(($(BT_LOW_MAX))) ($$4000-$$DFFF)" ; \
		rm -f $@ ; exit 1 ; \
	fi
	$(PADROM) $$(( $$(wc -c <$@) + $(KRN_GAP) )) $@
	cat $(MODDIR)/krn >> $@
	@ls -l $@

helpmsg: $(HELPFILES)
	$(MERGE) $^ > $@

$(DEFDIR):
	@mkdir -p $@

$(DEFDIR)/os9.d: $(DEFSDIR)/os9.d | $(DEFDIR)
	$(AS) $(DEFOPTS) -DOS9.D=0 $< > $@
	$(DROP_EXTRA_SPACES) $@

$(DEFDIR)/rbf.d: $(DEFSDIR)/rbf.d | $(DEFDIR)
	$(AS) $(DEFOPTS) -DRBF.D=0 $< > $@
	$(DROP_EXTRA_SPACES) $@

$(DEFDIR)/scf.d: $(DEFSDIR)/scf.d | $(DEFDIR)
	$(AS) $(DEFOPTS) -DSCF.D=0 $< > $@
	$(DROP_EXTRA_SPACES) $@

$(DEFDIR)/ec6809.d: $(L1PD)/defs/ec6809.d | $(DEFDIR)
	$(AS) $(DEFOPTS) -DEC6809.D=0 $< > $@
	$(DROP_EXTRA_SPACES) $@

$(DEFDIR)/ec6809_l2.d: $(L2PD)/defs/ec6809_l2.d | $(DEFDIR)
	$(AS) $(DEFOPTS) -DEC6809_L2.D=0 $< > $@
	$(DROP_EXTRA_SPACES) $@

$(DSKIMAGE): bootfile helpmsg $(addprefix $(DEFDIR)/,$(DEFS)) \
		$(addprefix $(MODDIR)/,$(CMDS_DISK)) $(SYSTEXT) $(STARTUP)
	$(RM) $@
	$(OS9FORMAT) -q -l$(DSKSECT) $@ -n"NitrOS-9/$(CPU) Level $(LEVEL)"
	$(OS9GEN) $@ -b=bootfile
	$(MAKDIR) $@,CMDS
	$(MAKDIR) $@,SYS
	$(MAKDIR) $@,DEFS
	$(OS9COPY) $(addprefix $(MODDIR)/,$(CMDS_DISK)) $@,CMDS
	$(OS9ATTR_EXEC) $(foreach file,$(CMDS_DISK),$@,CMDS/$(file))
	$(CPL) $(SYSTEXT) $@,SYS
	$(OS9ATTR_TEXT) $(foreach file,$(notdir $(SYSTEXT)),$@,SYS/$(file))
	$(CPL) $(addprefix $(DEFDIR)/,$(DEFS)) $@,DEFS
	$(OS9ATTR_TEXT) $(foreach file,$(DEFS),$@,DEFS/$(file))
	$(CPL) $(STARTUP) $@,startup
	$(OS9ATTR_TEXT) $@,startup

$(SDIMAGE): $(DSKIMAGE) ../ec6809/sdimage.py
	python3 ../ec6809/sdimage.py $< $@

# Module rules
$(MODDIR)/ddh0.dd: rbdesc.asm | $(MODDIR)
	$(AS) $< $(ASOUT)$@ $(AFLAGS) -DDD=1 -DDNum=$(BOOTCS)

$(MODDIR)/h0.dd: rbdesc.asm | $(MODDIR)
	$(AS) $< $(ASOUT)$@ $(AFLAGS) -DDNum=0

$(MODDIR)/h1.dd: rbdesc.asm | $(MODDIR)
	$(AS) $< $(ASOUT)$@ $(AFLAGS) -DDNum=1

$(MODDIR)/term_sc6850.dt: term_sc6850.asm | $(MODDIR)
	$(AS) $< $(ASOUT)$@ $(AFLAGS) -DHwBASE=0xEEA0

# Lean /Nil pseudo-device (NIL selects /Nil over the /Zero default)
$(MODDIR)/nil.dr: nzdrv.asm | $(MODDIR)
	$(AS) $(AFLAGS) -DNIL=1 $(ASOUT)$@ $<
$(MODDIR)/nil.dd: nzdesc.asm | $(MODDIR)
	$(AS) $(AFLAGS) -DNIL=1 $(ASOUT)$@ $<

# Command rules
$(MODDIR)/pwd: pd.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DPWD=1

$(MODDIR)/pxd: pd.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DPXD=1

$(MODDIR)/xmode: xmode.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DXMODE=1

$(MODDIR)/tmode: xmode.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DTMODE=1

# The Level 2 shell is a merged shellplus pack
$(MODDIR)/shell: $(addprefix $(MODDIR)/,$(SHELLMODS)) | $(MODDIR)
	$(MERGE) $(addprefix $(MODDIR)/,$(SHELLMODS)) >$@
$(MODDIR)/utilpak1: $(addprefix $(MODDIR)/,$(UTILPAK1)) | $(MODDIR)
	$(MERGE) $(addprefix $(MODDIR)/,$(UTILPAK1)) >$@

$(addprefix $(MODDIR)/,$(BINCMDS)): $(MODDIR)/%: $(L1PCD)/% | $(MODDIR)
	$(CP) $< $@

$(MODDIR)/basic09: $(LANGUAGES)/basic09/basic09_$(BASIC09_CPU) | $(MODDIR)
	$(CP) $< $@

$(MODDIR)/runb: $(LANGUAGES)/basic09/runb_$(BASIC09_CPU) | $(MODDIR)
	$(CP) $< $@

# The languages makefiles include $(NITROS9DIR)/rules.mak: pass it down.
$(LANGUAGES)/basic09/basic09_$(BASIC09_CPU) $(LANGUAGES)/basic09/runb_$(BASIC09_CPU):
	$(MAKE) -C $(dir $@) $(notdir $@) NITROS9DIR=$(NITROS9DIR)

info:
	@$(ECHO) "*** NitrOS-9/$(CPU) Level $(LEVEL) for the $(MACHINE) ($(PORT)) ***"
	@$(ECHO) "Bootrom:   bootrom (4 KB, \$$F000-\$$FFFF)"
	@$(ECHO) "Bootfile:  bootfile"
	@$(ECHO) "Disk:      $(DSKIMAGE)"
	@$(ECHO) "SD card:   $(SDIMAGE) (boot card CS$(BOOTCS))"

clean:
	$(RM) bootrom bootrom.lst bootfile buildinfo helpmsg *.dsk *.sd *.list *.map
	-rm -rf $(OBJDIR) $(LIBDIR) $(MODDIR) $(DEFDIR)

.PHONY: all banner modules cmds info clean libs
