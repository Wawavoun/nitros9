********************************************************************
* Boot - EC-6809 SPI SD card boot module
*
* Loads OS9Boot from an SD card on the I/O board SPI interface.
* The card is read through the public entries of IO_EPROM_V6, page 1:
*   P_SDINIA  probe CS0 and CS1, SDSC or SDHC
*   P_RDSDLB  read one 256-byte sector, A = LSN bits 15-8, B = bits 7-0
* One OS-9 sector is the first half of SD block LSN, so a card holds a
* disk of up to 65536 sectors (16 MB) from block 0.
*
* BOOTCS selects the card: 0 = CS0 (default), 1 = CS1.
*
* The ESS540 monitor normally sets up the I/O board. It is not in this
* ROM, so HWInit selects EPROM page 1 and I/O RAM page 0, and stores the
* empty FARCALL frame pointer before the first EPROM call.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   1      2026/11/15  Philippe Roehr
* Created from boot_ec6809sd, without the Arduino.

                    nam       Boot
                    ttl       EC-6809 SPI SD boot module

                    ifp1
                    use       defsfile
                    endc

* Only the lower 16 bits of an LSN are used: see boot_common.asm.
LSN24BIT            equ       0
FLOPPY              equ       0

* Default boot device statics
                    org       0
seglist             rmb       2                   pointer to segment list
blockloc            rmb       2                   pointer to memory requested
blockimg            rmb       2                   duplicate of the above
bootsize            rmb       2                   size in bytes
LSN0Ptr             rmb       2                   in-memory LSN0 pointer
size                equ       .

tylg                set       Systm+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       1

                    mod       eom,name,tylg,atrv,start,size

name                fcs       /Boot/
                    fcb       edition

*--------------------------------------------------------------------------
* HWInit - Initialize the device
*
*    Entry:
*       Y  = hardware address
*
*    Exit:
*       Carry Clear = OK, Set = Error
*       B  = error (Carry Set)
*
HWInit              clr       >PRCNT              RDSDLB must not call the FLEX spooler
                    lda       #1
                    sta       >IOPAGE             EPROM page 1, the public entries
                    clr       >IORAMPG            I/O RAM page 0 holds the FARCALL frames
                    ldd       #IODEP0
                    std       >IODEP              no FARCALL frame yet
                    lda       #2                  both cards not tested
                    sta       >SDOK0
                    sta       >SDOK1
                    jsr       P_SDINIA            CMD0 / CMD8 / ACMD41 / CMD58 on CS0 and CS1
                    lda       #BOOTCS
                    sta       >SDCS               boot card
                    ldx       #SDOK0
                    tst       a,x                 $00 is the only usable value
                    beq       HWTerm
                    comb
                    ldb       #E$NotRdy
                    rts

*--------------------------------------------------------------------------
* HWTerm - Terminate the device
*
*    Exit:
*       Carry Clear = OK, Set = Error
*       B = error (Carry Set)
*
HWTerm              clrb                          no error
                    rts

                    use       boot_common.asm

*--------------------------------------------------------------------------
* HWRead - Read a 256 byte sector from the device
*
*    Entry:
*       Y  = hardware address
*       X  = bits 15-0 of LSN
*       blockloc,u = where to load the 256 byte sector
*
*    Exit:
*       X = ptr to data (i.e. ptr in blockloc,u)
*       Carry Clear = OK, Set = Error
*
HWRead              tfr       x,d                 A = LSN bits 15-8, B = bits 7-0
                    ldx       blockloc,u
                    jsr       P_RDSDLB            A, X, Y and U are kept
                    bcs       HWRdEr
                    rts                           B = 0, C = 0 from RDSDLB
HWRdEr              ldb       #E$Read
                    rts

Address             fdb       $0000

                    emod
eom                 equ       *
EOMSize             equ       *-Address

                    end
