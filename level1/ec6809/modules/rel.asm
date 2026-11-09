*******************************************************************
* REL - Relocation routine
*
* $Id$
*
* This module MUST occupy the last 256 bytes of ROM ($FF00-$FFFF)
* due to the way the Corsham board is designed.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   1      2017/05/08  Boisy G. Pitre
* Created for Corsham 6809
*

    nam REL
    ttl Relocation routine

    IFP1
    use defsfile
    ENDC

tylg    set Systm+Objct
atrv    set ReEnt+rev
rev set $05
edition     set 5

Begin   mod eom,name,tylg,atrv,start,size

    org 0
size    equ .   REL doesn't require any memory

name    fcs /REL/
    fcb edition

*************************************************************************
* Entry point for Level 1

Start

* Wait a bit for hardware to calm after powerup before doing anything

 LDX #$1FFF
xx66 leax -1,x
 bne xx66


****************************************************************
* This code initializes the DAT in a SWTPC or Corsham 6809 board
*
* This code is not needed in the PT69-x computers but causes them
* no problems. By adding this code PTMON can be used in all PT69-x
* boards as well as any SS50 processor using the SWTPC DAT circuit
* such as the Corsham 6809 board.
******************************************************************

TSTPAT  EQU     $55AA       TEST PATTERN FOR SWTPC DAT INIT
DSTART  LDX     #$FFFF+1    POINT TO DAT RAM END + 1
        LDA     #$10        STORE FIRST VALUE + 1


* INITIALIZE DAT RAM --- LOADS $00-$0F IN LOCATIONS $FFF0-$FFFF
* OF DAT RAM

DATLP   DECA                PREPARE NEXT VALUE
        STA     ,-X         POINT TO NEXT RAM LOCATION THEN STORE
        BNE     DATLP       ALL 16 LOCATIONS INITIALIZED ?

* NOTE: IX NOW CONTAINS $0000, DAT RAM IS NO LONGER
*       ADDRESSED, AND LOGICAL ADDRESSES NOW EQUAL
*       PHYSICAL ADDRESSES.

        LDS     #$8000      Put it here to finish init

 
* DAT Initialization is complete at this point

* Initialize UART
        ldx #UARTBase   POINT TO CONTROL PORT ADDRESS
        lda #3  RESET ACIA PORT CODE
        sta ,x  STORE IN CONTROL REGISTER
        lda #$11    SET 8 DATA, 2 STOP AN 0 PARITY
        sta ,x  STORE IN CONTROL REGISTER
        tst 1,x ANYTHING IN DATA REGISTER?

                leax PowMSg,pcr Print a "Dat Init message
                bsr StringOut

* Initialization is complete at this point
* Jump into Kernel at $F011

        jmp $F011   jump into Krn

PowMsg          fcb $d,$a
                fcc "DAT Init"
                fcb 0


* Entry
* A = character to output
CharOut     pshs    b   SAVE A ACCUM AND IX
fetch@      ldb UARTBase    FETCH PORT STATUS
        bitb    #2  TEST TDRE, OK TO XMIT ?
        beq fetch@  IF NOT LOOP UNTIL RDY
        sta UARTBase+1  XMIT CHAR.
        puls    b,pc    restore and leave

* Entry
* X = nil terminated string
StringOut       pshs    a,x
loop@       lda ,x+
        beq done@
        bsr CharOut
        bra loop@
done@       puls    a,x,pc

        fill    $39,$100-*-EOMSize

EOMTop      EQU *

* I/O routines jump table (known locations)
LFFE9       fdb $FF00+CharOut
LFFEB       fdb $FF00+StringOut

        EMOD
eom     EQU *

                    fdb       $0000
Vectors     fdb $0100       SWI3
        fdb $0103       SWI2
        fdb $010F       FIRQ
        fdb $010C       IRQ
        fdb $0106       SWI
        fdb $0109       NMI
        fdb $FF00+Start start of REL

EOMSize     equ *-EOMTop

        end
