;*----------------------------------------------------------------------------*
;* FILE / MODULE: ec6809_6845.asm / ec6809_6845
;*
;* PURPOSE: SCF driver for the 6845 80 x 24 screen of the EC-6809 I/O board.
;*          Step 1: output only. Read returns E$BMode.
;*
;* The screen code is ported from the ESS540 monitor (ESS540_V7.asm), so the
;* screen understands the same Heath/Zenith H19 codes as under FLEX:
;*
;*   BS  cursor left           LF  line feed (scrolls)    CR  carriage return
;*   HT  next column multiple of 8                  BEL and other controls ignored
;*   ESC A/B/C/D  cursor up/down/right/left         ESC H  home
;*   ESC Y l c    cursor to line l-$20, column c-$20
;*   ESC I        reverse line feed (scrolls down on line 0)
;*   ESC E        clear screen and home
;*   ESC J / ESC b  erase to end / from beginning of screen
;*   ESC K / ESC o / ESC l  erase to end / from beginning / whole line
;*   ESC L / ESC M  insert / delete line
;*   ESC @ / ESC O  insert character mode on / off     ESC N  delete character
;*   ESC p / ESC q  reverse video on / off (bit 7 of the character)
;*   ESC F / ESC G  graphics characters on / off ($5E and up + $20)
;*   ESC v / ESC w  wrap at end of line on / off
;*   ESC j / ESC k  save / restore the cursor position
;*   ESC x 3 / ESC y 3  show control characters / interpret them again
;*   ESC x 4 / ESC y 4  block / underline cursor
;*   ESC x 5 / ESC y 5  cursor off / on
;*   ESC z        reset the screen
;*   ESC r c      (FLEX: VIA serial speed) the character c is skipped
;*
;* Scrolling moves the 6845 start address (R12/R13) by one line and clears
;* only the new line. The 2 KB video RAM wraps at $7FF, the 6845 addresses
;* go on growing; the CPU masks them with $07FF.
;*
;* Changes from the ESS540 code:
;*   - Variables in the driver static storage, not at $DE92-$DEA9.
;*   - ESC k restores the line and column only, in the current screen
;*     (ESS540 also restored the screen origin of the time of ESC j).
;*   - Erasing from a position to the same position erases one character
;*     (ESS540 then erased the whole video RAM, for example ESC o in
;*     column 0).
;*   - An ESC Y line out of range keeps the current line and still takes
;*     the column (ESS540 took the next character as a line again).
;*   - ESC r and ESC z do not touch the VIA (the system tick runs on it).
;*   - The 6845 table R0-R15 is in the device descriptor, after the SCF
;*     table, so the screen timing can change without a new driver.
;*
;* Hardware: CRTC register select at the descriptor port ($EC00), data at
;* port + 1, video RAM $E000-$E7FF (VRAMBase). Both are in the I/O area,
;* which the kernel keeps out of the RAM pool, and which Level 2 on the V6
;* board does not translate.
;*
;* Load it after boot:  load ec6809_6845 v1
;*
;* Edition 1, 2026-Nov-26, Ph. Roehr
;*----------------------------------------------------------------------------*

            nam         ec6809_6845
            ttl         SCF driver for the 6845 screen of the EC-6809

            ifp1
            use         defsfile
            endc

;* Screen geometry. The video RAM holds 25.6 lines of 80 characters.
SCRCOL      equ         80              ; characters a line
SCRLIN      equ         24              ; lines on the screen
VRMASK      equ         $07             ; high byte mask, 2 KB video RAM

;*---------------------------------------------------------------------------
;* Driver static storage.
;*---------------------------------------------------------------------------

            org         V.SCF
VGRADR      rmb         2               ; routine for the next character
VSCORG      rmb         2               ; screen origin, 6845 R12/R13 (MUST precede VCURPO)
VCURPO      rmb         2               ; cursor address, 6845 R14/R15
VCOL        rmb         1               ; cursor column 0-79 (MUST precede VLIN)
VLIN        rmb         1               ; cursor line 0-23
VLINAD      rmb         2               ; address of the cursor line, column 0
VSAVCL      rmb         2               ; ESC j column and line
VINSRT      rmb         1               ; non zero: insert character mode
VREVRS      rmb         1               ; $80: reverse video
VGRAPH      rmb         1               ; $20: graphics characters
VNOWRP      rmb         1               ; non zero: no wrap at end of line
VCURSH      rmb         1               ; 6845 R10, cursor start and blink
VTRANS      rmb         1               ; non zero: control characters shown
VCRTAB      rmb         2               ; 6845 table R0-R15 in the descriptor

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

