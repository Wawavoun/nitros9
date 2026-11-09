# EC-6809 build recipe (NitrOS-9 Level 1, 6809).
#
# It shares no port file with any other recipe.  Products:
#
#   bootrom   8 KB ROM image: krn krnp2 init boot_ec6809sd, padded to 3840
#             bytes, then the REL module; padded at the start to 8192
#   bootfile  OS9Boot: ioman sysgo clocks SCF RBF pio shell_21
#   $(DSKIMAGE)  disk image with OS9Boot, CMDS, SYS, DEFS and startup
#
# Sources come from level1/ec6809 first (vpath), then the generic
# level1/modules and level1/cmds trees.  A file in level1/ec6809/modules
# replaces the generic module of the same name for this build only:
# krn, clock, init, sysgo, sc6850 and term_sc6850 are EC-6809 copies.

PORT ?= ec6809
RECIPE ?= ec6809
CPU ?= 6809
LEVEL = 1
MACHINE ?= EC-6809
MODDIR = .mods
include ../rules.mak

# Assembler search: the recipe dir, the port dir (port defsfile, which sets
# Level), the port defs dir (so level1/cmds/defsfile's "use ../defsfile"
# resolves to the port defsfile), then the generic module and kernel dirs.
AFLAGS += -I. -I$(L1PD) -I$(L1PD)/defs -I$(L1PMD) -I$(L1MD) -I$(L1MD)/kernel
AFLAGS += $(AFLAGS_EXTRA)

LIB_NAMES = libnet.a libatari.a libalib.a
LFLAGS += -L$(LIBDIR) -lnet -latari -lalib
LFLAGS += $(LFLAGS_EXTRA)

TELNET_PORT = 6801
HTTPD_PORT = 8801

WHICHSHELL = shell_21

DISTRONAME = NOS9_$(CPU)_L$(LEVEL)
DISTROVER  = $(DISTRONAME)_$(NITROS9VER)_$(PORT)
DSKIMAGE  ?= $(DISTROVER).dsk

# Modules
BOOTERS  = rel boot_ec6809sd
KERNEL   = krn krnp2
SYSMODS  = ioman init sysgo sysgo_rom pio.sb
CLOCKS   = clock clock2_ec6809sd
RBF      = rbf.mn rbec6809sd.dr ddh0.dd h0.dd h1.dd h2.dd h3.dd
SCF      = scf.mn vrn.dr nil.dd sc6850.dr term_sc6850.dt
PIPE     = pipeman.mn piper.dr pipe.dd
MODULES  = $(BOOTERS) $(KERNEL) $(SYSMODS) $(CLOCKS) $(RBF) $(SCF) $(PIPE)

BOOTROM  = krn krnp2 init boot_ec6809sd
BOOTFILE = ioman sysgo clock clock2_ec6809sd scf.mn sc6850.dr term_sc6850.dt \
           rbf.mn rbec6809sd.dr ddh0.dd h1.dd h2.dd h3.dd pio.sb $(WHICHSHELL)

# Commands
CMDS = asm attr backup bawk binex build calldbg cmp copy cputype \
	date dcheck debug ded deiniz del deldir devs dir dirsort disasm \
	display dmode dsave dump echo edit error exbin format \
	free help ident iniz irqs link list load login makdir \
	megaread mdir merge mfree more os9gen padrom park printerr procs prompt pwd pxd \
	rename save setime shellplus shell_21 sleep \
	tee tmode touch tsmon tuneport unlink verify xmode

# BASIC09 comes from the sibling nitros9-languages checkout, when present.
ifneq ($(wildcard $(LANGUAGES)/basic09),)
vpath %.asm $(LANGUAGES)/basic09
AFLAGS += -I$(LANGUAGES)/basic09
BASIC09_CPU = $(if $(filter 6309,$(CPU)),6309,6809)
CMDS += basic09 runb gfx inkey syscall
endif

# SYS directory
vpath %.hp $(L1D)/sys
HELPFILES = asm.hp attr.hp backup.hp binex.hp build.hp chd.hp \
	chx.hp cmp.hp cobbler.hp config.hp copy.hp cputype.hp date.hp \
	dcheck.hp debug.hp ded.hp deiniz.hp del.hp deldir.hp devs.hp \
	dir.hp dirsort.hp disasm.hp display.hp dmode.hp dsave.hp dump.hp echo.hp \
	edit.hp error.hp ex.hp exbin.hp format.hp free.hp gfx.hp \
	help.hp ident.hp iniz.hp inkey.hp irqs.hp kill.hp link.hp \
	list.hp load.hp login.hp makdir.hp \
	mdir.hp megaread.hp merge.hp minted.hp mpi.hp mfree.hp os9gen.hp \
	padrom.hp park.hp procs.hp prompt.hp pwd.hp pxd.hp \
	rename.hp save.hp setime.hp \
	setpr.hp shell.hp sleep.hp tee.hp tmode.hp touch.hp tsmon.hp \
	tuneport.hp unlink.hp verify.hp xmode.hp
SYSTEXT = $(L1D)/sys/errmsg $(L1D)/sys/motd $(L1D)/sys/password \
	inetd.conf helpmsg

# DEFS directory.  Generated in .defs so the preprocessed defsfile cannot
# shadow the port defsfile through -I.
DEFDIR  = .defs
DEFOPTS = --preprocess -DLevel=1
DEFS    = defsfile os9.d rbf.d scf.d ec6809.d

STARTUP = $(L1PD)/startup

all: banner libs bootrom $(DSKIMAGE)

