;*-----------------------------------------------------------------------------
;*
;* sc68681m : Shared memory module
;*
;* Copies of the 68681 write-only registers shared by the port A and
;* port B instances of sc68681.
;*
;* 2026-May-04 by Ph.Roehr
;* 2026-Aug-06 IPCR dual-port registration
;* 2026-Nov-24 edition 3: hardware CTS, no IPCR registration any more
;*
;*-----------------------------------------------------------------------------

                    ifp1
                    use       defsfile
                    endc

                    nam       sc68681m
                    ttl       Shared data sc68681 driver instances

tylg                set       Data
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       $03

                    mod       eom,name,tylg,atrv,start,size

name                fcs       /sc68681m/
                    fcb       edition

                    fill      $00,V.SCF-*

                    org       V.SCF
ARTINT              fcb       $00         ; IMR $05 register copy
ARTACR              fcb       $80         ; ACR $04 register copy ACR(7)=1
size                equ       *

start
                    emod
eom                 equ       *

                    end