ModNam      fcs         "ec6809_6845"
            fcb         Edition

;*---------------------------------------------------------------------------
;* Driver jump table.
;*---------------------------------------------------------------------------

JmpTab      lbra        VInit
            lbra        VRead
            lbra        VWrite
            lbra        VGetSt
            lbra        VSetSt
            lbra        VTerm

;*---------------------------------------------------------------------------
;* VInit - set up the 6845 and clear the screen.
;*
;* IN: U  static storage, Y  device descriptor
;* OUT: CC.C 0
;*---------------------------------------------------------------------------

VInit       ldb         M$Opt,Y         ; the 6845 table follows the SCF table
            leax        M$DTyp,Y
            abx
            stx         VCRTAB,U
            bsr         VReset          ; 6845, variables, clear screen, home
            clrb
            rts

;*---------------------------------------------------------------------------
;* VTerm - nothing to release. The screen keeps its last contents.
;*---------------------------------------------------------------------------

VTerm       clrb
            rts

;*---------------------------------------------------------------------------
;* VRead - no keyboard yet.
;*---------------------------------------------------------------------------

VRead       comb
            ldb         #E$BMode
            rts

;*---------------------------------------------------------------------------
;* VGetSt / VSetSt.
;*
;* IN: U  static storage, Y  path descriptor, A  status code
;*---------------------------------------------------------------------------

VGetSt      cmpa        #SS.ScSiz       ; screen size?
            bne         VGS10
            ldx         PD.RGS,Y
            ldd         #SCRCOL
            std         R$X,X           ; columns
            ldd         #SCRLIN
            std         R$Y,X           ; lines
            clrb
            rts
VGS10       cmpa        #SS.EOF         ; SCF devices never return EOF
            bne         VGS20
            clrb
            rts
VGS20       cmpa        #SS.Ready       ; no input on this device
            bne         VSetSt
            comb
            ldb         #E$NotRdy
            rts

VSetSt      comb                        ; SCF ignores E$UnkSvc for SS.Open,
            ldb         #E$UnkSvc       ;    SS.Close and SS.ComSt
            rts

;*---------------------------------------------------------------------------
;* VWrite - put one character on the screen.
;*
;* IN: U  static storage, Y  path descriptor (kept for SCF), A  character
;* OUT: CC.C 0
;*---------------------------------------------------------------------------

VWrite      pshs        Y
            jsr         [VGRADR,U]      ; normal character or ESC sequence
            puls        Y
            clrb
            rts

;* Make X the routine for the next character.
VState      stx         VGRADR,U
            rts

;*---------------------------------------------------------------------------
;* Reset: 6845 registers from the descriptor table, every variable, clear
;* screen, home. ESC z comes here too.
;*---------------------------------------------------------------------------

VReset      ldx         V.PORT,U
            ldy         VCRTAB,U
            clra                        ; register 0
VR10        ldb         ,Y+
            sta         ,X              ; register number
            stb         1,X             ; its value
            inca
            cmpa        #16             ; R0-R15
            bne         VR10
            ldy         VCRTAB,U
            lda         10,Y            ; R10, cursor start and blink
            sta         VCURSH,U
            ldd         #0
            std         VSCORG,U        ; as in the table (R12-R15 = 0)
            std         VCURPO,U
            std         VLINAD,U
            std         VCOL,U          ; column and line
            std         VSAVCL,U
            clr         VINSRT,U
            clr         VREVRS,U
            clr         VGRAPH,U
            clr         VNOWRP,U
            clr         VTRANS,U
            leax        VNorm,PCR
            stx         VGRADR,U
            lbra        VClrSc           ; clear screen and home

;*---------------------------------------------------------------------------
;* Write R12-R15 (screen origin and cursor) from VSCORG and VCURPO.
;* A, B and X destroyed. Y kept.
;*---------------------------------------------------------------------------

