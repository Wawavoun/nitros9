;*----------------------------------------------------------------------------*
;* FILE / MODULE: sc68681.asm / DUART
;*
;* PURPOSE: Interrupt-driven device driver for 68681/DUART ports A and B,
;*          with hardware RTS/CTS flow control.
;*
;* Original version last modified    1985-Jul-05 12:10 PDT.
;* Last modified for 2681            2024-Oct-06 11:44 PDT by David C. Wiens.
;* Adapted to EC-6809 & 68681 duart  2026-May-04       by Ph. Roehr
;* XON/XOFF replaced by RTS/CTS flow control  2026-May-06
;* Kermit burst fixes: IPC mask, TX kick, sw RTS, 256-byte buffers  2026-May-19
;* Fixes: ARTINCH A clobber, ACR IP delta, dual-port IPCR CTS  2026-Aug-06
;* RTS high/low watermarks for USB-serial headroom              2026-Aug-06
;* Edition 6, 2026-Nov-24, for the NitrOS-9 ec6809 tree:
;*   - Hardware RTS: MR1 bit 7 (RxRTS) set, the 68681 drives OP0 (port A)
;*     or OP1 (port B) itself and negates RTS when its receive FIFO is
;*     full. When the input buffer reaches BHIGH the driver stops reading
;*     the FIFO (Rx interrupt off), so the 68681 negates RTS; ARTINCH turns
;*     the Rx interrupt back on at BLOW. No software RTS any more.
;*   - Hardware CTS: MR2 bit 4 (TxCTS), the 68681 waits for CTS before each
;*     character. The IPCR change interrupt and its CTS code are removed.
;*   - SS.Ready returns the byte count in B, SS.SSig and SS.Relea added
;*     (Kermit uses both).
;*   - The IRQ routine clears carry when it handled the interrupt.
;*   - F$Link of sc68681m with A = 0 (any type).
;*   - SLEEP: the S$Wake that ends the sleep stays in P$Signal (signals are
;*     processed on the return to user state), so it is cleared there and
;*     not returned as error #001. ARTCLOS still releases the port when a
;*     real signal ends its wait for the output to drain.
;*   - Buffer access with ABX: "B,X" takes B as a signed offset, so from
;*     position 128 on the 256-byte buffers were read and written 128 bytes
;*     below their start, over this static storage and the memory below it.
;*   - ARTOUTC keeps Y (SCF's path descriptor) across TXKICK.
;*   - DIRQI empties the whole receive FIFO in one interrupt and wakes the
;*     reader once, instead of one interrupt and one wake-up per character.
;*
;* Load it after boot:  load sc68681m sc68681 t1
;*
;* See copyright and licence information at end of file.
;*----------------------------------------------------------------------------*

            nam         sc68681
            ttl         Device driver for 68681/DUART on EC-6809 CPU board.

;*---------------------------------------------------------------------------
;* Definitions.
;*---------------------------------------------------------------------------

            ifp1
            use         defsfile
            endc

CAP.ALL     equ         SHARE.+PEXEC.+PWRIT.+PREAD.+EXEC.+WRITE.+READ.

;* 68681 registers, offsets from the chip base (shared by both ports)
ACR_D       equ         4               ; Auxiliary Control Register (write)
ISR_D       equ         5               ; Interrupt Status Register (read)
IMR_D       equ         5               ; Interrupt Mask Register (write)
OPRset_D    equ         14              ; set Output Port bits (write)

;* 68681 registers, offsets from the port base (port B = chip base + 8)
MR1_D       equ         0               ; mode register MR1 then MR2
MR2_D       equ         0
SR_D        equ         1               ; status register (read)
CSR_D       equ         1               ; clock select register (write)
CR_D        equ         2               ; command register (write)
RHR_D       equ         3               ; Rx holding register (read)
THR_D       equ         3               ; Tx holding register (write)

RxRDY.D     equ         $01             ; SR: receiver ready
TxRDY.D     equ         $04             ; SR: transmitter ready
RxERR.D     equ         $F0             ; SR: break, framing, parity, overrun
ErOvr.D     equ         $10             ; SR: overrun

RstMR.D     equ         $10             ; CR: reset MR pointer to MR1
RstRX.D     equ         $20             ; CR: reset receiver
RstTX.D     equ         $30             ; CR: reset transmitter
RstSt.D     equ         $40             ; CR: reset error status
EnTR.D      equ         $05             ; CR: enable receiver and transmitter

MR1RxRTS    equ         $80             ; MR1 bit 7: RTS negated when Rx FIFO full
MR2TxCTS    equ         $10             ; MR2 bit 4: Tx waits for CTS

;*
;* Equates.
;*
BSIZE       equ         256             ; size of each buffer
MSKCNTR     equ         $FF             ; (truncates to modulo 256)
BFULL       equ         BSIZE-1         ; hard full (TX sleep / RX overrun)
BWAKE       equ         (BSIZE-1)*7/8   ; wake writers when TX drained to this
BHIGH       equ         BSIZE/2         ; stop reading the FIFO (68681 drops RTS)
BLOW        equ         BSIZE/4         ; read the FIFO again

;*---------------------------------------------------------------------------
;* Driver static storage.
;*---------------------------------------------------------------------------

            org         V.SCF
DART0       rmb         2               ; base address of 68681/DUART chip
MSKART      rmb         3               ; interrupt packet
INTMI       rmb         1               ; DUART receiver interrupt mask
INTMO       rmb         1               ; DUART transmitter interrupt mask
SAVCHAR     rmb         1               ; save area for received character
IPTRH       rmb         1               ; input buffer next-in pointer (head)
IPTRT       rmb         1               ; input buffer next-out pointer (tail)
ICNT        rmb         1               ; input buffer byte count
OPTRH       rmb         1               ; output buffer next-in pointer
OPTRT       rmb         1               ; output buffer next-out pointer
OCNT        rmb         1               ; output buffer byte count
RTSBIT      rmb         1               ; OPR bit of this port's RTS (OP0 or OP1)
SSigPID     rmb         1               ; SS.SSig process ID (MUST precede SSigSig)
SSigSig     rmb         1               ; SS.SSig signal code
ARTINTP     rmb         2               ; pointer to memory copy of IMR register
ARTACRP     rmb         2               ; pointer to memory copy of ACR register
OUTBUF      rmb         BSIZE           ; output buffer
INBUF       rmb         BSIZE           ; input buffer

DatSiz      equ         .

;*---------------------------------------------------------------------------
;* Module header.
;*---------------------------------------------------------------------------

Rev         set         0               ; (0..15)
Edition     set         6               ; (0..255)
TypLng      set         Drivr+Objct
AtrRev      set         ReEnt+Rev

            mod         ModSizD,ModNamD,TypLng,AtrRev
            fdb         JmpDart         ; offset to driver jump table
            fdb         DatSiz          ; size of device static storage

            fcb         CAP.ALL         ; capabilities = all

ModNamD     fcs         "sc68681"       ; module name
            fcb         Edition         ; module edition

;*---------------------------------------------------------------------------
;* Baud rate code table, set 2 (ACR bit 7 = 1), 3.6864 MHz crystal.
;* IT.BAU: 0=110 1=300 2=600 3=1200 4=2400 5=4800 6=9600 7=19200
;*---------------------------------------------------------------------------

TBAUDR       fcb         $11             ; 110 B baud rate codes
             fcb         $44             ; 300 B
             fcb         $55             ; 600 B
             fcb         $66             ; 1200 B
             fcb         $88             ; 2400 B
             fcb         $99             ; 4800 B
             fcb         $BB             ; 9600 B
             fcb         $CC             ; 19200 B

SharMem      fcs        'sc68681m'      ; shared memory module

;*---------------------------------------------------------------------------
;* DUART driver jump table.
;*---------------------------------------------------------------------------

JmpDart     equ         *
            lbra        ARTINIT         ; initialize driver
            lbra        ARTINCH         ; get character from port
            lbra        ARTOUTC         ; output character to port
            lbra        ARTGET          ; get status
            lbra        ARTSET          ; set status
            lbra        ARTCLOS         ; close driver

;*---------------------------------------------------------------------------
;* ARTINIT - Initialize this device driver.
;*
;* IN: U  address of static storage
;*     Y  address of initial device descriptor module
;* OUT: CC.C  0/CC = OK
;* ERR: CC.C  1/CS = error
;*      B  OS-9 error code
;*---------------------------------------------------------------------------

ARTINIT     equ         *

            pshs        Y               ; save device descriptor
            pshs        U               ; save static storage
            leax        SharMem,PCR     ; shared memory module name
            clra                        ; any type/language
            os9         F$Link          ; U = its module header
            lbcs        AI91            ; error - restore and exit
            leay        V.SCF,U         ; register copies start at V.SCF
            puls        U               ; restore static storage
            sty         ARTINTP,U       ; IMR copy
            leay        1,Y
            sty         ARTACRP,U       ; ACR copy
            puls        Y               ; restore device descriptor for IT.*

;* Port A at chip base ($EF60), port B at chip base + 8 ($EF68)
            ldd         V.PORT,U
            andb        #$F0
            std         DART0,U         ; the real duart base address
            ldb         V.PORT+1,U
            bitb        #$08            ; port B?
            bne         AI04            ; .Y
            lda         #$01            ; port A: TxRDYA = ISR bit 0
            ldb         #$01            ;         RTS = OP0
            bra         AI05
AI04        lda         #$10            ; port B: TxRDYB = ISR bit 4
            ldb         #$02            ;         RTS = OP1
AI05        sta         INTMO,U
            lsla                        ; RxRDY is the next ISR bit
            sta         INTMI,U
            stb         RTSBIT,U

            lda         IT.PAR,Y        ; get parity and word length
            pshs        A
            ldx         V.PORT,U
            lda         #RstRX.D
            sta         CR_D,X          ; reset Rx
            lda         #RstTX.D
            sta         CR_D,X          ; reset Tx
            lda         #RstSt.D
            sta         CR_D,X          ; reset error status

;* --- WARNING---
;* THE BAUD RATE SET (ACR BIT 7) IS FOR BOTH CHANNELS A & B !!!
            ldx         DART0,U
            lda         [ARTACRP,U]     ; ACR copy: $80 = set 2, no IP change IRQ
            sta         ACR_D,X
            ldb         RTSBIT,U
            stb         OPRset_D,X      ; assert RTS; with RxRTS the 68681
                                        ; negates it when its FIFO is full

            lda         IT.BAU,Y        ; get baud rate code
            anda        #$0F
            cmpa        #7              ; 0-7 is valid?
            bls         AI02
            lda         #6              ; .N, default to 9600 B
AI02        leax        TBAUDR,PCR
            lda         A,X
            ldx         V.PORT,U
            sta         CSR_D,X
            lda         #RstMR.D        ; MR pointer to MR1
            sta         CR_D,X
            lda         0,S             ; parity and bits per word
            bmi         AI06
            lda         #$13            ; default = no parity / 8 bits
AI06        anda        #$1F            ; parity mode, parity type, bits
            ora         #MR1RxRTS       ; hardware RTS
            sta         MR1_D,X
            lda         ,S+             ; stop bits
            bmi         AI08
            lda         #$20            ; default to 2
AI08        lsra
            lsra
            anda        #$08            ; bit 3: 0 = 1 stop, 1 = 2 stop
            ora         #MR2TxCTS+$07   ; hardware CTS, 1 or 2 stop
            sta         MR2_D,X
            lda         #EnTR.D         ; enable rx & tx
            sta         CR_D,X

AI15        lda         SR_D,X          ; flush rx fifo
            bita        #RxRDY.D
            beq         AI20
            lda         RHR_D,X
            bra         AI15
AI20        lda         #RstSt.D        ; reset error status
            sta         CR_D,X
            clr         V.ERR,U

            clr         MSKART,U        ; FLIP BYTE = 0
            lda         INTMI,U
            ora         INTMO,U
            sta         MSKART+1,U      ; MASK BYTE
            lda         #100
            sta         MSKART+2,U      ; PRIORITY

            ldd         DART0,U
            addd        #ISR_D          ; ISR register is base address + 5
            leax        MSKART,U
            leay        DIRQ,PCR
            os9         F$IRQ           ; add to IRQ polling table
            bcs         AI90

            pshs        CC
            orcc        #IntMasks
            clr         IPTRH,U         ; clear pointers and counts
            clr         IPTRT,U
            clr         OPTRH,U
            clr         OPTRT,U
            clr         ICNT,U
            clr         OCNT,U
            clr         SSigPID,U
            lda         INTMI,U         ; enable receive interrupt
            lbsr        DINTON
            puls        CC
            clrb
AI90        rts

AI91        puls        U,Y             ; F$Link failed - drop saved regs
            rts

;*---------------------------------------------------------------------------
;* ARTCLOS - Deactivate this device driver.
;*
;* IN: U  address of static storage
;* OUT: CC.C  0/CC = OK
;* ERR: CC.C  1/CS = error
;*      B  OS-9 error code
;*---------------------------------------------------------------------------

ARTCLOS     equ         *

            ldx         >D.Proc
            lda         P$ID,X
            sta         V.BUSY,U
            sta         V.LPRC,U
AT10        orcc        #IntMasks
            tst         OCNT,U          ; output still to send?
            beq         AT50            ; .N
            lbsr        SLEEP           ; .Y, wait for the IRQ to drain it
            beq         AT10            ; woken normally, check again
            orcc        #IntMasks       ; signal: drop the rest of the output,
            clr         OCNT,U          ;    but still release the port below

AT50        lda         INTMI,U         ; disable both interrupts
            ora         INTMO,U
            lbsr        DINTOFF
            clr         SSigPID,U
            andcc       #^IntMasks

            leay        DIRQ,PCR        ; load irq service routine address
            ldx         #0              ; remove device from polling table
            os9         F$IRQ
            rts

;*---------------------------------------------------------------------------
;* ARTINCH - Read one character from the port buffer.
;*
;* IN: U  address of static storage
;*     Y  address of path descriptor
;* OUT: CC.C  0/CC = OK
;*      A  received character
;* ERR: CC.C  1/CS = error
;*      B  OS-9 error code
;*---------------------------------------------------------------------------

ARTINCH     equ         *

            orcc        #IntMasks
            tst         ICNT,U          ; is a character waiting in the buffer?
            bne         AN50            ; .Y

            bsr         SLEEP           ; .N
            beq         ARTINCH         ; no signal waiting
            coma                        ; return return-signal as error
            rts

AN50        leax        INBUF,U
            ldb         IPTRT,U
            abx                         ; X + B, B unsigned (B,X is signed)
            lda         ,X              ; get charac
            pshs        A               ; keep it across the Rx check
            incb
            andb        #MSKCNTR
            stb         IPTRT,U
            dec         ICNT,U
            lda         ICNT,U          ; drained to the low-water mark?
            cmpa        #BLOW
            bhi         AN55            ; .N
            lda         INTMI,U         ; .Y, read the FIFO again: the 68681
            lbsr        DINTON          ;    asserts RTS as it empties
AN55        puls        A               ; character for SCF

            ldb         V.ERR,U         ; any errors?
            beq         AN60            ; .N
            stb         PD.ERR,Y        ; .Y
            clr         V.ERR,U
            andcc       #^IntMasks
            comb
            ldb         #E$Read
            rts
AN60        andcc       #^(IntMasks+Carry)
            rts

;*---------------------------------------------------------------------------
;* ARTOUTC - Write one character into the port buffer.
;*
;* IN: U  address of static storage
;*     Y  address of path descriptor
;*     A  character to write
;* OUT: CC.C  0/CC = OK
;* ERR: CC.C  1/CS = error
;*      B  OS-9 error code
;*---------------------------------------------------------------------------

ARTOUTC     equ         *

            orcc        #IntMasks
            ldb         OCNT,U          ; any space left in transmit buffer?
            cmpb        #BFULL
            blo         AO50            ; .Y

            pshs        A
            bsr         SLEEP
            puls        A
            beq         ARTOUTC         ; no signal waiting
            coma                        ; return return-signal as error
            rts

AO50        pshs        Y               ; SCF's path descriptor (TXKICK uses Y)
            leax        OUTBUF,U
            ldb         OPTRH,U
            abx                         ; X + B, B unsigned (B,X is signed)
            sta         ,X              ; store charac
            incb
            andb        #MSKCNTR
            stb         OPTRH,U
            inc         OCNT,U
            lda         INTMO,U         ; buffer being filled, so
            lbsr        DINTON          ;    re-enable the Tx interrupt
            lbsr        TXKICK          ;    and send now if TxRDY is set
            puls        Y
            andcc       #^(IntMasks+Carry)
            rts

;* Sleep until buffer ready. Entered with IRQs masked.
;* OUT: Z = 1 woken normally, Z = 0 and B = signal or error to return.
;* The S$Wake sent by the IRQ stays in P$Signal: the kernel processes
;* signals only on the return to user state. It is not an error here.

SLEEP       ldb         V.BUSY,U
            stb         V.WAKE,U
            andcc       #^IntMasks

            ldx         #0
            os9         F$Sleep         ; sleep until the IRQ wakes us

            ldx         >D.Proc
            ldb         P$State,X
            bitb        #Condem         ; process killed?
            bne         SL20            ; .Y
            ldb         P$Signal,X      ; signal waiting?
            cmpb        #S$Wake         ; our own wake-up?
            bne         SL10            ; .N, report it (B = 0 is no signal)
            clr         P$Signal,X      ; .Y, consumed here
            clrb
SL10        tstb
            rts
SL20        ldb         #E$PrcAbt
            rts

;*---------------------------------------------------------------------------
;* DIRQ - Interrupt handler routine for 68681/DUART.
;*
;* IN: U  address of static storage
;*     A  contents of irq status register ISR (after flipping/masking bits)
;* OUT: CC.C  0 = handled, 1 = not from this port
;*---------------------------------------------------------------------------

DIRQ        equ         *

            ldy         V.PORT,U
            anda        [ARTINTP,U]     ; only the sources enabled now

            bita        INTMO,U
            lbne        DIRQO

            bita        INTMI,U
            lbne        DIRQI

            comb                        ; interrupt not caused by this port
            rts

;*---------------------------------------------------------------------------
;* DIRQO - Output interrupt handler routine. With MR2 TxCTS the 68681
;*         itself holds the character while CTS is negated: TxRDY stays
;*         clear, so no Tx interrupt comes until the PC is ready.
;*
;* IN: U  address of static storage
;*     Y  base address of port A or B
;*---------------------------------------------------------------------------

DIRQO       equ         *

            leax        OUTBUF,U
            ldb         OPTRT,U
            abx                         ; X + B, B unsigned (B,X is signed)
            lda         ,X              ; get character from buffer
            sta         THR_D,Y         ; send to transmitter
            incb                        ; adjust pointer
            andb        #MSKCNTR
            stb         OPTRT,U
            dec         OCNT,U          ; TX buffer now empty?
            beq         DO60            ; .Y
            ldb         OCNT,U          ; .N, reached wakeup level?
            cmpb        #BWAKE
            lbeq        WAKE            ; .Y
            clrb                        ; .N, handled
            rts
DO60        lda         INTMO,U         ; .Y, disable TxRdy interrupts
            lbsr        DINTOFF
            lbra        WAKE

;*---------------------------------------------------------------------------
;* DIRQI - Input interrupt handler routine.
;*
;* IN: U  address of static storage
;*     Y  base address of port A or B
;*---------------------------------------------------------------------------

;* Empties the receive FIFO (up to 3 characters + the shift register) in one
;* interrupt, stopping when the buffer reaches BHIGH (Rx interrupt off). The
;* sleeping reader, if any, is woken once at the end.

DIRQI       equ         *

DI05        lda         SR_D,Y          ; status of the next character
            bita        #RxRDY.D        ; FIFO empty?
            beq         WAKE            ; .Y, done: wake the reader
            anda        #RxERR.D
            beq         DI10
            ora         V.ERR,U         ; update cumulative errors
            sta         V.ERR,U
            lda         #RstSt.D        ; reset error status
            sta         CR_D,Y
DI10        lda         RHR_D,Y         ; get character from receiver
            sta         SAVCHAR,U

            ldb         ICNT,U
            cmpb        #BFULL          ; buffer already full?
            blo         DI50
            lda         V.ERR,U         ; .Y, overrun error, character lost
            ora         #ErOvr.D
            sta         V.ERR,U
            bra         DI60

DI50        leax        INBUF,U
            ldb         IPTRH,U
            abx                         ; X + B, B unsigned (B,X is signed)
            sta         ,X              ; store character
            incb
            andb        #MSKCNTR
            stb         IPTRH,U
            inc         ICNT,U
            lda         ICNT,U          ; reached the high-water mark?
            cmpa        #BHIGH
            blo         DI55            ; .N
            lda         INTMI,U         ; .Y, stop reading the FIFO: it fills
            lbsr        DINTOFF         ;    and the 68681 negates RTS

DI55        lda         SSigPID,U       ; data-ready signal wanted?
            beq         DI60            ; .N
            clr         SSigPID,U       ; .Y, one signal only
            ldb         SSigSig,U
            os9         F$Send

DI60        lda         SAVCHAR,U
            anda        #$7F
            beq         DI90            ; pass nulls thru
            cmpa        V.PCHR,U        ; pause character?
            bne         DI65            ; .N
            ldx         V.DEV2,U        ; get address of output device
            beq         DI90            ; .none
            sta         V.PAUS,X        ; request pause
            bra         DI90
DI65        ldb         #S$Intrpt       ; (INTERRUPT SIGNAL)
            cmpa        V.INTR,U        ; keyboard interrupt?
            beq         DI70            ; .Y
            ldb         #S$Abort        ; (ABORT SIGNAL)
            cmpa        V.QUIT,U        ; keyboard abort?
            bne         DI90            ; .N
DI70        lda         V.LPRC,U        ; signal the last process
            beq         DI90
            os9         F$Send

DI90        lda         [ARTINTP,U]     ; Rx interrupt still on?
            bita        INTMI,U
            lbne        DI05            ; .Y, next character of the FIFO

WAKE        ldb         #S$Wake         ; wakeup signal
            lda         V.WAKE,U        ; get process id
WI50        beq         WK90            ; .none, return
            os9         F$Send          ; send signal
WK90        clr         V.WAKE,U
            andcc       #^Carry         ; handled
            rts

;*---------------------------------------------------------------------------
;* ARTGET - Get Status.
;*
;* IN: U  address of static storage
;*     Y  address of path descriptor
;*     A  status code
;* OUT: CC.C  0/CC = OK
;* ERR: CC.C  1/CS = error
;*      B  OS-9 error code
;*---------------------------------------------------------------------------

ARTGET      equ         *
            cmpa        #SS.Ready       ; data available?
            bne         AG60            ; .N
            ldb         ICNT,U          ; byte count (at most 255)
            beq         AG50            ; none
            ldx         PD.RGS,Y
            stb         R$B,X           ; count in caller's B
            clrb
            rts
AG50        comb
            ldb         #E$NotRdy
            rts

AG60        cmpa        #SS.EOF         ; SCF devices never return EOF
            bne         AS80
            clrb
            rts

;*---------------------------------------------------------------------------
;* ARTSET - Set Status.
;*
;* IN: U  address of static storage
;*     Y  address of path descriptor
;*     A  status code
;* OUT: CC.C  0/CC = OK
;* ERR: CC.C  1/CS = error
;*      B  OS-9 error code
;*---------------------------------------------------------------------------

ARTSET      equ         *
            cmpa        #SS.SSig        ; signal on data ready
            bne         AS20
            lda         PD.CPR,Y        ; current process ID
            ldx         PD.RGS,Y
            ldb         R$X+1,X         ; signal code in LSB of caller's X
            pshs        CC
            orcc        #IntMasks
            tst         ICNT,U          ; data already here?
            bne         AS10            ; .Y, signal now
            std         SSigPID,U       ; .N, the IRQ sends it
            puls        CC
            clrb
            rts
AS10        puls        CC
            os9         F$Send
            clrb
            rts

AS20        cmpa        #SS.Relea       ; release the signal
            bne         AS80
            lda         PD.CPR,Y
            cmpa        SSigPID,U       ; ours?
            bne         AS30
            clr         SSigPID,U
AS30        clrb
            rts

AS80        comb
            ldb         #E$UnkSvc
            rts

;*---------------------------------------------------------------------------
;* TXKICK - If TxRDY is set, send one byte from OUTBUF (poll path).
;*
;* IN: U  static storage pointer
;*---------------------------------------------------------------------------
TXKICK      equ         *

            tst         OCNT,U
            beq         TXKX
            ldy         V.PORT,U
            lda         SR_D,Y
            bita        #TxRDY.D
            beq         TXKX
            leax        OUTBUF,U
            ldb         OPTRT,U
            abx                         ; X + B, B unsigned (B,X is signed)
            lda         ,X
            sta         THR_D,Y
            incb
            andb        #MSKCNTR
            stb         OPTRT,U
            dec         OCNT,U
            beq         TXKOFF
            rts
TXKOFF      lda         INTMO,U
            lbsr        DINTOFF
TXKX        rts

;*---------------------------------------------------------------------------
;* DINTON - Update the 68681/DUART write-only register IMR, setting individual
;*          bits ON to enable those interrupt sources, and remembering the
;*          current value.
;*
;* IN: A  bits to be changed are 1's, bits to be left unchanged are 0's
;*     U  static storage pointer
;* OUT: A  new ARTINT contents
;*---------------------------------------------------------------------------

DINTON      pshs    Y,CC
            orcc    #IntMasks           ; disable interrupts
            ora     [ARTINTP,U]         ; set specified bits
            bra     DINT50

;*---------------------------------------------------------------------------
;* DINTOFF - Update the 68681/DUART write-only register IMR, setting individual
;*           bits OFF to disable those interrupt sources, and remembering the
;*           current value.
;*
;* IN: A  bits to be changed are 1's, bits to be left unchanged are 0's
;*     U  static storage pointer
;* OUT: A  new ARTINT contents
;*---------------------------------------------------------------------------

DINTOFF     pshs    Y,CC
            orcc    #IntMasks           ; disable interrupts
            coma                        ; clear specified bits
            anda    [ARTINTP,U]

DINT50      sta     [ARTINTP,U]         ; update variable and DUART register
            ldy     DART0,U
            sta     IMR_D,Y             ; write IMR register
            puls    Y,CC,PC             ; restore interrupts, return to caller

            emod
ModSizD     equ         *

            end
