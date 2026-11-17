********************************************************************
* Boot - EC-6809 SPI SD card boot module
*
* Loads OS9Boot from an SD card on the I/O board SPI interface.
* The card is read through the NitrOS-9 part of the I/O board EPROM
* (recipes/ec6809/io_eprom_nos9.asm), public entries on page $10:
*   P_NINIT   set up the EPROM variables, probe CS0 and CS1
*   P_SDSTAT  flag of one card
*   P_RDSEC   read one 256-byte sector, A = card, B:X = LSN, U = buffer
* One OS-9 sector is the first half of SD block LSN.
*
* BOOTCS selects the card: 0 = CS0 (default), 1 = CS1.
*
* HWInit selects EPROM page $10 and I/O RAM page 0, and stores the empty
* FARCALL frame pointer before the first EPROM call.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   1      2026/11/15  Philippe Roehr
* Created from boot_ec6809sd, without the Arduino.
*   2      2026/11/17  Philippe Roehr
* Uses the NitrOS-9 EPROM part on page $10. No EPROM variable in main RAM.

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
edition             set       2

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
HWInit              lda       #NOSPAGE
                    sta       >IOPAGE             EPROM page $10, the public entries
                    clr       >IORAMPG            I/O RAM page 0: frames and variables
                    ldd       #IODEP0
                    std       >IODEP              no FARCALL frame yet
                    jsr       P_NINIT             CMD0 / CMD8 / ACMD41 / CMD58 on CS0 and CS1
                    lda       #BOOTCS
                    jsr       P_SDSTAT            B = flag of the boot card
                    tstb                          $00 is the only usable value
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
HWRead              pshs      u
                    ldu       blockloc,u          the buffer
                    lda       #BOOTCS
                    clrb                          LSN bits 23-16
                    jsr       P_RDSEC             A, X, Y and U are kept, B = error
                    tfr       u,x                 X = ptr to data, C is kept
                    puls      u,pc

Address             fdb       $0000

                    emod
eom                 equ       *
EOMSize             equ       *-Address

                    end