VCrtcP      pshs        Y
            ldx         V.PORT,U
            leay        VSCORG,U
            ldb         #12             ; R12
VCP10       lda         ,Y+
            stb         ,X
            sta         1,X
            incb
            cmpb        #16             ; stop after R15
            bne         VCP10
            puls        Y,PC

;* X = X AND $07FF. A and B kept.
VLimX       pshs        D
            tfr         X,D
            anda        #VRMASK
            tfr         D,X
            puls        D,PC

;*---------------------------------------------------------------------------
;* Normal state: print, or handle a control character.
;*---------------------------------------------------------------------------

VNorm       bita        #$60            ; $20-$7F or $A0-$FF?
            bne         VPrint          ; .Y, a character to show
            tst         VTRANS,U        ; control characters shown?
            bne         VPrint          ; .Y
            cmpa        #C$BSP
            lbeq        VLeft
            cmpa        #C$LF
            lbeq        VLinFd
            cmpa        #C$CR
            lbeq        VCarRt
            cmpa        #$09            ; horizontal tab
            lbeq        VHTab
            cmpa        #$1B            ; ESC
            bne         VRts            ; other controls, BEL included: nothing
            leax        VEsc,PCR
            lbra        VState

;* Put A at the cursor and move right. Insert mode shifts the end of the
;* line right first. At column 79: new line if wrap is on.
VPrint      tst         VINSRT,U
            bne         VInsCh
            ldx         VCURPO,U
            bsr         VLimX
VPut        cmpa        #$5E            ; graphics offset from $5E up
            blo         VPut10
            adda        VGRAPH,U
VPut10      ora         VREVRS,U        ; reverse video
            sta         VRAMBase,X
            ldb         VCOL,U
            cmpb        #SCRCOL-1       ; last column?
            blo         VRight          ; .N
            tst         VNOWRP,U        ; .Y, wrap?
            lbeq        VNewLn          ; .Y, CR and LF
            rts                         ; .N, stay on the last column

;* Insert mode: move the characters from the cursor to the end of the
;* line one place right (the last one is lost), then put A.
VInsCh      pshs        A
            ldx         VCURPO,U
            ldb         #SCRCOL-1
            subb        VCOL,U          ; characters to move
            abx                         ; X = last column of the line
            bsr         VLimX
            tstb
            beq         VIC30
VIC10       leax        -1,X
            cmpx        #0              ; below the start of the video RAM?
            bpl         VIC20           ; .N
            lda         VRAMBase+$7FF   ; .Y, $7FF goes to $000
            sta         VRAMBase
            ldx         #$07FF
            bra         VIC25
VIC20       lda         VRAMBase,X
            sta         VRAMBase+1,X
VIC25       decb
            bne         VIC10
VIC30       puls        A
            bra         VPut            ; X = the cursor

;*---------------------------------------------------------------------------
;* Cursor moves.
;*---------------------------------------------------------------------------

;* ESC C - one column right, not past column 79.
VRight      lda         VCOL,U
            cmpa        #SCRCOL-1
            bhs         VRts
            inc         VCOL,U
            ldd         VCURPO,U
            addd        #1
VSetCP      std         VCURPO,U
            lbra        VCrtcP

VRts        rts

;* BS, ESC D - one column left, not before column 0.
VLeft       tst         VCOL,U
            beq         VRts
            dec         VCOL,U
            ldd         VCURPO,U
            subd        #1
            bra         VSetCP

;* ESC B - one line down, no scroll.
VDown       lda         #SCRLIN-1
            cmpa        VLIN,U
            bls         VRts
            inc         VLIN,U
            bsr         VDown1
            lbra        VCrtcP

;* Cursor and line address one line down.
VDown1      ldd         VCURPO,U
            addd        #SCRCOL
            std         VCURPO,U
            ldd         VLINAD,U
            addd        #SCRCOL
            std         VLINAD,U
            rts

;* ESC A - one line up, no scroll.
VUp         lda         VLIN,U
            beq         VRts
