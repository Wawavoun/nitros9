********************************************************************
* Clock - Clock for NitrOS-9 Level 2 on the EC-6809 V6 CPU board
*
* The tick is T1 of the CPU board 6522 at $EF80, running free and
* reloading itself from its latch, TkPerSec times a second (as the
* Level 1 EC-6809 clock). Clock2 (clock2_ec6809rtc) reads the DS3231 once
* a minute through the I/O board EPROM.
*
* Taken from the Pico-Thing variant of level2/modules/clock.asm: no
* GIME, so every tick also polls the devices (D.Poll).
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   1      2026/11/23  Philippe Roehr
* Created from the Pico-Thing Level 2 clock, with the VIA T1 tick.

                    nam       Clock
                    ttl       Clock for the EC-6809 V6, Level 2

TkPerTS             equ       2         ticks per time slice
T1Flag              equ       %01000000 T1 bit in the VIA IFR and IER

                  IFP1
                    use       defsfile
                    use       cocovtio.d
                  ENDC

Edtn                equ       1
Vrsn                equ       0

                    mod       len,name,Systm+Objct,ReEnt+Vrsn,Init,0

name                fcs       "Clock"
                    fcb       Edtn

*
* Table to set up Service Calls
*
NewSvc              fcb       F$Time
                    fdb       F.Time-*-2
                    fcb       F$VIRQ
                    fdb       F.VIRQ-*-2
                    fcb       F$Alarm
                    fdb       F.ALARM-*-2
                    fcb       F$STime
                    fdb       F.STime-*-2
                    fcb       $80       end of service call table

*------------------------------------------------------------
*
* IRQ handler entry point
*
* Called by the kernel on every IRQ. A T1 interrupt is the tick: clear
* its flag and go to SvcVIRQ. Anything else goes to DoPoll.
*
SvcIRQ              lda       >VIA0Base+VIAIFR
                    anda      #T1Flag   T1 fired?
                    bne       YesClock

                    leax      DoPoll,pcr not the tick, poll other sources
                    lda       #$FF
                    sta       <D.QIRQ   flag as non-clock IRQ
                    bra       ContIRQ

YesClock            sta       >VIA0Base+VIAIFR A = T1Flag clears the T1 flag
                    ldx       <D.VIRQ   set VIRQ routine to be executed
                    clr       <D.QIRQ   flag as clock IRQ
ContIRQ             stx       <D.SvcIRQ
                    jmp       [D.XIRQ]  chain to kernel timeslice handler

*------------------------------------------------------------
*
* IRQ handling re-enters here on clock tick.
*
* Counts down VIRQ timers, updates system time, checks alarm.
*
SvcVIRQ             clra                flag for VIRQ pending
                    pshs      a
                    ldy       <D.CLTb   get address of VIRQ table
                    bra       virqent

virqloop            ldd       Vi.Cnt,x  decrement tick count
                    subd      #$0001
                    bne       notzero   is this one done?
                    lda       Vi.Stat,x should we reset?
                    bmi       doreset
                    lbsr      DelVIRQ   no, delete this entry
doreset             ora       #$01      mark VIRQ as triggered
                    sta       Vi.Stat,x
                    lda       #$80      add as interrupt source
                    sta       ,s
                    ldd       Vi.Rst,x  reset from reset count
notzero             std       Vi.Cnt,x
virqent             ldx       ,y++
                    bne       virqloop

                    puls      a         get VIRQ status
* No GIME: D.IRQS is never set by hardware, so poll the devices (the
* ACIA) on every tick.
                    bsr       DoPoll    poll all registered devices

KbdCheck            jsr       [>D.AltIRQ] update keyboard/mouse/etc.

                    dec       <D.Tick   end of second?
                    bne       VIRQend   no, skip time update
                    lda       #TkPerSec reset tick count
                    sta       <D.Tick

                    inc       <D.Sec    increment second
                    lda       <D.Sec
                    cmpa      #60       end of minute?
                    blo       VIRQend   no, skip minute update
                    clr       <D.Sec    reset seconds

                    ldx       <D.Clock2 call Clock2 GetTime: reads the RTC,
                    jsr       $03,x     or counts the minute itself

                    ldd       >WGlobal+G.AlPID
                    ble       VIRQend   no alarm set
                    ldd       >WGlobal+G.AlPckt+3
                    cmpd      <D.Hour
                    bne       VIRQend
                    ldd       >WGlobal+G.AlPckt+1
                    cmpd      <D.Month
                    bne       VIRQend
                    ldb       >WGlobal+G.AlPckt+0
                    cmpb      <D.Year
                    bne       VIRQend
                    ldd       >WGlobal+G.AlPID
                    cmpd      #1
                    beq       checkbel
                    os9       F$Send
                    bra       endalarm
checkbel            ldb       <D.Sec
                    andb      #$F0
                    beq       dobell
endalarm            ldd       #$FFFF
                    std       >WGlobal+G.AlPID
                    bra       VIRQend
dobell              ldx       >WGlobal+G.BelVec
                    beq       VIRQend
                    jsr       ,x
VIRQend             jmp       [>D.Clock] jump to kernel timeslice routine

*------------------------------------------------------------
*
* Poll interrupt sources
*
DoPoll              pshs      b         save B
                    clrb                clear "serviced" flag
DoPollLp            jsr       [>D.Poll] call poll routine
                    bcs       DoPollDn  no device found, done polling
                    incb                at least one device was serviced
                    bra       DoPollLp  check for more
