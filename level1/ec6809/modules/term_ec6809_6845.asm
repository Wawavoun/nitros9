********************************************************************
* V1 - Device Descriptor for the 6845 screen (ec6809_6845), output only
*
* The 16 bytes after the SCF table are the 6845 registers R0-R15. The
* driver finds them at M$DTyp + the SCF table size. Values: Techwood LCD
* screen, from the ESS540 monitor.
*
* Edition 1, 2026-Nov-26, Ph. Roehr
* Edition 2, 2026-Nov-26: mode UPDAT. (write-only open gave #203)
********************************************************************

                    nam       V1
                    ttl       ec6809_6845 Device Descriptor

                    ifp1
                    use       defsfile
                    endc

tylg                set       Devic+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       2

                    mod       eom,name,tylg,atrv,mgrnam,drvnam

* UPDAT., not WRITE.: SCF attaches the echo device (IT.D2P, this one) with
* read and write swapped, so a write-only open needs read here (#203 else).
* The driver itself still answers E$BMode to a read (no keyboard yet).
                    fcb       UPDAT.              mode byte
                    fcb       HW.Page             extended controller address
                    fdb       CRTCBase            6845 register select, data at +1

                    fcb       initsize-*-1        initialization table size
                    fcb       DT.SCF              IT.DVC device type
                    fcb       $00                 IT.UPC case:0=up&lower,1=upper only
                    fcb       $01                 IT.BSO backspace:0=bsp,1=bsp then sp & bsp
                    fcb       $00                 IT.DLO delete:0=bsp over line,1=return
                    fcb       $01                 IT.EKO echo:0=no echo
                    fcb       $01                 IT.ALF auto line feed:0=off
                    fcb       $00                 IT.NUL end of line null count
                    fcb       $00                 IT.PAU no end of page pause (it would read)
                    fcb       24                  IT.PAG lines per page
                    fcb       C$BSP               IT.BSP backspace character
                    fcb       C$DEL               IT.DEL delete line character
                    fcb       C$CR                IT.EOR end of record character
                    fcb       C$EOF               IT.EOF end of file character
                    fcb       C$RPRT              IT.RPR reprint line character
                    fcb       C$RPET              IT.DUP duplicate last line character
                    fcb       C$PAUS              IT.PSC pause character
                    fcb       C$INTR              IT.INT interrupt character
                    fcb       C$QUIT              IT.QUT quit character
                    fcb       C$BSP               IT.BSE backspace echo character
                    fcb       C$BELL              IT.OVF line overflow character (bell)
                    fcb       $00                 IT.PAR parity (none, not a serial line)
                    fcb       $00                 IT.BAU baud rate (none)
                    fdb       name                IT.D2P copy of descriptor name address
                    fcb       $00                 IT.XON
                    fcb       $00                 IT.XOFF
                    fcb       80                  IT.COL number of columns for display
                    fcb       24                  IT.ROW number of rows for display
                    fcb       $00                 IT.XTYP 0 => NOT extended type
initsize            equ       *

* 6845 registers R0-R15, Techwood LCD screen (ESS540 table).
                    fcb       $69                 R0  horizontal total
                    fcb       $50                 R1  horizontal displayed: 80
                    fcb       $57                 R2  horizontal sync position
                    fcb       $08                 R3  sync width
                    fcb       $1B                 R4  vertical total
                    fcb       $03                 R5  vertical total adjust
                    fcb       $18                 R6  vertical displayed: 24
                    fcb       $19                 R7  vertical sync position
                    fcb       $00                 R8  interlace mode: none
                    fcb       $0A                 R9  max scan line address
                    fcb       $60                 R10 cursor start (bits 6-5 blink mode)
                    fcb       $09                 R11 cursor end
                    fcb       $00                 R12 start address H
                    fcb       $00                 R13 start address L
                    fcb       $00                 R14 cursor H
                    fcb       $00                 R15 cursor L

name                fcs       /V1/
                    fcb       edition
mgrnam              fcs       /SCF/
drvnam              fcs       /ec6809_6845/

                    emod
eom                 equ       *
                    end
