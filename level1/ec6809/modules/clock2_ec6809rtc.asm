********************************************************************
* Clock2 - EC-6809 DS3231 RTC driver
*
* The DS3231 is on the I/O board I2C bus (PCF8584). It is reached
* through the public entries of the NitrOS-9 part of the I/O board EPROM
* (recipes/ec6809/io_eprom_nos9.asm), page $10:
*   P_I2C_INIT, P_I2C_START, P_I2C_WRITE, P_I2C_STOP
*   P_RTC_GET_BYTE (register A -> value B), P_BCDHEX
* The RTC must run in 24-hour mode. Years are 2000-2099.
* If the RTC does not answer, the time is left as it is.
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* ------------------------------------------------------------------
*   1      2026/11/15  Philippe Roehr
* Created from clock2_ec6809sd, without the Arduino.
*   2      2026/11/16  Philippe Roehr
* Init reads the RTC, so the time is right from boot.
*   3      2026/11/17  Philippe Roehr
* Uses the NitrOS-9 EPROM part on page $10.

                    nam       Clock2
                    ttl       EC-6809 DS3231 RTC driver

                    ifp1
                    use       defsfile
                    endc

tylg                set       Sbrtn+Objct
atrv                set       ReEnt+rev
rev                 set       $00
edition             set       3

RTC.Base            equ       $0000

                    mod       eom,name,tylg,atrv,JmpTable,RTC.Base

name                fcs       "Clock2"
                    fcb       edition

* Three Entry Points:
*   - Init
*   - GetTime
*   - SetTime
JmpTable
                    lbra      Init
                    bra       GetTime             RTC Get Time
                    nop

* SetTime. D.Year-D.Sec go to DS3231 registers 0-6, in BCD.
* Called by F$STime, in system state. IRQs stay masked so the minute
* GetTime cannot start an I2C transfer in the middle of this one.
SetTime             pshs      u,y,x,d,cc
                    orcc      #IntMasks
                    bsr       PageN
                    jsr       P_I2C_START
                    bne       SetStop
                    ldb       #RTC.Addr
                    jsr       P_I2C_WRITE
                    bne       SetStop
                    clrb                          start at register 0, seconds
                    jsr       P_I2C_WRITE
                    bne       SetStop
                    leau      WrTab,pcr
SetLoop             ldb       ,u+                 offset in D.Time, or $FF for day of week
                    bmi       SetDow
                    ldx       #D.Time
                    lda       b,x
                    cmpb      #0                  D.Year is years since 1900
                    bne       SetBCD
                    suba      #100
SetBCD              bsr       ToBCD
                    tfr       a,b
                    bra       SetPut
SetDow              ldb       #1                  day of week, not kept by OS-9
SetPut              jsr       P_I2C_WRITE
                    bne       SetStop
                    tst       ,u                  $80 ends the table
                    bpl       SetLoop
SetStop             jsr       P_I2C_STOP
                    puls      cc,d,x,y,u,pc

* DS3231 register order 0-6: offsets of sec, min, hour in D.Time, $FF for
* the day of week, then day, month, year.
WrTab               fcb       D.Sec-D.Time,D.Min-D.Time,D.Hour-D.Time,$FF
                    fcb       D.Day-D.Time,D.Month-D.Time,D.Year-D.Time,$80

* ToBCD. A = 0-99 binary. A returns the BCD value. B destroyed.
ToBCD               clrb
TB1                 cmpa      #10
                    blo       TB2
                    suba      #10
                    addb      #$10
                    bra       TB1
TB2                 pshs      b
                    adda      ,s+
                    rts

* PageN - map the EPROM public entries.
PageN               lda       #NOSPAGE
                    sta       >IOPAGE
                    rts

* GetTime. Called from the clock tick, once a minute, at IRQ level.
* It runs only when no EPROM call is active (IODEP = IODEP0). Then the
* interrupted code is outside the EPROM or in a page 1 slot, and the page
* found in PAGEID is put back. When the RTC cannot be read, the minute is
* counted in software: this Level 1 clock advances minutes only through
* GetTime.
GetTime             pshs      u,y,x,d
                    ldd       >IODEP
                    cmpd      #IODEP0
                    bne       GetSoft             an EPROM call is active
                    lda       >PAGEID             page now mapped
                    pshs      a
                    bsr       PageN
                    bsr       ReadRTC
                    puls      a                   Z is kept
                    sta       >IOPAGE             back to the page found
                    beq       GetEx               RTC read
