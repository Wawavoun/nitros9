                    ifne      EC6809_L2.D-1
EC6809_L2.D         set       1

********************************************************************
* ec6809_l2.d - NitrOS-9 Level 2 definitions for the EC-6809 V6 CPU board
*
* Used with ec6809.d (level1/ec6809/defs), which gives the I/O board,
* the I/O EPROM entries, the ACIA and the VIA.
*
* V6 CPU board (EC6809-V6/EC6809_New_Cpu_V6/CPU_board_V6_DAT_memo.txt):
*
*   $0000-$DFFF  slots 0-6  RAM through the DAT, 8 KB blocks
*   $E000-$EFFF  slot 7     I/O, not translated
*   $F000-$FEFF  slot 7     ROMOFF = 0: ROM
*                           ROMOFF = 1: RAM through the slot 7 entry; every
*                           task has KrnBlk there, so this is the kernel
*                           window, the same in every task
*   $FF00-$FFFF             reads: always ROM (vectors, ROM.xxx below)
*                           writes: DAT RAM, $FF00 + 8 x task + slot
*   $FE00        task register (write): bits 0-4 task, bit 5 ROMOFF.
*                With ROMOFF = 1 a write to $FE00 also writes the RAM
*                byte under it, so reading $FE00 gives the last value
*                written: krn keeps that byte free and reads it.
*
* The DAT RAM is write-only: the kernel keeps its own copy of every map.
* The kernel runs with ROMOFF = 1, so every value it writes to the task
* register has bit 5 set.
*
* The ROM bank (rom_ec6809.asm, $F000-$FFFF) loads OS9Boot from the SD
* card the way the Pico-Thing REL does (BtPreld): the modules end at
* $E000, krn goes to the kernel window, and krn is entered with X = start
* of the modules, Y = their size, so the kernel adopts them in place.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   1      2026/11/23  Philippe Roehr
* Created for the V6 CPU board.

                    nam       ec6809_l2.d
                    ttl       NitrOS-9 Level 2 definitions for the EC-6809 V6

*
* Dynamic Address Translator
*
DAT.BlCt            equ       8                   blocks per address space
DAT.BlSz            equ       (256/DAT.BlCt)*256  block size, 8 KB
DAT.ImSz            equ       DAT.BlCt*2          DAT image size, 2 bytes a block
DAT.Addr            equ       -(DAT.BlSz/256)     DAT MSB address bits
DAT.Task            equ       $FE00               task register (and its RAM mirror)
DAT.Regs            equ       $FF00               DAT RAM, write-only, 8 bytes a task
DAT.TkCt            equ       32                  number of hardware tasks
DAT.BlMx            equ       $7F                 highest block: 1 MB
DAT.BMSz            equ       $80                 memory block map size
DAT.Free            equ       $33FF               free slot: block $FF, PA20 = 1, no RAM
DAT.WrPr            equ       0                   no write protect
DAT.WrEn            equ       0                   no write enable
SysTask             equ       0                   system task number
ROMOFF              equ       %00100000           task register bit 5: RAM at $F000-$FEFF
KrnBlk              set       $7F                 block of the kernel window (top of 1 MB)
RAMBlks             equ       $80                 fixed RAM: 1 MB in 8 KB blocks

* Highest address a user buffer may reach (F$CpyMem): $E000 up is the I/O
* and the kernel window.
UserMemLimit        equ       $E000

*
* Boot. The ROM preloads OS9Boot: krnp2, init, ioman, the drivers and the
* shell end at $E000 (they start at $4000 or above: the page at $2000
* carries the hand-over), and krn sits in the kernel window at Bt.Start.
*
BtPreld             equ       1                   the ROM preloads the bootfile
KrnFixW             equ       1                   the kernel window is the fixed block KrnBlk
Bt.End              equ       $FF00               end of the kernel window
KrnSlot             equ       Bt.End-Bt.Start     krn + register stack + vector table
KrnGap              equ       Bt.Start-$E000      the I/O page, a gap in the bootfile
SHIFTBIT            equ       0                   no shift key on the serial console

*
* Fixed entries in the ROM page $FF00-$FFEF, readable whatever ROMOFF is.
* Built by level2/ec6809/modules/rom_ec6809.asm.
*
ROM.Go              equ       $FF00               ROMOFF = 1, task 0, JMP ,U
ROM.Reboot          equ       $FF08               ROMOFF = 0, task 0, reset entry
ROM.BtBug           equ       $FF14               print A on the console ACIA
ROM.Crash           equ       $FF30               print "CRASH" and B, and stop

*
* Kernel vector table at the top of the kernel window: the ROM vectors
* point here, after the register stack (SWIStack).
*
KrnVec              equ       $FEEE               SWI3 vector entry, then SWI2,
*                                                 FIRQ, IRQ, SWI, NMI, 3 bytes each

                    endc
