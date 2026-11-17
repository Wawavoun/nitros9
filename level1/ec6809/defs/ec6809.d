                    ifne      EC6809.D-1
EC6809.D            set       1

********************************************************************
* ec6809.d - NitrOS-9 System Definitions for the EC-6809
*
* This is a high level view of the EC-6809 memory map as setup by
* NitrOS-9.
*
*     $0000----> ==================================
*               |                                  |
*               |      NitrOS-9 Globals/Stack      |
*               |                                  |
*     $0500---->|==================================|
*               |                                  |
*                 . . . . . . . . . . . . . . . . .
*               |                                  |
*               |   RAM available for allocation   |
*               |       by NitrOS-9 and Apps       |
*               |                                  |
*                 . . . . . . . . . . . . . . . . .
*               |                                  |
*     $E000---->|==================================|
*               |                                  |
*  $E000-$EFFF  |    Memory Mapped I/O Region      |
*               |                                  |
*     $F000---->|==================================|
*               |                                  |
*  $F000-$FFFF  |               ROM                |
*               |                                  |
*               |==================================|
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*          2017/04/29  Boisy G. Pitre
* Started

                    nam       ec6809.d
                    ttl       NitrOS-9 System Definitions for the EC-6809

**********************************
* Ticks per second and the CPU clock
*
                    IFNDEF    TkPerSec
TkPerSec            SET       50
                    ENDC
ECLK                equ       1843200             E clock, Hz
T1Latch             equ       ECLK/TkPerSec-2     VIA T1 reload: N+2 E cycles a period


*************************************************
*
* NitrOS-9 Level 1 Section
*
*************************************************

HW.Page             set       $E0                 Device descriptor hardware page


********************************************************************
* EC-6809 Hardware Definitions
*

DATREGS             equ       $FFF0               DAT RAM CHIP (SWTPC REL init only)

S.CharOut           EQU       $FFE9
S.StringOut         EQU       $FFEB

* 6850 ACIA console on the I/O board.
UARTBase            equ       $EEA0

* 6522 VIA on the CPU board. T1 makes the system tick.
VIA0Base            equ       $EF80
VIAREGB             equ       0                   data reg B (ORB/IRB)
VIAREGA             equ       1                   data reg A (ORA/IRA)
VIADDRB             equ       2                   data dir reg B
VIADDRA             equ       3                   data dir reg A
VIAT1CL             equ       4                   T1 counter/latch low
VIAT1CH             equ       5                   T1 counter high, a write starts T1
VIAACR              equ       $0B                 auxiliary control register
VIAIFR              equ       $0D                 interrupt flag register
VIAIER              equ       $0E                 interrupt enable register

********************************************************************
* I/O board EPROM, NitrOS-9 part (level1/ec6809/ioeprom/io_eprom_nos9.asm),
* SPI SD cards and DS3231 RTC.
*
* The EPROM is a paged window at $E800-$E9FF. Pages $10-$3F of the
* AT28C256 are the NitrOS-9 part; pages $00-$0F are FLEX and are never
* called. Page $10 (NOSPAGE) holds the public entries. Select it from code
* outside the window, then JSR a slot; the slot returns with page $10
* still mapped. U is not used by FARCALL. Errors are NitrOS-9 codes in B
* with C = 1. Every EPROM variable is in I/O RAM page 0, so the EPROM uses
* no main RAM.
* Only one EPROM call may run at a time. Interrupt code may call it only
* while IODEP = IODEP0 (no frame active), and must put back the page it
* found in PAGEID. Clock2 GetTime, called every minute from the tick, does.

PAGEID              equ       $E800               first byte of every page: its number
IOPAGE              equ       $EEB0               I/O EPROM page latch
IORAMPG             equ       $EEC0               I/O RAM page latch
IODEP               equ       $EA00               FARCALL frame pointer, in I/O RAM
IODEP0              equ       $EC00               its value with no call active
NOSPAGE             equ       $10                 EPROM page of the NitrOS-9 entries

* A = card (0 = CS0, 1 = CS1) where noted. Sector entries: B = LSN bits
* 23-16, X = LSN bits 15-0, U = 256-byte buffer; A, X, Y and U are kept.
* Card flags: $00 usable, $01 no card, $02 not tested.
P_NINIT             equ       $E850               set up, probe both cards
P_SDINIA            equ       $E858               probe the cards not yet tested
P_SDINIT            equ       $E860               A = card, forced init
P_SDSTAT            equ       $E868               A = card, B = its flag
P_RDSEC             equ       $E870               read one 256-byte sector
P_WRSEC             equ       $E878               write one 256-byte sector
P_I2C_INIT          equ       $E880               PCF8584 init
P_I2C_START         equ       $E888               I2C start (sent by the next write)
P_I2C_RESTART       equ       $E890               I2C repeated start
P_I2C_STOP          equ       $E898               I2C stop
P_I2C_WRITE         equ       $E8A0               send B, Z = 1 on ACK
P_I2C_READ_ACK      equ       $E8A8               receive B with ACK
P_I2C_READ_NACK     equ       $E8B0               receive B, last byte
P_RTC_OK            equ       $E8B8               Z = 1 if the DS3231 answers
P_RTC_GET_BYTE      equ       $E8C0               DS3231 register A -> B, Z = 1 OK
P_BCDHEX            equ       $E8C8               BCD A -> binary A

RTC.Addr            equ       $D0                 DS3231 I2C address, write

                    org       $DFC0
C.STACK             RMB       2                   TOP OF INTERNAL STACK / USER VECTOR
C.SWI3              RMB       2                   SOFTWARE INTERRUPT VECTOR #3
C.SWI2              RMB       2                   SOFTWARE INTERRUPT VECTOR #2
C.FIRQ              RMB       2                   FAST INTERRUPT VECTOR
C.IRQ               RMB       2                   INTERRUPT VECTOR
C.SWI               RMB       2                   SOFTWARE INTERRUPT VECTOR
SVCVO               RMB       2                   SUPERVISOR CALL VECTOR ORGIN
SVCVL               RMB       2                   SUPERVISOR CALL VECTOR LIMIT
LRARAM              RMB       16                  LRA ADDRESSES

Bt.Start            EQU       $F000               Start address of the boot ROM in memory
Bt.Size             EQU       $1000
Bt.Track            EQU       0
Bt.Sec              EQU       0

                    endc