GetSoft             bsr       SoftMin
GetEx               puls      d,x,y,u,pc

* ReadRTC. EPROM page 1 must be mapped. All six fields are read before
* any is stored, so D.Time changes only when the RTC answered. The copy
* runs with IRQs masked, so no tick sees half a time.
* Exit: Z = 1 when D.Time was set from the RTC. A, B, X, Y, U destroyed.
ReadRTC             leas      -6,s
                    leay      RdTab,pcr
                    leau      ,s
RdLoop              lda       ,y+                 DS3231 register
                    jsr       P_RTC_GET_BYTE      B = value, Z = 1 when it answered
                    bne       RdFail
                    andb      ,y+                 drop the control bits
                    tfr       b,a
                    jsr       P_BCDHEX            A = binary
                    sta       ,u+
                    tst       ,y                  $FF ends the table
                    bpl       RdLoop
                    lda       ,s
                    adda      #100                D.Year is years since 1900
                    sta       ,s
                    leau      ,s                  the six fields
                    ldx       #D.Time
                    ldb       #6
                    pshs      cc
                    orcc      #IntMasks
RdCopy              lda       ,u+
                    sta       ,x+
                    decb
                    bne       RdCopy
                    puls      cc
                    leas      6,s
                    orcc      #Zero               RTC read
                    rts
RdFail              leas      6,s                 LEAS keeps Z = 0
                    rts

* Register and mask, in D.Time order: year, month, day, hour, min, sec.
RdTab               fcb       6,$FF,5,$1F,4,$3F,2,$3F,1,$7F,0,$7F,$FF

* Init. Called by the clock init inside the first F$STime, made by SysGo
* before the shell starts, after the default time was stored. No other
* EPROM call can be active then. Set up the PCF8584 and read the RTC so
* the time is right at once. The clock init has already set D.Sec = 59
* and D.Tick = 1 to force a GetTime on the next tick. When the RTC is
* read, D.Tick is set to a full second instead; when it is not, the
* default time and the forced GetTime are kept.
Init                pshs      u,y,x,d,cc
                    bsr       PageN               EPROM page $10
                    jsr       P_I2C_INIT
                    bsr       ReadRTC
                    bne       InitEx              no RTC, keep the default time
                    lda       >D.TSec             a full second before the next count
                    sta       >D.Tick
InitEx              puls      cc,d,x,y,u,pc

* SoftMin. Advance D.Time by one minute, seconds = 0.
* Same code as clock2_soft. DP is 0 at IRQ level.
SoftMin             lda       <D.Min              grab current minute
                    inca                          minute+1
                    cmpa      #60                 End of hour?
                    blo       UpdMin              no, Set start of minute
                    ldd       <D.Day              get day, hour
                    incb                          hour+1
                    cmpb      #24                 End of Day?
                    blo       UpdHour             ..no
                    inca                          day+1
                    leax      <months-1,pcr       point to months table with offset-1: Jan = +1
                    ldb       <D.Month            this month
                    cmpa      b,x                 end of month?
                    bls       UpdDay              ..no, update the day
                    cmpb      #2                  yes, is it Feb?
                    bne       NoLeap              ..no, ok
                    ldb       <D.Year             else get year
                    andb      #$03                check for leap year: good until 2099
                    cmpd      #$1D00              29th on leap year?
                    beq       UpdDay              ..yes, skip it
NoLeap              ldd       <D.Year             else month+1
                    incb                          month+1
                    cmpb      #13                 end of year?
                    blo       UpdMonth            ..no
                    inca                          year+1
                    ldb       #$01                set month to jan
UpdMonth            std       <D.Year             save year, month
                    lda       #$01                day=1st
UpdDay              clrb                          hour=midnite
UpdHour             std       <D.Day              save day,hour
                    clra                          minute=00
UpdMin              clrb                          seconds=00
                    std       <D.Min              save min,secs
                    rts
months              fcb       31,28,31,30,31,30,31,31,30,31,30,31 Days in each month

                    emod
eom                 equ       *
                    end
