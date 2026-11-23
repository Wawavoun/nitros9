********************************************************************
* rom_ec6809 - NitrOS-9 Level 2 boot ROM for the EC-6809 V6 CPU board
*
* A raw 4 KB image for $F000-$FFFF (one 4 KB bank of the CPU board
* EPROM, chosen with the A12/A13 jumpers). Not an OS-9 module.
*
* At reset the V6 board runs with ROMOFF = 0: $F000-$FFFF is this ROM,
* $E000-$EFFF the I/O. The ROM:
*   1. writes all 32 DAT maps: task 0 = blocks 0-6 (identity), the other
*      tasks no RAM ($FF), and slot 7 = KrnBlk in every task;
*   2. sets up the console ACIA and the I/O board EPROM, and probes the
*      SD cards (P_NINIT);
*   3. reads LSN0 of the boot card (BOOTCS) for OS9Boot (DD.BT, DD.BSZ,
*      written by os9 gen);
*   4. loads OS9Boot. The recipe builds it as
*        modules (krnp2 ... shell)    ends at $E000, starts at $4000 or up
*        gap of $1000 bytes           the I/O page, not loaded
*        krn, $F00 bytes              the kernel window $F000-$FEFF
*      The modules go straight to their place (task 0 is identity
*      mapped). krn goes to block KrnBlk, mapped for a moment in slot 1;
*   5. jumps to ROM.Go in the $FFxx page with X = start of the modules,
*      Y = their size, U = krn entry. ROM.Go sets ROMOFF, so $F000-$FEFF
*      becomes the kernel window, and enters krn, which adopts the
*      modules in place (BtPreld, as on the Pico-Thing).
*
* The $FFxx page is ROM whatever ROMOFF is. It holds ROM.Go, ROM.Reboot
* (back to ROM and to the reset entry), ROM.BtBug (console output, the
* kernel's D.BtBug) and ROM.Crash (the kernel's D.Crash), then the CPU
* vectors. The interrupt vectors point to the kernel table at KrnVec
* ($FEEE), in the kernel window.
*
* The SD card is read through the NitrOS-9 part of the I/O board EPROM
* (P_NINIT, P_SDSTAT, P_RDSEC), as the Level 1 booter does.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   1      2026/11/23  Philippe Roehr
* Created for the V6 CPU board.

                    nam       rom_ec6809
                    ttl       EC-6809 V6 NitrOS-9 Level 2 boot ROM

                  IFP1
                    use       defsfile
                  ENDC

* RAM used before krn starts. Block 0, which krn clears.
RomStk              equ       $1000               stack top
LSN0Buf             equ       $1000               LSN0 is read here
BtLSN               equ       $0100               3 bytes: next LSN of OS9Boot
BtLow               equ       $0103               2 bytes: size of the modules
BtCnt               equ       $0105               1 byte: sectors left to read
KrnEnt              equ       $0106               2 bytes: krn entry point

* krn is loaded through slot 1 ($2000-$3FFF) with KrnBlk mapped there.
* Offset $1000 in the block is $F000 once the block is in slot 7.
KrnTmp              equ       $2000+(Bt.Start-$E000)
ModLow              equ       $4000               lowest start of the modules

                    org       $F000

********************************************************************
* Reset entry
*
Start               orcc      #IntMasks
                    ldx       #$1FFF              let the hardware settle
Settle              leax      -1,x
                    bne       Settle

* All 32 maps. X runs from $FF00 to $FFFF, B = 8 x task + slot. No RAM
* is mapped yet, so no stack until this is done.
                    ldx       #DAT.Regs
DatLp               tfr       x,d
                    andb      #%00000111          B = slot
                    cmpb      #7
                    beq       DatKrn              slot 7: the kernel block
                    cmpx      #DAT.Regs+8
                    blo       DatSet              task 0: block = slot
                    ldb       #$FF                other tasks: no RAM
                    bra       DatSet
