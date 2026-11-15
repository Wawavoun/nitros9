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
* I/O board EPROM (IO_EPROM_V6), SPI SD cards and DS3231 RTC.
*
* The EPROM is a paged window at $E800-$E9FF. Page 1 holds the public
* entries. Select page 1 from code outside the window, then JSR a slot.
* The slot returns with page 1 still mapped. U is not used by FARCALL.
* Only one EPROM call may run at a time. Interrupt code may call it only
* while IODEP = IODEP0 (no frame active), and must put back the page it
* found in PAGEID. Clock2 GetTime, called every minute from the tick, does.

PAGEID              equ       $E800               first byte of every page: its number
IOPAGE              equ       $EEB0               I/O EPROM page latch
IORAMPG             equ       $EEC0               I/O RAM page latch
IODEP               equ       $EA00               FARCALL frame pointer, in I/O RAM
IODEP0              equ       $EC00               its value with no call active

P_SDINIA            equ       $E898               probe CS0 then CS1
P_RDSDLB            equ       $E8A8               read one 256-byte sector
P_WRSDLB            equ       $E8B0               write one 256-byte sector
P_I2C_INIT          equ       $E8C0               PCF8584 init
P_I2C_START         equ       $E8C8               I2C start (sent by the next write)
P_I2C_STOP          equ       $E8D8               I2C stop
P_I2C_WRITE         equ       $E8E0               send B, Z = 1 on ACK
P_RTC_GET_BYTE      equ       $E978               DS3231 register A -> B, Z = 1 OK
P_BCDHEX            equ       $E980               BCD A -> binary A

* EPROM working RAM in main memory. Krn keeps pages $CC and $DE allocated.
PRCNT               equ       $CC34               FLEX spooler flag, must stay 0
SDCS                equ       $DE6B               card used by RDSDLB/WRSDLB, 0 or 1
SDOK0               equ       $DE6D               CS0: $00 usable, $01 empty, $02 not tested
SDOK1               equ       $DE6E               CS1: same values

* EPROM errors returned in B with C = 1
ERSRW               equ       $40                 read or write failed
ERSNR               equ       $80                 no usable card

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
