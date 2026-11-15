********************************************************************
* rbec6809spi - EC-6809 SPI SD card RBF driver
*
* Drives the two SD sockets of the I/O board through IO_EPROM_V6:
*   drive 0 = CS0, drive 1 = CS1 (descriptor IT.DRV).
* Each OS-9 sector is the first half of SD block LSN (P_RDSDLB and
* P_WRSDLB), so a card holds a disk of up to 65536 sectors (16 MB).
* The second half of each block is written as zeros.
*
* The booter has already set up the I/O board and probed both cards.
* Init probes again any card whose flag is not $00 or $01; that sends no
* command to a card already known. Cards are not hot-plugged: a card
* inserted after boot needs a reboot.
*
* Each EPROM call runs to the end with interrupts left as they are. The
* calls are made only here and in Clock2, both in system state, so two
* calls never overlap.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   1      2026/11/15  Philippe Roehr
* Created from rbec6809sd, without the Arduino.

                    nam       rbec6809spi
                    ttl       EC-6809 SPI SD card RBF driver

                    ifp1
                    use       defsfile
                    endc

NumDrvs             set       2

tylg                set       Drivr+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

                    mod       eom,name,tylg,atrv,start,size

                    rmb       DRVBEG+(DRVMEM*NumDrvs)
size                equ       .

                    fcb       DIR.+SHARE.+PEXEC.+PREAD.+PWRIT.+EXEC.+UPDAT.

name                fcs       /rbec6809spi/
                    fcb       edition

start               lbra      Init
                    lbra      Read
                    lbra      Write
                    lbra      GetStat
                    lbra      SetStat
                    lbra      Term

* Init
*
* Entry:
*    Y  = address of device descriptor
*    U  = address of device memory area
*
* Exit:
*    CC = carry set on error
*    B  = error code
*
Init                ldb       #NumDrvs
                    stb       V.NDRV,u
                    leax      DRVBEG,u
                    lda       #$FF
Init2               sta       DD.TOT,x            invalidate drive tables
                    sta       DD.TOT+1,x
                    sta       DD.TOT+2,x
                    leax      DRVMEM,x
                    decb
                    bne       Init2
                    bsr       Page1
                    jsr       P_SDINIA            probe only cards not yet tested
* No usable card is not an Init error: Read and Write return E$NotRdy.
Term                clrb
                    rts

* Page1 - map the EPROM public entries. RDSDLB tests PRCNT for the FLEX
* spooler; krn keeps its page allocated and it must stay 0.
Page1               lda       #1
                    sta       >IOPAGE
                    clr       >PRCNT
                    rts

* Prep - check the drive and the LSN, select the card.
*
* Entry:
*    B  = MSB of LSN
*    X  = LSB of LSN
*    Y  = address of path descriptor
*
* Exit:
*    D  = LSN bits 15-0 (A = high byte, B = low byte)
*    CC = carry set on error, B = error code
*
Prep                tstb                          bits 23-16 must be 0
                    bne       PrepSct
                    ldb       PD.DRV,y
                    cmpb      #NumDrvs
                    bhs       PrepUnit
                    stb       >SDCS
                    pshs      x
                    ldx       #SDOK0
                    tst       b,x                 $00 is the only usable value
                    puls      x
                    bne       PrepNR
                    bsr       Page1
                    tfr       x,d
                    andcc     #^Carry
                    rts
PrepSct             comb
                    ldb       #E$Sect
                    rts
PrepUnit            comb
                    ldb       #E$Unit
                    rts
PrepNR              comb
                    ldb       #E$NotRdy
                    rts

* Read
*
* Entry:
*    B  = MSB of LSN
*    X  = LSB of LSN
*    Y  = address of path descriptor
*    U  = address of device memory area
*
* Exit:
*    CC = carry set on error
*    B  = error code
*
Read                bsr       Prep
                    bcs       ReadEx
                    ldx       PD.BUF,y
                    pshs      d
                    jsr       P_RDSDLB            A, X, Y and U are kept
                    puls      d                   carry is kept
                    bcs       ReadEr
                    cmpd      #0                  LSN 0?
                    bne       ReadOk
* LSN 0: copy the disk description into this drive's table.
                    lda       PD.DRV,y
                    ldb       #DRVMEM
                    mul
                    leax      d,u
                    leax      DRVBEG,x
                    ldy       PD.BUF,y
                    ldb       #DD.SIZ
CpyLSN0             lda       ,y+
                    sta       ,x+
                    decb
                    bne       CpyLSN0
ReadOk              clrb
ReadEx              rts
ReadEr              ldb       #E$Read
                    rts

* Write
*
* Entry:
*    B  = MSB of LSN
*    X  = LSB of LSN
*    Y  = address of path descriptor
*    U  = address of device memory area
*
* Exit:
*    CC = carry set on error
*    B  = error code
*
Write               bsr       Prep
                    bcs       ReadEx
                    ldx       PD.BUF,y
                    jsr       P_WRSDLB            A, X, Y and U are kept
                    bcc       ReadOk
                    ldb       #E$Write
                    rts

* GetStat
*
* Entry:
*    R$B = function code
*    Y   = address of path descriptor
*    U   = address of device memory area
*
* Exit:
*    CC = carry set on error
*    B  = error code
*
GetStat             comb
                    ldb       #E$UnkSvc
                    rts

* SetStat
*
* SS.Reset and SS.WTrk have nothing to do on a card, so format only
* writes the sectors. Every other code is accepted the same way.
*
SetStat             clrb
                    rts

                    emod
eom                 equ       *
                    end
