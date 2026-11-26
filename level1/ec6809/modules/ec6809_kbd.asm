;*----------------------------------------------------------------------------*
;* FILE / MODULE: ec6809_kbd.asm / ec6809_kbd
;*
;* PURPOSE: SCF driver for the PS/2 keyboard of the EC-6809, input only.
;*          Step 2 of the video + keyboard console.
;*
;* An Arduino decodes the PS/2 keyboard and puts the ASCII code on port A of
;* the CPU board 6522 VIA ($EF80), then pulses a 1 ms negative strobe on CA1.
;* CA1 is set on the rising edge, at the end of the strobe (PCR bit 0 = 1, as
;* under FLEX), and interrupts. Reading port A at $EF81 (register 1, with
;* handshake) gives the code and clears the CA1 flag.
;*
;* The VIA is shared with the system tick (T1, clock module). This driver
;* only ever touches CA1: PCR bit 0, IER/IFR bit 1 (writes $82 and $02,
;* never $7F), and port A as input. The clock clears only its own T1 flag.
;*
;* Output: SCF sends what is written to a path to the path's own device,
;* and only the echo to the descriptor's echo device (IT.D2P, K1 itself).
;* This driver's Write discards the character.
;*
;* Ctrl-C, Ctrl-Q and the pause key send their signal (or pause) and are
;* not put in the buffer, so they do not show up again in the next line.
;*
;* Load it after boot:  load ec6809_kbd k1
;* Test:                shell </k1 >/term >>/term   (typing blind)
;*
;* Edition 1, 2026-Nov-26, Ph. Roehr. Input part from sc68681 edition 7.
;*----------------------------------------------------------------------------*

            nam         ec6809_kbd
            ttl         SCF driver for the PS/2 keyboard of the EC-6809

            ifp1
            use         defsfile
            endc

CA1Flag     equ         %00000010       ; CA1 bit in the VIA IFR and IER

BSIZE       equ         256             ; input buffer; INCB wraps a pointer
BFULL       equ         BSIZE-1         ; full: further keys are dropped

;*---------------------------------------------------------------------------
;* Driver static storage.
;*---------------------------------------------------------------------------

            org         V.SCF
KPKT        rmb         3               ; F$IRQ packet: flip, mask, priority
IPTRH       rmb         1               ; input buffer next-in pointer (head)
IPTRT       rmb         1               ; input buffer next-out pointer (tail)
ICNT        rmb         1               ; input buffer byte count
SSigPID     rmb         1               ; SS.SSig process ID (MUST precede SSigSig)
SSigSig     rmb         1               ; SS.SSig signal code
INBUF       rmb         BSIZE           ; input buffer

DatSiz      equ         .

;*---------------------------------------------------------------------------
;* Module header.
;*---------------------------------------------------------------------------

Rev         set         0
Edition     set         1
TypLng      set         Drivr+Objct
AtrRev      set         ReEnt+Rev

            mod         ModSiz,ModNam,TypLng,AtrRev
            fdb         JmpTab          ; offset to driver jump table
            fdb         DatSiz          ; size of device static storage

            fcb         UPDAT.          ; capabilities (the descriptor limits them)

ModNam      fcs         "ec6809_kbd"
            fcb         Edition

;*---------------------------------------------------------------------------
;* Driver jump table.
;*---------------------------------------------------------------------------

JmpTab      lbra        KInit
            lbra        KRead
            lbra        KWrite
            lbra        KGetSt
            lbra        KSetSt
            lbra        KTerm

;*---------------------------------------------------------------------------
;* KInit - port A input, CA1 on the rising edge, IRQ entry, CA1 interrupt on.
;*
;* IN: U  static storage, Y  device descriptor
;* OUT: CC.C 0, or CC.C 1 and B = error from F$IRQ
;*---------------------------------------------------------------------------

KInit       clr         IPTRH,U         ; empty buffer
            clr         IPTRT,U
            clr         ICNT,U
            clr         SSigPID,U
            clr         V.ERR,U

            ldx         V.PORT,U        ; the VIA
            pshs        CC
            orcc        #IntMasks
            clr         VIADDRA,X       ; port A: all inputs
            lda         VIAPCR,X
            ora         #$01            ; CA1 active on the rising edge
            sta         VIAPCR,X
            lda         #CA1Flag        ; CA1 interrupt off for now
            sta         VIAIER,X
            lda         VIAREGA,X       ; drop a key already waiting (clears CA1)
            puls        CC

            clr         KPKT,U          ; flip byte
            lda         #CA1Flag
            sta         KPKT+1,U        ; mask byte: CA1 in the IFR
            lda         #100
            sta         KPKT+2,U        ; priority
            ldd         V.PORT,U
            addd        #VIAIFR         ; status register to poll
            leax        KPKT,U
            leay        KIrq,PCR
            os9         F$IRQ           ; add to the IRQ polling table
            bcs         KI90

            ldx         V.PORT,U
            lda         #$80+CA1Flag    ; CA1 interrupt on
            sta         VIAIER,X
            clrb
KI90        rts

;*---------------------------------------------------------------------------
;* KTerm - CA1 interrupt off, IRQ entry removed. T1 is left alone.
;*---------------------------------------------------------------------------

KTerm       ldx         V.PORT,U
            lda         #CA1Flag        ; clears IER bit 1 only
            sta         VIAIER,X
            clr         SSigPID,U
            ldx         #0              ; remove the device from the polling table
            leay        KIrq,PCR
            os9         F$IRQ
            clrb
            rts

