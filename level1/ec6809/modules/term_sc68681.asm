;*-----------------------------------------------------------------------------
;*
;* T1 - Device Descriptor for DUART port A (sc68681), hardware RTS/CTS.
;*
;* Edition 4, 2026-Nov-24: 19200 baud, no end-of-page pause (SCF would wait
;* for a key on this line after every 24 lines).
;*
;*-----------------------------------------------------------------------------

            ifp1
            use         defsfile
            endc

;*---------------------------------------------------------------------------
;* Module header.
;*---------------------------------------------------------------------------

Rev         set         0               (0..15)
Edition     set         4               (0..255)
TypLng      set         Devic+Objct
AtrRev      set         ReEnt+Rev

            mod         ModSizTA,ModNamTA,TypLng,AtrRev
            fdb         MgrNamTA        ; offset to file manager name
            fdb         DrvNamTA        ; offset to device driver name

;*---------------------------------------------------------------------------
;* Mode, address, table size.
;*---------------------------------------------------------------------------

            fcb         $03             ; capabilities = read/write

            fcb         $00             ; Device physical address (MSB)

;* For using A port of 68681 with sc68681 driver use base address ($ef60)
;* For using B port of 68681 with sc68681 driver use base address + 8 ($ef68)

            fdb         $EF60           ; sc68681 port A
;            fdb         $EF68           ; sc68681 port B

            fcb         EndTblTA-*-1    ; initialization table size

;*---------------------------------------------------------------------------
;* Option Initialization table.
;*---------------------------------------------------------------------------

            fcb         0               ; IT.DVC  device type (0 = SCF)
            fcb         0               ; IT.UPC  case (0 = upper/lower case)
            fcb         1               ; IT.BSO  backspace output (1 = bse/spce/bse)
            fcb         0               ; IT.DLO  delete output (0 = bse over entire line)
            fcb         1               ; IT.EKO  echo flag (1 = echo)
            fcb         1               ; IT.ALF  auto line-feed (1 = yes)
            fcb         0               ; IT.NUL  number of end-of-line nulls
            fcb         0               ; IT.PAU  end-of-page pause flag (0 = no: a data line)
            fcb         24              ; IT.PAG  lines per page
            fcb         $08             ; IT.BSP  keyboard backspace character (Ctrl+H)
            fcb         $18             ; IT.DEL  keyboard delete-line character (Ctrl+X)
            fcb         $0D             ; IT.EO   end-of-record character (CR)
            fcb         $1B             ; IT.EOF  keyboard end-of-file character (ESC/Ctrl+[)
            fcb         $04             ; IT.RPR  keyboard reprint-current-line charac (Ctrl+D)
            fcb         $01             ; IT.DUP  keyboard duplicate-prev-line charac (Ctrl+A)
            fcb         $17             ; IT.PSC  keyboard "pause" character (Ctrl+W)
            fcb         $03             ; IT.INT  keyboard "interrupt" character (Ctrl+C)
            fcb         $11             ; IT.QUT  keyboard "quit" character (Ctrl+Q)
            fcb         $08             ; IT.BSE  backspace output character
            fcb         $07             ; IT.OVF  line overflow character (bell)
;* For IT.PAR code just below
;* bit 7 stop bit (6-5) data valid / bit 6-5 01 2 stop - 00 1 stop / bit 4-3 parity / bit 2 odd/even / bit 1-0 bits per char
            fcb         $B3             ; IT.PAR  device initialization value (8 data/no par./2 stop)
;* IT.BAU: 0=110 1=300 2=600 3=1200 4=2400 5=4800 6=9600 7=19200
            fcb         $07             ; IT.BAU  baud rate ($07 = 19200 baud)
            fdb         ModNamTA        ; IT.D2P  offset to name of attached device
            fcb         $00             ; IT.XON  X-ON character (not defined)
            fcb         $00             ; IT.XOFF X-OFF character (not defined)
            fdb         0               ; (reserved for expansion)
EndTblTA    equ         *

;*---------------------------------------------------------------------------
;* Name strings.
;*---------------------------------------------------------------------------

MgrNamTA    fcs         'SCF'           ; file manager name
DrvNamTA    fcs         'sc68681'       ; device driver name
ModNamTA    fcs         'T1'            ; device descriptor module name
            fcb         Edition         ; module edition

            emod
ModSizTA    equ         *

            end