VUp10       dec         VLIN,U
            ldd         VCURPO,U
            subd        #SCRCOL
            std         VCURPO,U
            ldd         VLINAD,U
            subd        #SCRCOL
            std         VLINAD,U
            lbra        VCrtcP

;* ESC I - reverse line feed. On line 0 the screen scrolls down.
VRevLF      lda         VLIN,U
            bne         VUp10
            ldd         VSCORG,U        ; origin one line up
            subd        #SCRCOL
            std         VSCORG,U
            bsr         VClrLn          ; clear that new top line
            inc         VLIN,U          ; so that VUp10 brings it back to 0
            lbsr        VCrtcP
            bra         VUp10

;* CR - column 0.
VCarRt      ldx         VLINAD,U
            stx         VCURPO,U
            clr         VCOL,U
            lbra        VCrtcP

;* CR then LF (wrap at end of line).
VNewLn      bsr         VCarRt

;* LF - one line down; from the last line the screen scrolls up.
VLinFd      bsr         VDown1
            lda         VLIN,U
            inc         VLIN,U
            cmpa        #SCRLIN-1       ; was it the last line?
            lbne        VCrtcP          ; .N
            ldd         VLINAD,U        ; .Y, clear the new line,
            bsr         VClrLn
            dec         VLIN,U          ;    stay on the last line
            ldd         VSCORG,U        ;    and move the origin one line
            addd        #SCRCOL
            std         VSCORG,U
            lbra        VCrtcP

;* Clear the 80 characters from video address D.
VClrLn      anda        #VRMASK
            tfr         D,X
            lda         #C$SPAC
            ldb         #SCRCOL
VCL10       sta         VRAMBase,X
            leax        1,X
            cmpx        #$0800          ; end of the video RAM?
            bne         VCL20
            ldx         #0
VCL20       decb
            bne         VCL10
            rts

;* HT - right to the next column multiple of 8, not past column 72.
VHTab       lbsr        VRight
            ldb         VCOL,U
            cmpb        #72
            bgt         VHT90
            bitb        #$07
            bne         VHTab
VHT90       rts

;* ESC H - home.
VHome       ldd         VSCORG,U
            std         VCURPO,U
            std         VLINAD,U
            clr         VCOL,U
            clr         VLIN,U
            lbra        VCrtcP

;* Cursor to column VCOL, line VLIN of the current screen.
VGoto       lda         VLIN,U
            ldb         #SCRCOL
            mul
            addd        VSCORG,U
            std         VLINAD,U
            addb        VCOL,U
            adca        #0
            std         VCURPO,U
            lbra        VCrtcP

;* ESC j - save the column and line.
VSavCu       ldd         VCOL,U
            std         VSAVCL,U
            rts

;* ESC k - back to the saved column and line.
VRstCu       ldd         VSAVCL,U
            std         VCOL,U
            bra         VGoto

;*---------------------------------------------------------------------------
;* Erasing. VFill writes spaces from video address X to Y, both included,
;* wrapping at $7FF.
;*---------------------------------------------------------------------------

VFill       lbsr        VLimX
            tfr         Y,D
            anda        #VRMASK
            pshs        D               ; last address
            lda         #C$SPAC
VF10        sta         VRAMBase,X
            cmpx        ,S              ; last one done?
            beq         VF30
            leax        1,X
            cmpx        #$0800
            bne         VF10
            ldx         #0
            bra         VF10
VF30        puls        D,PC

;* ESC E - clear the whole video RAM, then home.
VClrSc       ldx         #0
            ldy         #$07FF
            bsr         VFill
            bra         VHome

;* ESC K - erase to the end of the line.
VEraEL       ldx         VCURPO,U
            ldb         #SCRCOL-1
            subb        VCOL,U
            leay        B,X             ; B is 0-79, positive
            bra         VFill

;* ESC o - erase from the start of the line to the cursor.
VEraBL       ldx         VLINAD,U
            ldy         VCURPO,U
            bra         VFill

;* ESC l - erase the whole line.
VEraLn       ldx         VLINAD,U
            leay        SCRCOL-1,X
            bra         VFill

;* ESC b - erase from the start of the screen to the cursor.
VEraBS       ldx         VSCORG,U
            ldy         VCURPO,U
            bra         VFill