;*---------------------------------------------------------------------------
;* KWrite - output goes to the echo device (IT.D2P), never here. Discarded.
;*---------------------------------------------------------------------------

KWrite      clrb
            rts

;*---------------------------------------------------------------------------
;* KRead - one character from the buffer, sleeping while it is empty.
;*
;* IN: U  static storage, Y  path descriptor
;* OUT: CC.C 0 and A = character, or CC.C 1 and B = error or signal
;*---------------------------------------------------------------------------

KRead       orcc        #IntMasks
            tst         ICNT,U          ; a key waiting?
            bne         KR50            ; .Y
            bsr         KSleep          ; .N
            beq         KRead           ; woken by the IRQ, look again
            coma                        ; a signal: return it as the error
            rts

KR50        leax        INBUF,U
            ldb         IPTRT,U
            abx                         ; X + B, B unsigned (B,X is signed)
            lda         ,X
            incb
            stb         IPTRT,U
            dec         ICNT,U
            andcc       #^(IntMasks+Carry)
            rts

;* Sleep until a key comes. Entered with IRQs masked.
;* OUT: Z = 1 woken normally, Z = 0 and B = signal or error to return.
;* The S$Wake sent by the IRQ stays in P$Signal: the kernel processes
;* signals only on the return to user state. It is not an error here.

KSleep      ldb         V.BUSY,U
            stb         V.WAKE,U
            andcc       #^IntMasks
            ldx         #0
            os9         F$Sleep         ; sleep until the IRQ wakes us
            ldx         >D.Proc
            ldb         P$State,X
            bitb        #Condem         ; process killed?
            bne         KSL20           ; .Y
            ldb         P$Signal,X      ; signal waiting?
            cmpb        #S$Wake         ; our own wake-up?
            bne         KSL10           ; .N, report it (B = 0 is no signal)
            clr         P$Signal,X      ; .Y, consumed here
            clrb
KSL10       tstb
            rts
KSL20       ldb         #E$PrcAbt
            rts

;*---------------------------------------------------------------------------
;* KIrq - a key is on port A.
;*
;* IN: U  static storage
;* OUT: CC.C 0, handled
;*---------------------------------------------------------------------------

KIrq        ldx         V.PORT,U
            lda         VIAREGA,X       ; the key; clears the CA1 flag
            beq         KQ50            ; NUL: no control check, buffer it

            ldb         #S$Intrpt
            cmpa        V.INTR,U        ; interrupt key?
            beq         KQ20
            ldb         #S$Abort
            cmpa        V.QUIT,U        ; quit key?
            beq         KQ20
            cmpa        V.PCHR,U        ; pause key?
            bne         KQ50
            ldx         V.DEV2,U        ; echo device static storage
            beq         KQ90
            sta         V.PAUS,X        ; pause its output
            bra         KQ90            ; the key is not buffered

KQ20        lda         V.LPRC,U        ; signal the last process
            beq         KQ90
            os9         F$Send
            bra         KQ90            ; the key is not buffered

KQ50        ldb         ICNT,U
            cmpb        #BFULL          ; buffer full?
            bhs         KQ90            ; .Y, the key is dropped
            leax        INBUF,U
            ldb         IPTRH,U
            abx                         ; X + B, B unsigned (B,X is signed)
            sta         ,X
            incb
            stb         IPTRH,U
            inc         ICNT,U

            lda         SSigPID,U       ; data-ready signal wanted?
            beq         KQ90            ; .N
            clr         SSigPID,U       ; .Y, one signal only
            ldb         SSigSig,U
            os9         F$Send

KQ90        ldb         #S$Wake         ; wake the reader, if one sleeps
            lda         V.WAKE,U
            beq         KQ95
            os9         F$Send
KQ95        clr         V.WAKE,U
            andcc       #^Carry         ; handled
            rts

;*---------------------------------------------------------------------------
;* KGetSt - Get Status.
;*
;* IN: U  static storage, Y  path descriptor, A  status code
;*---------------------------------------------------------------------------

KGetSt      cmpa        #SS.Ready       ; keys waiting?
            bne         KG60
            ldb         ICNT,U          ; byte count (at most 255)
            beq         KG50            ; none
            ldx         PD.RGS,Y
            stb         R$B,X           ; count in caller's B
            clrb
            rts
KG50        comb
            ldb         #E$NotRdy
            rts

KG60        cmpa        #SS.EOF         ; SCF devices never return EOF
            bne         KS80
            clrb
            rts

;*---------------------------------------------------------------------------
;* KSetSt - Set Status.
;*
;* IN: U  static storage, Y  path descriptor, A  status code
;*---------------------------------------------------------------------------

KSetSt      cmpa        #SS.SSig        ; signal on data ready
            bne         KS20
            lda         PD.CPR,Y        ; current process ID
            ldx         PD.RGS,Y
            ldb         R$X+1,X         ; signal code in LSB of caller's X
            pshs        CC
            orcc        #IntMasks
            tst         ICNT,U          ; data already here?
            bne         KS10            ; .Y, signal now
            std         SSigPID,U       ; .N, the IRQ sends it
            puls        CC
            clrb
            rts
KS10        puls        CC
            os9         F$Send
            clrb
            rts

KS20        cmpa        #SS.Relea       ; release the signal
            bne         KS80
            lda         PD.CPR,Y
            cmpa        SSigPID,U       ; ours?
            bne         KS30
            clr         SSigPID,U
KS30        clrb
            rts

KS80        comb                        ; SCF ignores E$UnkSvc for SS.Open,
            ldb         #E$UnkSvc       ;    SS.Close and SS.ComSt
            rts

            emod
ModSiz      equ         *

            end
