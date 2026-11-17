********************************************************************
* rbec6809spi - EC-6809 SPI SD card RBF driver
*
* Drives the two SD sockets of the I/O board through the NitrOS-9 part of
* the I/O board EPROM (recipes/ec6809/io_eprom_nos9.asm), page $10:
*   drive 0 = CS0, drive 1 = CS1 (descriptor IT.DRV).
* Each OS-9 sector is the first half of SD block LSN (P_RDSEC and
* P_WRSEC, 24-bit LSN). The second half of each block is written as zeros.
* The EPROM checks the card number and the card flag, and returns
* E$Unit, E$NotRdy, E$Read or E$Write itself.
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
*   2      2026/11/17  Philippe Roehr
* Uses the NitrOS-9 EPROM part on page $10, with a 24-bit LSN.

                    nam       rbec6809spi
                    ttl       EC-6809 SPI SD card RBF driver

                    ifp1
                    use       defsfile
                    endc

NumDrvs             set       2

tylg                set       Drivr+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       2

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
                    bsr       PageN
                    jsr       P_SDINIA            probe only cards not yet tested
* No usable card is not an Init error: Read and Write return E$NotRdy.
Term                clrb
                    rts

* PageN - map the EPROM public entries. A destroyed.
PageN               lda       #NOSPAGE
                    sta       >IOPAGE
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
Read                bsr       PageN
                    lda       PD.DRV,y            card
                    pshs      u,b                 B = LSN bits 23-16, at 0,s
                    ldu       PD.BUF,y
                    jsr       P_RDSEC             A, X, Y and U are kept
                    puls      b,u                 C is kept
                    bcs       ReadEx              B = error from the EPROM
                    tstb                          LSN 0?
                    bne       ReadOk
                    leax      ,x
                    bne       ReadOk
* LSN 0: copy the disk description into this drive's table.
                    ldb       #DRVMEM             A = PD.DRV, kept by P_RDSEC
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
Write               bsr       PageN
                    lda       PD.DRV,y            card
                    pshs      u
                    ldu       PD.BUF,y
                    jsr       P_WRSEC             B = 0 or the error, C is kept
                    puls      u,pc

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