;* ESC J - erase from the cursor to the end of the screen.
VEraES       ldx         VCURPO,U
            ldy         VSCORG,U
            leay        SCRCOL*SCRLIN-1,Y
            bra         VFill

;* ESC N - delete the character at the cursor; the end of the line moves
;* one place left and a space comes in at column 79.
VDelCh       ldx         VCURPO,U
            lbsr        VLimX
            ldb         VCOL,U
VN10        cmpb        #SCRCOL-1
            beq         VN30
            cmpx        #$07FF          ; next one at $000?
            bne         VN20
            lda         VRAMBase
            sta         VRAMBase+$7FF
            ldx         #0
            bra         VN25
VN20        lda         VRAMBase+1,X
            sta         VRAMBase,X
            leax        1,X
VN25        incb
            bra         VN10
VN30        lda         #C$SPAC
            sta         VRAMBase,X
            rts

;*---------------------------------------------------------------------------
;* Lines.
;*---------------------------------------------------------------------------

;* X = video address of screen line B, B = 80. A destroyed.
VLnAdr      lda         #SCRCOL
            mul
            addd        VSCORG,U
            anda        #VRMASK
            tfr         D,X
            ldb         #SCRCOL
            rts

;* Copy screen line B to line B+1. B kept.
VCpDn       pshs        B
            bsr         VLnAdr
VCD10       lda         VRAMBase,X
            leax        SCRCOL,X
            lbsr        VLimX
            sta         VRAMBase,X
            leax        -(SCRCOL-1),X
            lbsr        VLimX
            decb
            bne         VCD10
            puls        B,PC

;* Copy screen line B+1 to line B. B kept.
VCpUp       pshs        B
            bsr         VLnAdr
VCU10       leax        SCRCOL,X
            lbsr        VLimX
            lda         VRAMBase,X
            leax        -SCRCOL,X
            lbsr        VLimX
            sta         VRAMBase,X
            leax        1,X
            decb
            bne         VCU10
            puls        B,PC

;* ESC L - insert a line at the cursor line; the last line is lost.
VInsLn       ldb         #SCRLIN-2       ; line 22 goes to 23 first
VEL10       cmpb        VLIN,U
            blt         VEL20
            bsr         VCpDn
            decb
            bra         VEL10
VEL20       lbsr        VCarRt
            lbra        VEraLn          ; the cursor line is now empty

;* ESC M - delete the cursor line; the lines below move up and the last
;* line is cleared.
VDelLn       ldb         VLIN,U
VEM10       cmpb        #SCRLIN-1
            beq         VEM20
            bsr         VCpUp
            incb
            bra         VEM10
VEM20       lbsr        VCarRt
            ldx         VSCORG,U
            leax        SCRCOL*(SCRLIN-1),X
            leay        SCRCOL-1,X
            lbra        VFill

;*---------------------------------------------------------------------------
;* Modes.
;*---------------------------------------------------------------------------

VInsOn      lda         #1              ; ESC @ insert mode on
            sta         VINSRT,U
            rts
VInsOf       clr         VINSRT,U        ; ESC O insert mode off
            rts
VEscp       lda         #$80            ; ESC p reverse video on
            sta         VREVRS,U
            rts
VEscq       clr         VREVRS,U        ; ESC q reverse video off
            rts
VEscF       lda         #$20            ; ESC F graphics on
            sta         VGRAPH,U
            rts
VEscG       clr         VGRAPH,U        ; ESC G graphics off
            rts
VEscv       clr         VNOWRP,U        ; ESC v wrap on
            rts
VEscw       lda         #$FF            ; ESC w wrap off
            sta         VNOWRP,U
            rts

;*---------------------------------------------------------------------------
;* ESC sequences.
;*---------------------------------------------------------------------------

;* The character after ESC.
VEsc        leax        VEscY1,PCR      ; ESC Y line column
            cmpa        #'Y
            beq         VEsc90
            leax        VSkip1,PCR      ; ESC r speed: skipped
            cmpa        #'r
            beq         VEsc90
            leax        VEscX,PCR       ; ESC x n
            cmpa        #'x
            beq         VEsc90
            leax        VEscY,PCR       ; ESC y n
            cmpa        #'y
            beq         VEsc90
            leax        VNorm,PCR       ; one-character code: back to normal
            stx         VGRADR,U
            leax        VTab,PCR