* The last poll left carry set; B=0 must keep it set and B>0 must clear
* it (tstb does not touch carry), or the kernel treats a serviced IRQ as
* unclaimed and masks interrupts in the process it interrupted.
DoPollDn            cmpb      #1        carry set only if nothing was serviced
                    puls      b,pc      return; carry clear if serviced

*------------------------------------------------------------
*
* Handle F$VIRQ system call
*
F.VIRQ              pshs      cc
                    orcc      #IntMasks disable interrupts
                    ldy       <D.CLTb   address of VIRQ table
                    ldx       <D.Init   address of INIT
                    ldb       PollCnt,x number of polling table entries
                    ldx       R$X,u     zero means delete entry
                    beq       RemVIRQ
FindVIRQ            ldx       ,y++      is VIRQ entry null?
                    beq       AddVIRQ   if yes, add here
                    decb
                    bne       FindVIRQ
                    puls      cc
                    comb
                    ldb       #E$Poll
                    rts

AddVIRQ             leay      -2,y      point to first null VIRQ entry
                    ldx       R$Y,u
                    stx       ,y
                    ldy       R$D,u
                    sty       ,x
                    bra       virqexit

RemVIRQ             ldx       ,y++
                    beq       virqexit
                    cmpx      R$Y,u
                    bne       RemVIRQ
                    bsr       DelVIRQ
virqexit            puls      cc
                    clrb
                    rts

DelVIRQ             pshs      x,y
DelVLup             ldx       ,y++
                    stx       -4,y
                    bne       DelVLup
                    puls      x,y
                    leay      -2,y
                    rts

*------------------------------------------------------------
*
* Handle F$Alarm call
*
F.ALARM             ldx       #WGlobal+G.AlPckt
                    ldd       R$D,u
                    bne       DoAlarm
                    std       G.AlPID-G.AlPckt,x
                    rts

DoAlarm             tsta
                    bne       SetAlarm
                    cmpd      #1
                    bne       GetAlarm
SetAlarm            std       G.AlPID-G.AlPckt,x
                    ldy       <D.Proc
                    lda       P$Task,y
                    ldb       <D.SysTsk
                    ldx       R$X,u
                    ldu       #WGlobal+G.AlPckt
                    ldy       #5
                    bra       FMove

GetAlarm            cmpd      #2
                    bne       AlarmErr
                    ldd       G.AlPID-G.AlPckt,x
                    std       R$D,u
                    bra       RetTime
AlarmErr            comb
                    ldb       #E$IllArg
                    rts

*------------------------------------------------------------
*
* Handle F$Time system call
*
F.Time              ldx       #D.Time
RetTime             ldy       <D.Proc
                    ldb       P$Task,y
                    lda       <D.SysTsk
                    ldu       R$X,u
STime.Mv            ldy       #6
FMove               os9       F$Move
                    rts

*------------------------------------------------------------
*
* Handle F$STime system call
*
F.STime             ldx       <D.Proc
                    lda       P$Task,x
                    ldx       R$X,u
                    ldu       #D.Time
                    ldb       <D.SysTsk
                    bsr       STime.Mv
                    lda       #TkPerSec
                    sta       <D.Tick

                    ldx       <D.Clock2 call Clock2 SetTime
                    jsr       $06,x
                    rts

Clock2              fcs       "Clock2"

*------------------------------------------------------------
*
* Clock Initialization
*
* Called by the kernel to service the first F$STime call.
* Starts VIA T1 and installs the IRQ handler.
*
Init                ldx       <D.Proc   save user proc
                    pshs      x
                    ldx       <D.SysPrc make sys for link
                    stx       <D.Proc

                    leax      <Clock2,pcr
                    lda       #Sbrtn+Objct
                    os9       F$Link

                    puls      x
                    stx       <D.Proc   restore user proc

                    bcc       LinkOk
                    lda       #E$MNF
                    jmp       <D.Crash
LinkOk              sty       <D.Clock2 save Clock2 entry point

                    pshs      cc        save IRQ enable status
                    orcc      #IntMasks disable interrupts

* VIA T1: continuous, TkPerSec interrupts a second
                    ldx       #VIA0Base
                    lda       #%01111111 disable every VIA interrupt
                    sta       VIAIER,x
                    sta       VIAIFR,x  and clear any that are pending
                    lda       VIAACR,x
                    anda      #%00111111 T1 continuous, PB7 not driven
                    ora       #%01000000
                    sta       VIAACR,x
                    ldd       #T1Latch
                    stb       VIAT1CL,x low byte goes to the latch
                    sta       VIAT1CH,x high byte loads the counter and starts T1

                    ldd       #59*256+TkPerTS trigger RTC read soon
                    std       <D.Sec    will prompt Clock2 read at next timeslice

                    stb       <D.TSlice set ticks per time slice
                    stb       <D.Slice  set first time slice
                    leax      SvcIRQ,pcr install IRQ handler
                    stx       <D.IRQ
                    leax      SvcVIRQ,pcr install VIRQ handler
                    stx       <D.VIRQ
                    leay      NewSvc,pcr insert service calls
                    os9       F$SSvc

                    lda       #%10000000+T1Flag enable the T1 interrupt
                    sta       >VIA0Base+VIAIER

                    ldy       <D.Clock2 call Clock2 init
                    jsr       ,y
                    puls      cc,pc     restore IRQ status and return

                    emod
len                 equ       *

                    end