DatKrn              ldb       #KrnBlk
DatSet              stb       ,x+
                    cmpx      #$0000              past $FFFF?
                    bne       DatLp
                    clr       >DAT.Task           task 0, ROMOFF = 0
                    lds       #RomStk

* Console ACIA on the I/O board
                    ldx       #UARTBase
                    lda       #3                  master reset
                    sta       ,x
                    lda       #$11                8 data, 2 stop, /16
                    sta       ,x
                    tst       1,x                 drop any received byte
                    leax      MsgHello,pcr
                    lbsr      PrStr

* I/O board EPROM, as the Level 1 booter
                    lda       #NOSPAGE
                    sta       >IOPAGE             EPROM page $10, the public entries
                    clr       >IORAMPG            I/O RAM page 0: frames and variables
                    ldd       #IODEP0
                    std       >IODEP              no FARCALL frame yet
                    jsr       P_NINIT             probe CS0 and CS1
                    lda       #BOOTCS
                    jsr       P_SDSTAT            B = flag of the boot card
                    tstb
                    beq       CardOk
                    leax      MsgNoCard,pcr
                    lbra      Fail

* LSN0: DD.BT and DD.BSZ
CardOk              ldu       #LSN0Buf
                    clr       >BtLSN
                    clr       >BtLSN+1
                    clr       >BtLSN+2
                    lbsr      RdSec
                    ldd       LSN0Buf+DD.BT
                    std       >BtLSN
                    lda       LSN0Buf+DD.BT+2
                    sta       >BtLSN+2
                    ldd       LSN0Buf+DD.BSZ      OS9Boot size
                    subd      #KrnGap+KrnSlot     less the gap and krn
                    bls       BadBoot             too small (or no OS9Boot)
                    tstb                          whole sectors?
                    bne       BadBoot
                    cmpd      #$E000-ModLow       room below $E000?
                    bhi       BadBoot
                    std       >BtLow

* The modules, up to $E000
                    sta       >BtCnt              A = sectors
                    ldd       #$E000
                    subd      >BtLow
                    tfr       d,u                 U = start of the modules
                    lbsr      RdSecs

* Skip the gap
                    ldb       #KrnGap/256
SkipLp              lbsr      IncLSN
                    decb
                    bne       SkipLp

* krn, into KrnBlk through slot 1
                    lda       #KrnBlk
                    sta       >DAT.Regs+1         task 0 slot 1 = KrnBlk
                    lda       #KrnSlot/256
                    sta       >BtCnt
                    ldu       #KrnTmp
                    lbsr      RdSecs
                    ldd       >KrnTmp+M$ID
                    cmpd      #M$ID12             a module?
                    bne       NoKrn
                    ldd       >KrnTmp+M$Exec
                    addd      #Bt.Start
                    std       >KrnEnt
                    lda       #1
                    sta       >DAT.Regs+1         task 0 slot 1 = block 1 again

* Enter krn
                    leax      MsgGo,pcr
                    bsr       PrStr
                    ldd       #$E000
                    subd      >BtLow
                    tfr       d,x                 X = start of the modules
                    ldy       >BtLow              Y = their size
                    ldu       >KrnEnt             U = krn entry
                    jmp       ROM.Go

BadBoot             leax      MsgBadBoot,pcr
                    bra       Fail
NoKrn               leax      MsgNoKrn,pcr

* Fail: print X, then stop
Fail                bsr       PrStr
Stop                bra       Stop

********************************************************************
* RdSecs - read BtCnt sectors from BtLSN to U
* RdSec  - read one sector from BtLSN to U
* Exit: U past the data, BtLSN past the last sector. On error: message
* and stop.
*
RdSecs              bsr       RdSec
                    dec       >BtCnt
                    bne       RdSecs
                    rts

RdSec               lda       #BOOTCS
                    ldb       >BtLSN              LSN bits 23-16
                    ldx       >BtLSN+1            LSN bits 15-0
                    jsr       P_RDSEC             A, X, Y and U are kept
                    bcs       RdErr
                    leau      $100,u
