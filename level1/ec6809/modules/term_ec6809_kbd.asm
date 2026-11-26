********************************************************************
* K1 - Device Descriptor for the PS/2 keyboard (ec6809_kbd), input only
*
* The keyboard comes in through the CPU board VIA ($EF80). Input only: the
* driver discards what is written to a K1 path, and the echo goes to K1
* itself (IT.D2P), so it is not seen. Test with
*     shell </k1 >/term >>/term
* typing blind on the PS/2 keyboard, the answers come in minicom.
*
* IT.D2P is not Term: SCF (ReleaseDevices, the CLRA before STA V.BUSY)
* never frees an echo device that differs from the path's own device, so
* the next process to use Term waited forever for the shell.
*
* Edition 1, 2026-Nov-26, Ph. Roehr
* Edition 2, 2026-Nov-26: echo to K1 itself (Term as echo device hung)
********************************************************************

                    nam       K1
                    ttl       ec6809_kbd Device Descriptor

                    ifp1
                    use       defsfile
                    endc

tylg                set       Devic+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       2

                    mod       eom,name,tylg,atrv,mgrnam,drvnam

* UPDAT.: SCF attaches the echo device with read and write swapped, and a
* shell opens its paths for update.
                    fcb       UPDAT.              mode byte
                    fcb       HW.Page             extended controller address
                    fdb       VIA0Base            CPU board 6522 VIA

                    fcb       initsize-*-1        initialization table size
                    fcb       DT.SCF              IT.DVC device type
                    fcb       $00                 IT.UPC case:0=up&lower,1=upper only
                    fcb       $01                 IT.BSO backspace:0=bsp,1=bsp then sp & bsp
                    fcb       $00                 IT.DLO delete:0=bsp over line,1=return
                    fcb       $01                 IT.EKO echo:0=no echo
                    fcb       $01                 IT.ALF auto line feed:0=off
                    fcb       $00                 IT.NUL end of line null count
                    fcb       $00                 IT.PAU no end of page pause
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
                    fdb       name                IT.D2P echo device: K1 itself
                    fcb       $00                 IT.XON
                    fcb       $00                 IT.XOFF
                    fcb       80                  IT.COL number of columns for display
                    fcb       24                  IT.ROW number of rows for display
                    fcb       $00                 IT.XTYP 0 => NOT extended type
initsize            equ       *

name                fcs       /K1/
                    fcb       edition
mgrnam              fcs       /SCF/
drvnam              fcs       /ec6809_kbd/

                    emod
eom                 equ       *
                    end