banner:
	@$(ECHO) "************************************************************"
	@$(ECHO) "*"
	@$(ECHO) "*      NitrOS-9/$(CPU) Level $(LEVEL) $(MACHINE) ($(PORT))"
	@$(ECHO) "*"
	@$(ECHO) "************************************************************"

include ../libs.mak

modules: $(addprefix $(MODDIR)/,$(MODULES))

cmds: $(addprefix $(MODDIR)/,$(CMDS))

bootrom: $(addprefix $(MODDIR)/,$(BOOTROM) rel)
	$(MERGE) $(addprefix $(MODDIR)/,$(BOOTROM)) > bootrom_p1
	$(PADROM) 3840 bootrom_p1
	$(MERGE) bootrom_p1 $(MODDIR)/rel > $@
	$(PADROM) 8192 -b $@
	$(RM) bootrom_p1
	@ls -l $@

bootfile: $(addprefix $(MODDIR)/,$(BOOTFILE))
	$(MERGE) $(addprefix $(MODDIR)/,$(BOOTFILE)) > $@

helpmsg: $(HELPFILES)
	$(MERGE) $^ > $@

inetd.conf: $(L1D)/sys/inetd.conf
	sed -e 's/%TELNET_PORT%/$(TELNET_PORT)/' \
	    -e 's/%HTTPD_PORT%/$(HTTPD_PORT)/' $< > $@

$(DEFDIR):
	@mkdir -p $@

$(DEFDIR)/defsfile: $(L1PD)/defs/defsfile.asm | $(DEFDIR)
	$(AS) $(DEFOPTS) $< > $@
	$(DROP_EXTRA_SPACES) $@

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

$(DSKIMAGE): bootfile helpmsg inetd.conf $(addprefix $(DEFDIR)/,$(DEFS)) \
		$(addprefix $(MODDIR)/,$(CMDS)) $(SYSTEXT) $(STARTUP)
	$(RM) $@
	$(OS9FORMAT_DW) -e -q $@ -n"NitrOS-9/$(CPU) Level $(LEVEL)"
	$(OS9GEN) $@ -b=bootfile
	$(MAKDIR) $@,CMDS
	$(MAKDIR) $@,SYS
	$(MAKDIR) $@,DEFS
	$(OS9COPY) $(addprefix $(MODDIR)/,$(CMDS)) $@,CMDS
	$(OS9ATTR_EXEC) $(foreach file,$(CMDS),$@,CMDS/$(file))
	$(OS9RENAME) $@,CMDS/$(WHICHSHELL) shell
	$(CPL) $(SYSTEXT) $@,SYS
	$(OS9ATTR_TEXT) $(foreach file,$(notdir $(SYSTEXT)),$@,SYS/$(file))
	$(CPL) $(addprefix $(DEFDIR)/,$(DEFS)) $@,DEFS
	$(OS9ATTR_TEXT) $(foreach file,$(DEFS),$@,DEFS/$(file))
	$(CPL) $(STARTUP) $@,startup
	$(OS9ATTR_TEXT) $@,startup

# Module rules
$(MODDIR)/sysgo_rom: sysgo.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DROM=1

$(MODDIR)/ddh0.dd: rbdesc.asm | $(MODDIR)
	$(AS) $< $(ASOUT)$@ $(AFLAGS) -DDD=1 -DDNum=0

$(MODDIR)/h0.dd: rbdesc.asm | $(MODDIR)
	$(AS) $< $(ASOUT)$@ $(AFLAGS) -DDNum=0

$(MODDIR)/h1.dd: rbdesc.asm | $(MODDIR)
	$(AS) $< $(ASOUT)$@ $(AFLAGS) -DDNum=1

$(MODDIR)/h2.dd: rbdesc.asm | $(MODDIR)
	$(AS) $< $(ASOUT)$@ $(AFLAGS) -DDNum=2

$(MODDIR)/h3.dd: rbdesc.asm | $(MODDIR)
	$(AS) $< $(ASOUT)$@ $(AFLAGS) -DDNum=3

$(MODDIR)/term_sc6850.dt: term_sc6850.asm | $(MODDIR)
	$(AS) $< $(ASOUT)$@ $(AFLAGS) -DHwBASE=0xE010

# Command rules
$(MODDIR)/pwd: pd.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DPWD=1

$(MODDIR)/pxd: pd.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DPXD=1

$(MODDIR)/xmode: xmode.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DXMODE=1

$(MODDIR)/tmode: xmode.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@ -DTMODE=1

$(MODDIR)/basic09: $(LANGUAGES)/basic09/basic09_$(BASIC09_CPU) | $(MODDIR)
	$(CP) $< $@

$(MODDIR)/runb: $(LANGUAGES)/basic09/runb_$(BASIC09_CPU) | $(MODDIR)
	$(CP) $< $@

$(LANGUAGES)/basic09/basic09_$(BASIC09_CPU) $(LANGUAGES)/basic09/runb_$(BASIC09_CPU):
	$(MAKE) -C $(dir $@) $(notdir $@)

info:
	@$(ECHO) "*** NitrOS-9/$(CPU) Level $(LEVEL) for the $(MACHINE) ($(PORT)) ***"
	@$(ECHO) "Bootrom:   bootrom"
	@$(ECHO) "Bootfile:  bootfile"
	@$(ECHO) "Disk:      $(DSKIMAGE)"

clean:
	$(RM) bootrom bootrom_p1 bootfile buildinfo helpmsg inetd.conf *.dsk *.list *.map
	-rm -rf $(OBJDIR) $(LIBDIR) $(MODDIR) $(DEFDIR)

.PHONY: all banner modules cmds info clean libs