VEsc10      tst         ,X              ; end of the table?
            beq         VRts2           ; .Y, unknown code: ignored
            cmpa        ,X
            beq         VEsc20
            leax        3,X
            bra         VEsc10
VEsc20      ldd         1,X             ; offset of the routine
            leax        VTab,PCR
            jmp         D,X
VEsc90      stx         VGRADR,U
VRts2       rts

;* ESC Y, first character: the line.
VEscY1      suba        #C$SPAC
            cmpa        #SCRLIN         ; out of range: keep the line
            bhs         VEY10
            sta         VLIN,U
VEY10       leax        VEscY2,PCR
            stx         VGRADR,U
            rts

;* ESC Y, second character: the column (79 at most).
VEscY2      suba        #C$SPAC
            cmpa        #SCRCOL
            blo         VEY20
            lda         #SCRCOL-1
VEY20       sta         VCOL,U
            leax        VNorm,PCR
            stx         VGRADR,U
            lbra        VGoto

;* ESC r: one character skipped.
VSkip1      leax        VNorm,PCR
            stx         VGRADR,U
            rts

;* ESC x n: 3 show control characters, 4 block cursor, 5 cursor off.
VEscX       leax        VNorm,PCR
            stx         VGRADR,U
            ldb         VCURSH,U
            cmpa        #'3
            bne         VEX10
            sta         VTRANS,U        ; non zero
            rts
VEX10       cmpa        #'4
            bne         VEX20
            andb        #$E0            ; start at scan line 0
            bra         VSetR10
VEX20       cmpa        #'5
            bne         VRts2
            andb        #$9F            ; blink bits 01: no cursor
            orb         #$20
            bra         VSetR10

;* ESC y n: 3 interpret control characters, 4 underline cursor, 5 cursor on.
VEscY       leax        VNorm,PCR
            stx         VGRADR,U
            ldb         VCURSH,U
            cmpa        #'3
            bne         VEY30
            clr         VTRANS,U
            rts
VEY30       cmpa        #'4
            bne         VEY40
            andb        #$60            ; start at scan line 8
            orb         #$08
            bra         VSetR10
VEY40       cmpa        #'5
            bne         VRts2
            orb         #$60            ; blink bits 11: blink 1/32
VSetR10     stb         VCURSH,U
            ldx         V.PORT,U
            lda         #10             ; R10
            sta         ,X
            stb         1,X
            rts

;* ESC z - reset.
VEscz       lbra        VReset

;* One-character ESC codes: character, offset of the routine from VTab.
VTab        fcb         'H
            fdb         VHome-VTab
            fcb         'C
            fdb         VRight-VTab
            fcb         'D
            fdb         VLeft-VTab
            fcb         'B
            fdb         VDown-VTab
            fcb         'A
            fdb         VUp-VTab
            fcb         'I
            fdb         VRevLF-VTab
            fcb         'j
            fdb         VSavCu-VTab
            fcb         'k
            fdb         VRstCu-VTab
            fcb         'E
            fdb         VClrSc-VTab
            fcb         '@
            fdb         VInsOn-VTab
            fcb         'O
            fdb         VInsOf-VTab
            fcb         'N
            fdb         VDelCh-VTab
            fcb         'K
            fdb         VEraEL-VTab
            fcb         'o
            fdb         VEraBL-VTab
            fcb         'l
            fdb         VEraLn-VTab
            fcb         'b
            fdb         VEraBS-VTab
            fcb         'J
            fdb         VEraES-VTab
            fcb         'M
            fdb         VDelLn-VTab
            fcb         'L
            fdb         VInsLn-VTab
            fcb         'p
            fdb         VEscp-VTab
            fcb         'q
            fdb         VEscq-VTab
            fcb         'F
            fdb         VEscF-VTab
            fcb         'G
            fdb         VEscG-VTab
            fcb         'z
            fdb         VEscz-VTab
            fcb         'v
            fdb         VEscv-VTab
            fcb         'w
            fdb         VEscw-VTab
            fcb         0               ; end of the table

            emod
ModSiz      equ         *

            end