* IncLSN - next LSN. A and B are kept.
IncLSN              inc       >BtLSN+2
                    bne       IncEx
                    inc       >BtLSN+1
                    bne       IncEx
                    inc       >BtLSN
IncEx               rts

RdErr               pshs      b
                    leax      MsgRdErr,pcr
                    bsr       PrStr
                    puls      a
                    jsr       PrHex
                    bra       Stop

********************************************************************
* PrStr - print the string at X, ending with 0
*
PrStr               pshs      a,x
PrLp                lda       ,x+
                    beq       PrEx
                    jsr       ROM.BtBug
                    bra       PrLp
PrEx                puls      a,x,pc

MsgHello            fcb       C$CR,C$LF
                    fcc       "EC-6809 V6 - NitrOS-9 Level 2 boot ROM"
                    fcb       C$CR,C$LF,0
MsgNoCard           fcc       "No boot card"
                    fcb       C$CR,C$LF,0
MsgBadBoot          fcc       "No OS9Boot, or not for this ROM"
                    fcb       C$CR,C$LF,0
MsgNoKrn            fcc       "No krn in OS9Boot"
                    fcb       C$CR,C$LF,0
MsgRdErr            fcc       "SD read error "
                    fcb       0
MsgGo               fcc       "OS9Boot loaded"
                    fcb       C$CR,C$LF,0

********************************************************************
* The $FFxx page: ROM whatever ROMOFF is. Fixed entries for the kernel.
*
                    fill      $FF,ROM.Go-*

* ROM.Go - ROMOFF = 1 (kernel window), task 0, then JMP ,U. X and Y kept.
RGo                 lda       #ROMOFF
                    sta       >DAT.Task
                    jmp       ,u

                    fill      $FF,ROM.Reboot-*

* ROM.Reboot - back to ROM at $F000 and to the reset entry.
RReboot             orcc      #IntMasks
                    clr       >DAT.Task           task 0, ROMOFF = 0
                    jmp       [$FFFE]

                    fill      $FF,ROM.BtBug-*

* ROM.BtBug - print A on the console ACIA. Bit 7 is dropped (the last
* character of an OS-9 name). CC, A and B are kept: callers test N.
RBtBug              pshs      cc,a,b
                    anda      #$7F
RBtWait             ldb       >UARTBase
                    bitb      #%00000010          transmit register empty?
                    beq       RBtWait
                    sta       >UARTBase+1
                    puls      cc,a,b,pc

                    fill      $FF,ROM.Crash-*

* ROM.Crash - the kernel's D.Crash: print CRASH, A and B, and stop.
RCrash              orcc      #IntMasks
                    pshs      b,a
                    leax      MsgCrash,pcr
RCrLp               lda       ,x+
                    beq       RCrHex
                    jsr       ROM.BtBug
                    bra       RCrLp
RCrHex              puls      a
                    bsr       PrHex
                    lda       #C$SPAC
                    jsr       ROM.BtBug
                    puls      a
                    bsr       PrHex
RCrStop             bra       RCrStop

* PrHex - print A as two hex digits. A is destroyed.
PrHex               pshs      a
                    lsra
                    lsra
                    lsra
                    lsra
                    bsr       PrNib
                    puls      a
PrNib               anda      #$0F
                    adda      #'0
                    cmpa      #'9
                    bls       PrNib2
                    adda      #'A-'9-1
PrNib2              jmp       ROM.BtBug

MsgCrash            fcb       C$CR,C$LF
                    fcc       "CRASH "
                    fcb       0

********************************************************************
* CPU vectors. The interrupts go to the kernel table at KrnVec.
*
                    fill      $FF,$FFF0-*
                    fdb       Start               reserved
                    fdb       KrnVec              SWI3
                    fdb       KrnVec+3            SWI2
                    fdb       KrnVec+6            FIRQ
                    fdb       KrnVec+9            IRQ
                    fdb       KrnVec+12           SWI
                    fdb       KrnVec+15           NMI
                    fdb       Start               RESET

                    end
