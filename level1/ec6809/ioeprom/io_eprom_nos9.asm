;*
;* I/O EPROM, NITROS-9 PART. PAGES $10-$3F OF AN AT28C256.
;*
;* PAGES $00-$0F OF THE CHIP ARE THE FLEX PART: IO_EPROM_V6.bin, 8 KB, AS
;* IT IS, WITH PAGES $0A-$0F SPARE FOR FLEX. THIS FILE BUILDS ONLY THE
;* CHIP BYTES $2000-$7FFF (24 KB). MAKE IN recipes/ec6809 BUILDS IT WITH LWASM:
;*   lwasm --6809 --format=raw -oio_eprom_nos9.bin -lio_eprom_nos9.lst io_eprom_nos9.asm
;* THE CHIP IMAGE IS THE TWO FILES JOINED, BY HAND:
;*   cat IO_EPROM_V6.bin io_eprom_nos9.bin > <CHIP IMAGE>
;*
;* EACH PAGE IS ITS OWN ORG $E800. LWASM'S PHASE GETS RELATIVE BRANCHES
;* WRONG, SO IT IS NOT USED. IN A RAW FILE THE PAGES FOLLOW EACH OTHER,
;* SO THE ORDER OF THE PAGES IN THIS FILE IS THEIR ORDER IN THE CHIP.
;* THE FIRST BYTE OF A PAGE IS ITS NUMBER, WRITTEN OUT ON EACH PAGE.
;*
;* NOTHING HERE CALLS A FLEX PAGE, AND NOTHING IS KEPT IN MAIN RAM. EVERY
;* VARIABLE AND THE FARCALL FRAMES ARE IN I/O RAM PAGE 0 ($EA00-$EBFF).
;* THE SPI, SD AND I2C CODE IS COPIED FROM IO_EPROM_V6 PAGES 2 AND 4-7,
;* WITH THE PAGE NUMBERS CHANGED. THE FLEX SECTOR ENTRIES, THE SPOOLER
;* CALL, SDWRITE, SDBOOT AND THE FLEX DISK PAGE ARE NOT HERE.
;* ONE CHANGE IN THE COPIED CODE: MKCMD ALSO REJECTS AN SDSC BYTE ADDRESS
;* THAT CARRIES OUT OF BIT 31, NOW THAT AN LSN HAS 24 BITS.
;*
;* THE NITROS-9 BOOT ROM SELECTS EPROM PAGE $10 AT $EEB0 AND I/O RAM
;* PAGE 0 AT $EEC0, STORES $EC00 AT $EA00, THEN CALLS P_NINIT.
;* THE SAME ENTRIES SERVE LEVEL 1 AND LEVEL 2. UNDER LEVEL 2 THEY ARE
;* CALLED IN THE SYSTEM TASK, WHOSE MAP HAS THE I/O BLOCK AT $E000, AND A
;* BUFFER ADDRESS IS A SYSTEM ADDRESS. A BUFFER MUST NOT BE IN $E000-$FFFF.
;*
;* THE FIRST BYTE OF EVERY PAGE IS THE PAGE NUMBER, READ AT $E800.
;* FARCALL IS $E801 ON EVERY PAGE, THROUGH THE RTS AT $E84A. THE
;* INSTRUCTION AFTER EACH LATCH WRITE IS FETCHED FROM THE NEW PAGE, SO
;* THOSE BYTES ARE THE SAME ON EVERY PAGE, AND THE SAME AS IN THE FLEX PART.
;*   JSR FARCALL / FCB PAGE / FDB ADDRESS
;* THE CALLEE SEES THE CALLER'S REGISTERS AND RETURNS WITH RTS. U IS NOT
;* USED BY FARCALL. AFTER THAT RTS THE CALLER PAGE IS MAPPED AGAIN.
;* FARCALL'S FRAME IS IN THE I/O RAM, BELOW THE WORD AT $EA00. $EA00 MUST
;* HOLD $EC00 BEFORE THE FIRST CALL. FARCALL DOES NOT TEST IT.
;* ONLY ONE CALL MAY RUN AT A TIME. INTERRUPT CODE MAY CALL AN ENTRY ONLY
;* WHILE $EA00 HOLDS $EC00, AND MUST PUT BACK THE PAGE IT READ AT $E800.
;*
;* PAGE $10 HOLDS ONLY THE PUBLIC ENTRIES, 8 BYTES EACH. OUTSIDE THIS
;* EPROM, SELECT PAGE $10 AND JSR THE SLOT. THE SLOT RETURNS WITH PAGE $10
;* STILL MAPPED. ERRORS ARE NITROS-9 CODES IN B WITH C = 1.
;*
;* $E850 P_NINIT          PAGE $12  SET EVERY VARIABLE, SPI IDLE, PROBE CS0 AND CS1
;* $E858 P_SDINIA                   PROBE THE CARDS NOT YET TESTED
;* $E860 P_SDINIT                   A = CARD. FORCED INIT OF THAT CARD
;* $E868 P_SDSTAT                   A = CARD. B = ITS FLAG
;* $E870 P_RDSEC          PAGE $13  READ ONE 256-BYTE SECTOR
;* $E878 P_WRSEC                    WRITE ONE 256-BYTE SECTOR
;* $E880 P_I2C_INIT       PAGE $11  I2C_INIT
;* $E888 P_I2C_START                I2C_START
;* $E890 P_I2C_RESTART              I2C_RESTART
;* $E898 P_I2C_STOP                 I2C_STOP
;* $E8A0 P_I2C_WRITE                I2C_WRITE
;* $E8A8 P_I2C_READ_ACK             I2C_READ_ACK
;* $E8B0 P_I2C_READ_NACK            I2C_READ_NACK
;* $E8B8 P_RTC_OK                   RTC_OK
;* $E8C0 P_RTC_GET_BYTE             RTC_GET_BYTE
;* $E8C8 P_BCDHEX                   BCDHEX
;* NEXT FREE PUBLIC SLOT IS $E8D0. DO NOT INSERT IN FRONT OF A SLOT.
;*
;* CARD FLAGS: $00 USABLE, $01 NO CARD OR IT FAILED, $02 NOT TESTED.
;* SECTOR N OF A CARD IS THE FIRST HALF OF ITS 512-BYTE BLOCK N.
;*
;* PAGE $10  PUBLIC ENTRIES.
;* PAGE $11  PCF8584, THEN DS3231 RTC_OK / RTC_GET_BYTE / BCDHEX.
;* PAGE $12  NINIT, NSDONE, SDSTAT, MKCMD, SDCCSX, SDINIT, SDONE.
;* PAGE $13  DATA LOOPS, RDSEC, WRSEC, SDCMD. LOCAL P5CLK AND P5WT.
;* PAGE $14  SDTRY, SDOCR AND THE COMMAND TABLES. LOCAL SDCCS6.
;* PAGE $15  SPI MASTER AND THE SECTOR FRAMING. NO LATCH WRITE PER BYTE.
;* PAGES $16-$3F ARE FREE, FILLED WITH $00.
;*
;* 11/2026 PH. ROEHR

PAGEID          EQU     $E800
PAGEREG         EQU     $EEB0
FARCALL         EQU     $E801

PG_PUB          EQU     $10
PG_I2C          EQU     $11
PG_INIT         EQU     $12
PG_DATA         EQU     $13
PG_TRY          EQU     $14
PG_SPI          EQU     $15

;* I/O RAM PAGE 0, $EA00-$EBFF. NOT UNMAPPED BY THE EPROM PAGE LATCH.
;* IODEP IS THE NEXT FARCALL FRAME. THE CALLER STORES $EC00 BEFORE THE
;* FIRST CALL. DESTMP HOLDS THE DESTINATION, THEN THE CALLER S ON THE WAY
;* HOME. THE FRAMES, 6 BYTES EACH, GROW DOWN FROM $EBFF. FOUR DEEP AT MOST.

IODEP           EQU     $EA00
DESTMP          EQU     $EA02

;* VARIABLES, $EA10-$EA24. SAME OFFSETS AS THE FLEX PART'S $DE6B BLOCK.

SDRAM           EQU     $EA10
SDCS            EQU     SDRAM+0         ; CARD OF THE CURRENT COMMAND, 0 OR 1
SDOK0           EQU     SDRAM+2         ; $00 USABLE, $01 NO CARD, $02 NOT TESTED
SDOK1           EQU     SDRAM+3         ; SAME VALUES AS SDOK0. MUST FOLLOW SDOK0
SDLBA0          EQU     SDRAM+4
SDLBA1          EQU     SDRAM+5
SDLBA2          EQU     SDRAM+6
SDLBA3          EQU     SDRAM+7
SPI_IMG         EQU     SDRAM+8         ; LAST BYTE WRITTEN TO SPI CTRL
CMDBUF          EQU     SDRAM+9
SDCCS0          EQU     SDRAM+15
SDCCS1          EQU     SDRAM+16
SDWSHT          EQU     SDRAM+17        ; NONZERO: SDWAIT STOPS AFTER 16 BYTES
SDSHF           EQU     SDRAM+19
I2C_FLAG        EQU     SDRAM+20

;* NITROS-9 ERROR CODES

ERUNIT          EQU     $F0             ; E$UNIT, CARD NUMBER NOT 0 OR 1
ERREAD          EQU     $F4             ; E$READ
ERWRIT          EQU     $F5             ; E$WRITE
ERSNR           EQU     $F6             ; E$NOTRDY, NO USABLE CARD

;* SPI MASTER AT $EE90. CTRL CANNOT BE READ BACK, SO SPI_IMG KEEPS IT.
;* SPEED, E = 1.8432 MHZ: 00 = 921.6 KHZ, 01 = 460.8, 10 = 230.4, 11 = 115.2.
;* THE NAMES BELOW ARE THE NOMINAL 1 MHZ TO 125 KHZ.

SPI_BASE        EQU     $EE90
SPI_DAT         EQU     SPI_BASE        ; W STARTS EIGHT CLOCKS, R IS MISO
SPI_STA         EQU     SPI_BASE+1      ; R  D7 = BUSY
SPI_CTL         EQU     SPI_BASE+1      ; W  CONTROL
CTL_CS          EQU     %00000011       ; D1-D0 CHIP NUMBER
CTL_ON          EQU     %00000100       ; D2  1 = THAT CS LOW
CTL_SPD         EQU     %00011000       ; D4-D3 SPEED
CTL_IE          EQU     %00100000       ; D5  INTN ENABLE
SP_1M           EQU     0
SP_500K         EQU     1
SP_250K         EQU     2
SP_125K         EQU     3
IMG_IDLE        EQU     SP_125K*8      ; CS OFF, 125 KHZ, INTN OFF
SPI_TMO         EQU     $0800           ; CONTROL-WRITE GIVE-UP, $0800 POLLS
SP_SPIN         EQU     64              ; BYTE-CLOCK GIVE-UP. 125 KHZ NEEDS ~10

;* PCF8584 AT $EE80. CONSTANTS FROM DRIVERS/pcf8584.ASM.

PCF_BASE        EQU     $EE80
PCF_S0          EQU     PCF_BASE
PCF_S1          EQU     PCF_BASE+1
S1_SEL_S0P      EQU     $80
S1_SEL_S2       EQU     $A0
S1_IDLE         EQU     $C1
S1_START        EQU     $C5
S1_REPSTART     EQU     $45
S1_STOP         EQU     $C3
S1_NACK         EQU     $40
S2_8MHZ_90K     EQU     $18
S0P_OWN         EQU     $55
ST_PIN          EQU     %10000000
ST_BER          EQU     %00010000
ST_LRB          EQU     %00001000
ST_BB           EQU     %00000001
ST_START        EQU     $08
ST_RESTART      EQU     $10
ST_SLAW_ACK     EQU     $18
ST_DATA_ACK     EQU     $28
ST_SLAR_ACK     EQU     $40
ST_RX_ACK       EQU     $50
ST_RX_NACK      EQU     $58
F_C5            EQU     %00000001
F_REP           EQU     %00000010
F_DUMMY         EQU     %00000100
SI_TMO          EQU     $8000


;*--------------------------------------------------------------------
;* PAGE $10. PUBLIC ENTRIES ONLY. EACH SLOT IS 8 BYTES.

;* FARCALL. SAME BYTES AS ON EVERY OTHER PAGE.

                ORG     $E800
                FCB     $10            ; THIS PAGE'S NUMBER, READ BACK AS PAGEID
                PSHS    CC,A,B,X,Y      ; RETURN PC IS AT 7,S. U IS NOT USED
                LDX     7,S             ; FCB PAGE, THEN FDB ADDRESS
                LDA     ,X+             ; DESTINATION PAGE, KEPT IN A
                LDY     ,X++            ; DESTINATION ADDRESS
                STX     7,S             ; RETURN SKIPS THE FCB AND THE FDB
                STY     DESTMP          ; Y STILL HOLDS IT
                TFR     S,X             ; X = S AT THE SAVED REGISTERS
                ORCC    #$50            ; MASK IRQ BEFORE S LEAVES THE CALLER
                LDS     IODEP           ; $EC00, OR THE FRAME BELOW AN OUTER CALL
                LDB     PAGEID
                PSHS    X,Y,D           ; 1 PAGE, 2 CALLER S, 4 DESTINATION
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE NEW PAGE
                LDS     2,S             ; SAVED REGS. PULS LEAVES THE RETURN PC
                PULS    CC,A,B,X,Y
                JSR     [DESTMP]
                PSHS    CC,A            ; RESULT. S IS 2 BELOW THE RETURN PC
                ORCC    #$50
                STS     DESTMP
                LDS     IODEP
                LDA     1,S             ; CALLER PAGE
                LEAS    6,S             ; DROP THIS FRAME
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE CALLER PAGE
                LDS     DESTMP
                PULS    CC,A
                RTS

                FILL    $00,$E850-*     ; SPARE. KEEPS P_NINIT AT $E850

;* EACH ENTRY IS 8 BYTES. THE ADDRESS IS FIXED. FILL KEEPS THE NEXT SLOT.

;* P_NINIT. $E850. SET EVERY VARIABLE, SPI IDLE AT 125 KHZ, THEN SDINIT.
P_NINIT         JSR     FARCALL
                FCB     PG_INIT
                FDB     NINIT
                RTS
                FILL    $00,$E858-*
;* P_SDINIA. $E858. PROBE EACH CARD WHOSE FLAG IS NOT $00 OR $01.
P_SDINIA        JSR     FARCALL
                FCB     PG_INIT
                FDB     SDINIT
                RTS
                FILL    $00,$E860-*
;* P_SDINIT. $E860. A = CARD. FORCED INIT OF THAT CARD.
P_SDINIT        JSR     FARCALL
                FCB     PG_INIT
                FDB     NSDONE
                RTS
                FILL    $00,$E868-*
;* P_SDSTAT. $E868. A = CARD. B = ITS FLAG.
P_SDSTAT        JSR     FARCALL
                FCB     PG_INIT
                FDB     SDSTAT
                RTS
                FILL    $00,$E870-*
;* P_RDSEC. $E870. READ ONE 256-BYTE SECTOR.
P_RDSEC         JSR     FARCALL
                FCB     PG_DATA
                FDB     RDSEC
                RTS
                FILL    $00,$E878-*
;* P_WRSEC. $E878. WRITE ONE 256-BYTE SECTOR.
P_WRSEC         JSR     FARCALL
                FCB     PG_DATA
                FDB     WRSEC
                RTS
                FILL    $00,$E880-*
;* P_I2C_INIT. $E880. PCF8584 FIG.5 INIT.
P_I2C_INIT      JSR     FARCALL
                FCB     PG_I2C
                FDB     I2C_INIT
                RTS
                FILL    $00,$E888-*
;* P_I2C_START. $E888. BUS FREE CHECK. START IS SENT BY THE NEXT WRITE.
P_I2C_START     JSR     FARCALL
                FCB     PG_I2C
                FDB     I2C_START
                RTS
                FILL    $00,$E890-*
;* P_I2C_RESTART. $E890. REPEATED START, 45H.
P_I2C_RESTART   JSR     FARCALL
                FCB     PG_I2C
                FDB     I2C_RESTART
                RTS
                FILL    $00,$E898-*
;* P_I2C_STOP. $E898. STOP, C3H.
P_I2C_STOP      JSR     FARCALL
                FCB     PG_I2C
                FDB     I2C_STOP
                RTS
                FILL    $00,$E8A0-*
;* P_I2C_WRITE. $E8A0. SEND B. Z = 1 ON ACK.
P_I2C_WRITE     JSR     FARCALL
                FCB     PG_I2C
                FDB     I2C_WRITE
                RTS
                FILL    $00,$E8A8-*
;* P_I2C_READ_ACK. $E8A8. RECEIVE ONE BYTE WITH ACK. DATA IN B.
P_I2C_READ_ACK  JSR     FARCALL
                FCB     PG_I2C
                FDB     I2C_READ_ACK
                RTS
                FILL    $00,$E8B0-*
;* P_I2C_READ_NACK. $E8B0. LAST BYTE, NACK. DATA IN B.
P_I2C_READ_NACK JSR     FARCALL
                FCB     PG_I2C
                FDB     I2C_READ_NACK
                RTS
                FILL    $00,$E8B8-*
;* P_RTC_OK. $E8B8. PROBE DS3231. Z = 1 IF IT ACKS.
P_RTC_OK        JSR     FARCALL
                FCB     PG_I2C
                FDB     RTC_OK
                RTS
                FILL    $00,$E8C0-*
;* P_RTC_GET_BYTE. $E8C0. REGISTER IN A, VALUE IN B. Z = 1 IF OK.
P_RTC_GET_BYTE  JSR     FARCALL
                FCB     PG_I2C
                FDB     RTC_GET_BYTE
                RTS
                FILL    $00,$E8C8-*
;* P_BCDHEX. $E8C8. BCD IN A, BINARY IN A. B IS KEPT.
P_BCDHEX        JSR     FARCALL
                FCB     PG_I2C
                FDB     BCDHEX
                RTS
                FILL    $00,$E8D0-*

P10END          EQU     *
                FILL    $00,$EA00-*

;*--------------------------------------------------------------------
;* PAGE $11. PCF8584, THEN THE DS3231. I2C_FLAG IS IN I/O RAM.

;* FARCALL. SAME BYTES AS ON EVERY OTHER PAGE.

                ORG     $E800
                FCB     $11            ; THIS PAGE'S NUMBER, READ BACK AS PAGEID
                PSHS    CC,A,B,X,Y      ; RETURN PC IS AT 7,S. U IS NOT USED
                LDX     7,S             ; FCB PAGE, THEN FDB ADDRESS
                LDA     ,X+             ; DESTINATION PAGE, KEPT IN A
                LDY     ,X++            ; DESTINATION ADDRESS
                STX     7,S             ; RETURN SKIPS THE FCB AND THE FDB
                STY     DESTMP          ; Y STILL HOLDS IT
                TFR     S,X             ; X = S AT THE SAVED REGISTERS
                ORCC    #$50            ; MASK IRQ BEFORE S LEAVES THE CALLER
                LDS     IODEP           ; $EC00, OR THE FRAME BELOW AN OUTER CALL
                LDB     PAGEID
                PSHS    X,Y,D           ; 1 PAGE, 2 CALLER S, 4 DESTINATION
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE NEW PAGE
                LDS     2,S             ; SAVED REGS. PULS LEAVES THE RETURN PC
                PULS    CC,A,B,X,Y
                JSR     [DESTMP]
                PSHS    CC,A            ; RESULT. S IS 2 BELOW THE RETURN PC
                ORCC    #$50
                STS     DESTMP
                LDS     IODEP
                LDA     1,S             ; CALLER PAGE
                LEAS    6,S             ; DROP THIS FRAME
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE CALLER PAGE
                LDS     DESTMP
                PULS    CC,A
                RTS

;* I2C_INIT. FIG.5: OWN ADDRESS, CLOCK, THEN BUS IDLE.
;* DESTROYS A. I2C_FLAG IS IN I/O RAM.
I2C_INIT        CLR     I2C_FLAG        ; NO DEFERRED START
                LDA     #S1_SEL_S0P     ; SELECT S0'
                STA     PCF_S1
                LDA     #S0P_OWN        ; OWN ADDRESS, MUST BE WRITTEN
                STA     PCF_S0
                LDA     #S1_SEL_S2      ; SELECT S2
                STA     PCF_S1
                LDA     #S2_8MHZ_90K    ; 8 MHZ CLOCK, SCL ABOUT 90 KHZ
                STA     PCF_S0
                LDA     #S1_IDLE        ; ESO=1, ACK=1, BUS IDLE
                STA     PCF_S1
                RTS

;* I2C_WAIT_SI. WAIT UNTIL PIN=0. Z=1 OK, Z=0 AND A=$FF ON TIMEOUT.
;* DESTROYS A, X.
I2C_WAIT_SI     LDX     #SI_TMO
WSI_LP          LDA     PCF_S1
                BPL     WSI_OK          ; PIN=0, BYTE COMPLETE
                LEAX    -1,X
                BNE     WSI_LP
                LDA     #$FF            ; TIMEOUT, Z=0
                RTS
WSI_OK          CLRA                    ; Z=1
                RTS

;* I2C_WAIT_PIN. WAIT, THEN REJECT A BUS ERROR.
;* Z=1 OK. Z=0 AND A=$FF ON TIMEOUT OR BER.
I2C_WAIT_PIN    BSR     I2C_WAIT_SI
                BNE     I2C_FAIL
                LDA     PCF_S1
                BITA    #ST_BER
                BNE     I2C_FAIL
                CLRA
                RTS
I2C_FAIL        LDA     #$FF            ; Z=0
                RTS

;* I2C_WAIT_ACK. WAIT, THEN REQUIRE ACK (LRB=0).
I2C_WAIT_ACK    BSR     I2C_WAIT_PIN
                BNE     I2C_FAIL
                LDA     PCF_S1
                BITA    #ST_LRB
                BNE     I2C_FAIL        ; NACK
                CLRA
                RTS

;* I2C_START. BUS MUST BE FREE (BB=1). THE START PULSE WAITS FOR I2C_WRITE.
;* A=$08 AND Z=1 WHEN THE BUS IS FREE.
I2C_START       LDX     #SI_TMO
BB_WAIT         LDA     PCF_S1
                BITA    #ST_BB
                BNE     ST_FREE         ; BB=1, BUS FREE
                LEAX    -1,X
                BNE     BB_WAIT
                BRA     I2C_FAIL
ST_FREE         LDA     I2C_FLAG
                ORA     #F_C5           ; NEXT WRITE: S0 THEN C5H
                STA     I2C_FLAG
                LDA     #ST_START       ; RETURN $08, Z=1
                CMPA    #ST_START
                RTS

;* I2C_RESTART. 45H, REPEATED START ONLY. A=$10, Z=1.
I2C_RESTART     LDA     #S1_REPSTART
                STA     PCF_S1
                LDA     I2C_FLAG
                ANDA    #~(F_C5)
                ORA     #F_REP          ; NEXT WRITE SENDS S0 ONLY
                STA     I2C_FLAG
                LDA     #ST_RESTART
                CMPA    #ST_RESTART
                RTS

;* I2C_STOP. C3H. HARDWARE DROPS TO SLAVE RECEIVER. PIN IS NOT SET.
I2C_STOP        LDA     #S1_STOP
                STA     PCF_S1
                CLR     I2C_FLAG
                RTS

;* I2C_WRITE. B IS SLA+W, A DATA BYTE, OR SLA+R.
;* Z=1 FOR $18, $28 OR $40. A IS THAT STATUS.
I2C_WRITE       LDA     I2C_FLAG
                BITA    #F_C5
                BNE     WR_C5           ; FIRST WRITE AFTER START
                BITA    #F_REP
                BNE     WR_REP          ; FIRST WRITE AFTER RESTART
                STB     PCF_S0          ; PLAIN DATA BYTE
                BSR     I2C_WAIT_ACK
                BNE     I2C_FAIL
                LDA     #ST_DATA_ACK    ; $28, Z=1
                CMPA    #ST_DATA_ACK
                RTS
WR_C5           STB     PCF_S0          ; ADDRESS BYTE
                LDA     #S1_START       ; C5H CLOCKS IT OUT AND SENDS START
                STA     PCF_S1
                BRA     WR_ADDR
WR_REP          STB     PCF_S0          ; ADDRESS AFTER 45H, NO SECOND C5H
WR_ADDR         LDA     I2C_FLAG
                ANDA    #~(F_C5|F_REP)
                BITB    #1              ; R/W BIT OF THE ADDRESS
                BEQ     WR_W
                ORA     #F_DUMMY        ; NEXT READ DISCARDS THE ADDRESS
WR_W            STA     I2C_FLAG
                BSR     I2C_WAIT_ACK
                BNE     I2C_FAIL
                BITB    #1
                BNE     WR_RD
                LDA     #ST_SLAW_ACK    ; $18
                CMPA    #ST_SLAW_ACK
                RTS
WR_RD           LDA     #ST_SLAR_ACK    ; $40
                CMPA    #ST_SLAR_ACK
                RTS

;* I2C_READ_ACK. ONE DATA BYTE WITH ACK. A=$50, B=DATA, Z=1.
;* THE FIRST CALL AFTER SLA+R DOES THE DUMMY S0 READ.
I2C_READ_ACK    LDA     I2C_FLAG
                BITA    #F_DUMMY
                BEQ     RA_WAIT
                LDA     PCF_S0          ; DUMMY: START THE FIRST DATA BYTE
                LDA     I2C_FLAG
                ANDA    #~(F_DUMMY)
                STA     I2C_FLAG
RA_WAIT         JSR     I2C_WAIT_PIN
                BEQ     RA_OK
                LDA     #$FF
                RTS
RA_OK           LDB     PCF_S0          ; DATA
                LDA     #ST_RX_ACK      ; $50, Z=1
                CMPA    #ST_RX_ACK
                RTS

;* I2C_READ_NACK. LAST BYTE. 40H CLEARS ACK. A=$58, B=DATA, Z=1.
I2C_READ_NACK   LDA     I2C_FLAG
                BITA    #F_DUMMY
                BEQ     RN_NAK
                LDA     PCF_S0          ; DUMMY WHEN THIS IS THE ONLY BYTE
                LDA     I2C_FLAG
                ANDA    #~(F_DUMMY)
                STA     I2C_FLAG
RN_NAK          LDA     #S1_NACK        ; ACK=0 BEFORE THE LAST BYTE
                STA     PCF_S1
                JSR     I2C_WAIT_PIN
                BEQ     RN_OK
                LDA     #$FF
                RTS
RN_OK           LDB     PCF_S0
                LDA     #ST_RX_NACK     ; $58, Z=1
                CMPA    #ST_RX_NACK
                RTS

;* DS3231 READ. SAME PAGE AS THE PCF8584,
;* SO THESE CALL I2C_START / I2C_WRITE / I2C_STOP DIRECTLY.
;* Z=1 MEANS OK, SAME AS THE I2C ROUTINES. STOP CLEARS Z,
;* SO THE ACK RESULT IS SAVED ACROSS IT.

RTC_ID_WRITE    EQU     $D0
RTC_ID_READ     EQU     $D1

;* RTC_OK. Z=1 IF THE DS3231 ACKS SLA+W. DESTROYS A, B, X.
RTC_OK          JSR     I2C_START
                BNE     ROK_BAD
                LDB     #RTC_ID_WRITE
                JSR     I2C_WRITE
                PSHS    CC              ; KEEP THE ACK FLAG
                JSR     I2C_STOP
                PULS    CC,PC
ROK_BAD         JSR     I2C_STOP
                LDA     #1              ; Z=0
                RTS

;* RTC_GET_BYTE. REGISTER IN A. VALUE IN B. Z=1 IF OK.
;* DESTROYS A AND X. B IS THE DATA ONLY WHEN Z=1.
RTC_GET_BYTE    PSHS    A
                JSR     I2C_START
                BNE     RGB_FAIL
                LDB     #RTC_ID_WRITE
                JSR     I2C_WRITE
                BNE     RGB_FAIL
                PULS    B               ; REGISTER ADDRESS
                PSHS    B
                JSR     I2C_WRITE
                BNE     RGB_FAIL
                JSR     I2C_RESTART
                BNE     RGB_FAIL
                LDB     #RTC_ID_READ
                JSR     I2C_WRITE
                BNE     RGB_FAIL
                BSR     I2C_READ_NACK   ; SINGLE BYTE, DATA IN B
                BNE     RGB_FAIL
                JSR     I2C_STOP
                LEAS    1,S
                CLRA                    ; Z=1, B STILL HOLDS THE BYTE
                RTS
RGB_FAIL        JSR     I2C_STOP
                LEAS    1,S
                LDA     #1              ; Z=0
                RTS

;* BCDHEX. BCD IN A, BINARY IN A. B IS KEPT.
BCDHEX          PSHS    B
                TFR     A,B
                ANDB    #$0F
                PSHS    B
                ANDA    #$F0
                LSRA
                LSRA
                LSRA
                LSRA
                LDB     #10
                MUL
                ADDB    ,S+
                TFR     B,A
                PULS    B,PC

P11END          EQU     *
                FILL    $00,$EA00-*

;*--------------------------------------------------------------------
;* PAGE $12. NITROS-9 CARD ENTRIES, COMMAND BUILDER, SDINIT AND SDONE.

;* FARCALL. SAME BYTES AS ON EVERY OTHER PAGE.

                ORG     $E800
                FCB     $12            ; THIS PAGE'S NUMBER, READ BACK AS PAGEID
                PSHS    CC,A,B,X,Y      ; RETURN PC IS AT 7,S. U IS NOT USED
                LDX     7,S             ; FCB PAGE, THEN FDB ADDRESS
                LDA     ,X+             ; DESTINATION PAGE, KEPT IN A
                LDY     ,X++            ; DESTINATION ADDRESS
                STX     7,S             ; RETURN SKIPS THE FCB AND THE FDB
                STY     DESTMP          ; Y STILL HOLDS IT
                TFR     S,X             ; X = S AT THE SAVED REGISTERS
                ORCC    #$50            ; MASK IRQ BEFORE S LEAVES THE CALLER
                LDS     IODEP           ; $EC00, OR THE FRAME BELOW AN OUTER CALL
                LDB     PAGEID
                PSHS    X,Y,D           ; 1 PAGE, 2 CALLER S, 4 DESTINATION
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE NEW PAGE
                LDS     2,S             ; SAVED REGS. PULS LEAVES THE RETURN PC
                PULS    CC,A,B,X,Y
                JSR     [DESTMP]
                PSHS    CC,A            ; RESULT. S IS 2 BELOW THE RETURN PC
                ORCC    #$50
                STS     DESTMP
                LDS     IODEP
                LDA     1,S             ; CALLER PAGE
                LEAS    6,S             ; DROP THIS FRAME
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE CALLER PAGE
                LDS     DESTMP
                PULS    CC,A
                RTS

;* NINIT. P_NINIT. EVERY VARIABLE GETS ITS START VALUE, BOTH CARDS ARE
;* MARKED NOT TESTED, THE SPI MASTER GOES IDLE AT 125 KHZ WITH CS HIGH,
;* THEN SDINIT PROBES CS0 AND CS1. $EA00 MUST ALREADY HOLD $EC00.
;* C = 0 WHEN A CARD IS USABLE. C = 1, B = E$NOTRDY OTHERWISE.
NINIT           LDA     #$02            ; NOT TESTED
                STA     SDOK0
                STA     SDOK1
                CLRA
                STA     SDCS
                STA     SDCCS0
                STA     SDCCS1
                STA     SDWSHT
                STA     I2C_FLAG
                LDA     #IMG_IDLE
                STA     SPI_IMG
                JSR     FARCALL         ; PAGE $15. CS HIGH, CLOCKS, 125 KHZ
                FCB     PG_SPI
                FDB     SPI_INIT
                LBCC    SDINIT
                LDB     #ERSNR
                RTS                     ; C IS SET

;* NSDONE. P_SDINIT. A = CARD, 0 OR 1. THEN AS SDONE.
;* C = 1, B = E$UNIT FOR ANY OTHER CARD NUMBER.
NSDONE          CMPA    #1
                BHI     NUNIT
                STA     SDCS
                LBRA    SDONE
NUNIT           LDB     #ERUNIT
                ORCC    #$01
                RTS

;* SDSTAT. P_SDSTAT. A = CARD, 0 OR 1. B = ITS FLAG, C = 0.
;* C = 1, B = E$UNIT FOR ANY OTHER CARD NUMBER. A, X KEPT.
SDSTAT          CMPA    #1
                BHI     NUNIT
                PSHS    X
                LDX     #SDOK0
                LDB     A,X
                ANDCC   #$FE
                PULS    X,PC


;* MKCMD. A = COMMAND BYTE. LBA IS ALREADY IN SDLBA0-3.
;* C = 0 READY. C = 1 IF AN SDSC BYTE ADDRESS DOES NOT FIT IN 32 BITS.
MKCMD           STA     CMDBUF          ; COMMAND INDEX
                LDA     #$01            ; DUMMY CRC, EXCEPT CMD0 AND CMD8
                STA     CMDBUF+5
                BSR     SDCCSX          ; X -> SDCCS0 OR SDCCS1
                TST     ,X
                BNE     MKBLK           ; CCS=1, BLOCK ADDRESS
                TST     SDLBA3          ; SDSC ADDRESS IS THE LBA SHIFTED LEFT 9
                BNE     MKOVF
                LDA     SDLBA2
                STA     CMDBUF+1
                LDA     SDLBA1
                STA     CMDBUF+2
                LDA     SDLBA0
                STA     CMDBUF+3
                CLR     CMDBUF+4
                LSL     CMDBUF+4        ; THAT SHIFT MAKES IT LBA << 9
                ROL     CMDBUF+3
                ROL     CMDBUF+2
                ROL     CMDBUF+1
                BCS     MKOVF           ; BIT 23 OF THE LBA LEFT BIT 31
                BRA     MKOK
MKBLK           LDA     SDLBA3          ; BLOCK NUMBER, NO SHIFT
                STA     CMDBUF+1
                LDA     SDLBA2
                STA     CMDBUF+2
                LDA     SDLBA1
                STA     CMDBUF+3
                LDA     SDLBA0
                STA     CMDBUF+4
MKOK            ANDCC   #$FE
                RTS
MKOVF           ORCC    #$01
                RTS

;* SDCCSX. X POINTS AT SDCCS0 OR SDCCS1 FOR THE CARD IN SDCS. A KEPT.
SDCCSX          LDB     SDCS
                ANDB    #1
                LDX     #SDCCS0
                ABX
                RTS


;* PHASE0. A IS THE FLAG. SDCS SELECTS THE SOCKET.
;* A = 0 NOTHING MORE. A = 1 NEEDS CMD8. A = 2 NEEDS CMD58.
;* A SILENT CARD IS STORED AS $01.
PHASE0          TSTA                    ; $00 ALREADY USABLE
                BEQ     PH0N
                CMPA    #$01            ; $01 ALREADY EMPTY
                BEQ     PH0N
                JSR     FARCALL         ; PAGE $14. CMD0 ONLY, 125 KHZ
                FCB     PG_TRY
                FDB     SDC0
                BCS     PH0E
                CMPA    #$01            ; IDLE
                BNE     PH0Z
                LDA     #1
                RTS
PH0Z            TSTA                    ; R1 = 0, ALREADY IN TRANSFER
                BNE     PH0E
                LDA     #2
                RTS
PH0E            LDA     #$01
                TST     SDCS
                BNE     PH0E1
                STA     SDOK0
                BRA     PH0N
PH0E1           STA     SDOK1
PH0N            CLRA
                RTS

;* PHASEA. CMD8 AND ACMD41 FOR THE CARD ALREADY IN IDLE. SDCS IS SET.
;* A = 2 WHEN CMD58 IS STILL REQUIRED. A = 0 WHEN THE FLAG IS NOW $01.
PHASEA          JSR     FARCALL         ; PAGE $14
                FCB     PG_TRY
                FDB     SDACMD
                BCS     PHAN
                LDA     #2
                RTS
PHAN            CLRA
                RTS

;* SDINIT. CMD0 FOR CS0, THEN CMD0 FOR CS1, BOTH AT 125 KHZ.
;* CMD8 AND ACMD41 START ONLY AFTER BOTH CMD0S HAVE RETURNED.
;* THEN ONE SWITCH TO 1 MHZ, AND CMD58 FOR EACH CARD THAT IS READY.
;* $00 AND $01 ARE LEFT ALONE. $02 AND ANY OTHER VALUE ARE PROBED.
;* C = 0 AND SDCS ON CS0 WHEN THAT FLAG IS $00, OTHERWISE ON CS1.
;* C = 1, B = $80 WHEN NEITHER FLAG IS $00.
;* A SECOND CALL WITH $00 WRITES 1 MHZ AND SENDS NO COMMAND.
;* BOTH $01 LEAVE THE CLOCK AT 125 KHZ.
SDINIT          CLRB
                STB     ,-S             ; CS0 PHASE. THIS BYTE BECOMES 1,S
                STB     ,-S             ; CS1 PHASE, AT 0,S
                CLR     SDCS
                LDA     SDOK0
                BSR     PHASE0
                STA     1,S
                LDA     #1
                STA     SDCS
                LDA     SDOK1
                BSR     PHASE0
                STA     ,S
                CLR     SDCS
                LDA     1,S
                CMPA    #1
                BNE     PH1
                BSR     PHASEA
                STA     1,S
PH1             LDA     #1
                STA     SDCS
                LDA     ,S
                CMPA    #1
                BNE     PHSPD
                BSR     PHASEA
                STA     ,S
PHSPD           LDA     SDOK0
                BEQ     PHGO
                LDA     SDOK1
                BEQ     PHGO
                LDA     ,S
                CMPA    #2
                BEQ     PHGO
                LDA     1,S
                CMPA    #2
                BNE     PHNONE
PHGO            CLRA                    ; 1 MHZ ONCE FOR BOTH SOCKETS
                JSR     FARCALL         ; PAGE $15
                FCB     PG_SPI
                FDB     SPI_SPD
                BCS     PHBAD
                LDA     1,S             ; CS0
                CMPA    #2
                BNE     PHC1
                CLR     SDCS
                JSR     FARCALL         ; PAGE $14. CMD58 AT 1 MHZ
                FCB     PG_TRY
                FDB     SDOCR
PHC1            LDA     ,S              ; CS1
                CMPA    #2
                BNE     PHDONE
                LDA     #1
                STA     SDCS
                JSR     FARCALL
                FCB     PG_TRY
                FDB     SDOCR
PHDONE          LEAS    2,S
                LDA     SDOK0
                BNE     PHPK1
                CLR     SDCS            ; PREFER CS0 WHEN IT IS USABLE
                CLRB
                ANDCC   #$FE
                RTS
PHPK1           LDA     SDOK1
                BNE     PHNO2
                LDA     #1
                STA     SDCS
                CLRB
                ANDCC   #$FE
                RTS
PHNONE          LEAS    2,S
PHNO2           LDB     #ERSNR
                ORCC    #$01
                RTS
PHBAD           LEAS    2,S
                LDB     #ERSNR
                ORCC    #$01
                RTS

;* SDONE. FORCED INIT OF THE ONE CARD IN SDCS. P_SDINIT LANDS HERE.
;* THE FLAG IS IGNORED AND THE PROBE RUNS AT 125 KHZ.
;* A CARD THAT ANSWERS IS SWITCHED TO 1 MHZ, THEN CMD58 STORES $00 OR $01.
;* C = 0 WHEN THE FLAG IS $00. C = 1, B = $80 OTHERWISE.
SDONE           JSR     FARCALL         ; PAGE $14
                FCB     PG_TRY
                FDB     SDTRY
                BCS     SONEX
                CLRA
                JSR     FARCALL         ; PAGE $15
                FCB     PG_SPI
                FDB     SPI_SPD
                BCS     SONBAD
                JSR     FARCALL         ; PAGE $14
                FCB     PG_TRY
                FDB     SDOCR
SONEX           RTS
SONBAD          LDA     #$01
                TST     SDCS
                BNE     SON1
                STA     SDOK0
                BRA     SON2
SON1            STA     SDOK1
SON2            LDB     #ERSNR
                ORCC    #$01
                RTS

P12END          EQU     *
                FILL    $00,$EA00-*

;*--------------------------------------------------------------------
;* PAGE $13. DATA LOOPS AND THE NITROS-9 SECTOR ENTRIES.
;* P5CLK IS THE LOCAL SPI EXCHANGE. IT DOES NOT WRITE THE PAGE LATCH.

;* FARCALL. SAME BYTES AS ON EVERY OTHER PAGE.

                ORG     $E800
                FCB     $13            ; THIS PAGE'S NUMBER, READ BACK AS PAGEID
                PSHS    CC,A,B,X,Y      ; RETURN PC IS AT 7,S. U IS NOT USED
                LDX     7,S             ; FCB PAGE, THEN FDB ADDRESS
                LDA     ,X+             ; DESTINATION PAGE, KEPT IN A
                LDY     ,X++            ; DESTINATION ADDRESS
                STX     7,S             ; RETURN SKIPS THE FCB AND THE FDB
                STY     DESTMP          ; Y STILL HOLDS IT
                TFR     S,X             ; X = S AT THE SAVED REGISTERS
                ORCC    #$50            ; MASK IRQ BEFORE S LEAVES THE CALLER
                LDS     IODEP           ; $EC00, OR THE FRAME BELOW AN OUTER CALL
                LDB     PAGEID
                PSHS    X,Y,D           ; 1 PAGE, 2 CALLER S, 4 DESTINATION
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE NEW PAGE
                LDS     2,S             ; SAVED REGS. PULS LEAVES THE RETURN PC
                PULS    CC,A,B,X,Y
                JSR     [DESTMP]
                PSHS    CC,A            ; RESULT. S IS 2 BELOW THE RETURN PC
                ORCC    #$50
                STS     DESTMP
                LDS     IODEP
                LDA     1,S             ; CALLER PAGE
                LEAS    6,S             ; DROP THIS FRAME
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE CALLER PAGE
                LDS     DESTMP
                PULS    CC,A
                RTS

;* SDWAIT. CLOCK UNTIL MISO IS NOT $FF. A = THAT BYTE, C = 0. B KEPT.
;* C = 1 AND A = $FF ON SPI FAILURE OR GIVE-UP.
;* SDWSHT NONZERO STOPS AFTER 16 BYTES. DATA READS LEAVE IT CLEAR.
SDWAIT          PSHS    B
                LDX     #$4000          ; GIVE-UP COUNT
                TST     SDWSHT
                BEQ     SW1
                LDX     #16             ; INIT CMD0 ANSWERS WITHIN A FEW BYTES
SW1             LDA     #$FF
                BSR     P5CLK           ; NO PAGE SWITCH PER BYTE
                BCS     SW2
                CMPA    #$FF
                BNE     SW3
                LEAX    -1,X
                BNE     SW1
                LDA     #$FF
                ORCC    #$01
SW2             PULS    B,PC
SW3             ANDCC   #$FE
                PULS    B,PC

;* P5CLK. CLOCK THE BYTE IN A. A RETURNS MISO. B, X, Y AND U KEPT.
;* THE SHIFTER MUST BE IDLE ON ENTRY, AND IS IDLE AGAIN ON SUCCESS.
;* C = 1 AND A = $FF IF IT STAYS BUSY FOR SP_SPIN POLLS.
;* USED BY SDWAIT AND SDCMD, WHERE THE CARD SETS THE PACE.
P5CLK           STA     SPI_DAT
                BSR     P5WT
                BCS     PCKF
                LDA     SPI_DAT         ; C IS CLEAR FROM P5WT
                RTS
PCKF            LDA     #$FF
                RTS

;* P5WT. WAIT UNTIL THE SHIFTER IS IDLE. ALL REGISTERS KEPT.
;* C = 0 IDLE. C = 1 STILL BUSY AFTER SP_SPIN POLLS.
P5WT            PSHS    A,B
                LDB     #SP_SPIN
PW1             LDA     SPI_STA
                BPL     PW2
                DECB
                BNE     PW1
                ORCC    #$01
                PULS    A,B,PC
PW2             ANDCC   #$FE
                PULS    A,B,PC

;* FAST LOOPS. SDFF, SDZRO, SDRDB AND SDSND.
;* U POINTS AT SPI_BASE. 0,U IS DATA, 1,U IS STAT.
;* ONE 74LS299 HOLDS THE BYTE SENT AND THEN THE BYTE RECEIVED. A READ
;* OF DATA ONLY ENABLES ITS OUTPUTS, SO A WRITE MAY FOLLOW AT ONCE.
;* A WRITE WHILE BUSY = 1 RESTARTS THE SEQUENCER. EVERY WRITE COMES
;* AFTER A STAT READ THAT SAW BUSY = 0.
;* AT 1 MHZ BUSY READS 0 FROM THE 16TH E CYCLE AFTER THE WRITE CYCLE.
;* EACH LOOP PUTS ITS POLL 18 OR 19 CYCLES AFTER THE WRITE, SO ONE POLL
;* FALLS THROUGH. A SLOWER CLOCK, OR AN IRQ, GOES TO P5WT.
;* THE SHIFTER MUST BE IDLE ON ENTRY. B, Y AND U ARE KEPT.
;* C = 0 DONE, A = LAST MISO. C = 1 AND A = $FF ON SPI FAILURE.

;* P5CNT. Y = B, OR 256 WHEN B = 0. A AND B KEPT.
P5CNT           PSHS    B
                CLR     ,-S             ; 0,S = 0, 1,S = B
                PULS    Y
                LEAY    ,Y              ; Z WHEN B = 0
                BNE     PCN1
                LDY     #256
PCN1            RTS

;* SDFF. B BYTES OF $FF. B = 0 MEANS 256. X KEPT.
SDFF            LDA     #$FF
                BRA     SDREP

;* SDZRO. B BYTES OF $00. B = 0 MEANS 256. X KEPT.
SDZRO           CLRA

;* SDREP. B BYTES OF A. A WRITE RELOADS THE 299 WHATEVER IT HOLDS,
;* SO THE REPLY IS NOT READ, EXCEPT THE LAST ONE. 25 CYCLES A BYTE.
SDREP           PSHS    B,Y,U
                BSR     P5CNT
                LDU     #SPI_BASE
REP1            STA     ,U              ; START THIS BYTE
                LEAY    -1,Y
                BEQ     REP3            ; THAT WAS THE LAST ONE
                BRN     *               ; 3 + 2 = 5 CYCLES OF DELAY.
                NOP                     ; THE POLL LANDS AT CYCLE 18
                LDB     1,U
                BPL     REP1
                BSR     P5WT            ; STILL SHIFTING
                BCC     REP1
                BRA     P5FL
REP3            BSR     P5WT
                BCS     P5FL
                LDA     ,U              ; LAST MISO
                BRA     P5OK

;* SDRDB. READ B BYTES INTO X, SENDING $FF. B = 0 MEANS 256. X ADVANCES.
;* EACH PASS READS A BYTE, STARTS THE NEXT, THEN STORES. 30 CYCLES A BYTE.
;* NO BYTE IS CLOCKED AFTER THE LAST ONE.
SDRDB           PSHS    B,Y,U
                BSR     P5CNT
                LDU     #SPI_BASE
                LDB     #$FF
                STB     ,U              ; FIRST BYTE
                LEAY    -1,Y            ; PASSES BEFORE THE LAST BYTE
                BEQ     RDB3
RDB1            LDA     1,U             ; POLL AT CYCLE 19
                BMI     RDB4
RDB2            LDA     ,U              ; THIS BYTE
                STB     ,U              ; START THE NEXT
                STA     ,X+
                LEAY    -1,Y
                BNE     RDB1
RDB3            BSR     P5WT            ; LAST BYTE
                BCS     P5FL
                LDA     ,U
                STA     ,X+
                BRA     P5OK
RDB4            BSR     P5WT            ; STILL SHIFTING
                BCC     RDB2
                BRA     P5FL

;* SDSND. SEND B BYTES FROM X. B = 0 MEANS 256. X ADVANCES.
;* THE BUFFER IS NOT CHANGED. THE NEXT BYTE IS FETCHED WHILE THE CURRENT
;* ONE SHIFTS. NOTHING PAST THE LAST BYTE IS READ. 26 CYCLES A BYTE.
SDSND           PSHS    B,Y,U
                BSR     P5CNT
                LDU     #SPI_BASE
                LDA     ,X+
                BRA     SN3
SN1             LDA     ,X+
                LDB     1,U             ; POLL AT CYCLE 19
                BMI     SN4
SN3             STA     ,U              ; START THIS BYTE
                LEAY    -1,Y
                BNE     SN1
                JSR     P5WT            ; LAST BYTE
                BCS     P5FL
                LDA     ,U
                BRA     P5OK
SN4             JSR     P5WT            ; STILL SHIFTING
                BCC     SN3

;* SHARED EXITS OF THE FAST LOOPS.
P5FL            LDA     #$FF
                ORCC    #$01
                PULS    B,Y,U,PC
P5OK            ANDCC   #$FE
                PULS    B,Y,U,PC

;* RDSEC. P_RDSEC. READ ONE 256-BYTE SECTOR, THE FIRST HALF OF ITS BLOCK.
;* A = CARD, 0 OR 1. B = LSN BITS 23-16, X = LSN BITS 15-0.
;* U = BUFFER. A, X, Y AND U ARE KEPT.
;* C = 0, B = 0 DONE. C = 1, B = E$UNIT, E$NOTRDY OR E$READ.
RDSEC           PSHS    A,X,Y,U
                BSR     SECSET          ; CARD AND LBA
                BCS     RDX
                JSR     FARCALL         ; PAGE $15. COMMAND AND TOKEN
                FCB     PG_SPI
                FDB     SDROPEN
                BCS     RDFAL
                LDX     5,S             ; BUFFER, THE CALLER'S U
                CLRB                    ; 256 BYTES
                JSR     SDRDB
                BCS     RDFAL
                CLRB                    ; DISCARD THE OTHER HALF
                JSR     SDFF
                BCS     RDFAL
                JSR     FARCALL         ; PAGE $15. TWO CRC BYTES, CS HIGH
                FCB     PG_SPI
                FDB     SDRCLOSE
                BCS     RDFAL
                CLRB
                ANDCC   #$FE
                PULS    A,X,Y,U,PC
RDFAL           JSR     FARCALL
                FCB     PG_SPI
                FDB     SPI_IDLE
                LDB     #ERREAD
                ORCC    #$01
RDX             PULS    A,X,Y,U,PC

;* WRSEC. P_WRSEC. WRITE ONE 256-BYTE SECTOR. THE SECOND HALF OF THE
;* BLOCK IS WRITTEN AS $00. SAME ENTRY AS RDSEC. THE BUFFER IS NOT CHANGED.
;* C = 0, B = 0 DONE. C = 1, B = E$UNIT, E$NOTRDY OR E$WRITE.
WRSEC           PSHS    A,X,Y,U
                BSR     SECSET
                BCS     WRX
                JSR     FARCALL         ; PAGE $15. COMMAND AND TOKEN
                FCB     PG_SPI
                FDB     SDWOPEN
                BCS     WRFAL
                LDX     5,S
                CLRB
                JSR     SDSND
                BCS     WRFAL
                CLRB
                JSR     SDZRO           ; PAD THE BLOCK TO 512 BYTES
                BCS     WRFAL
                JSR     FARCALL         ; PAGE $15. CRC, BUSY, CS HIGH
                FCB     PG_SPI
                FDB     SDWCLOSE
                BCS     WRFAL
                CLRB
                ANDCC   #$FE
                PULS    A,X,Y,U,PC
WRFAL           JSR     FARCALL
                FCB     PG_SPI
                FDB     SPI_IDLE
                LDB     #ERWRIT
                ORCC    #$01
WRX             PULS    A,X,Y,U,PC

;* SECSET. A = CARD, B = LSN BITS 23-16, X = LSN BITS 15-0.
;* THE CARD MUST BE 0 OR 1 AND ITS FLAG $00. THEN SDCS = CARD AND
;* SDLBA0-3 = THE LSN. A, B AND Y DESTROYED.
;* C = 1, B = E$UNIT OR E$NOTRDY, WHEN THE SECTOR CANNOT BE TRIED.
SECSET          CMPA    #1
                BHI     SSUNIT
                STA     SDCS
                STB     SDLBA2
                CLR     SDLBA3
                PSHS    X
                PULS    A,B             ; A = LSN BITS 15-8, B = BITS 7-0
                STA     SDLBA1
                STB     SDLBA0
                LDA     SDCS
                LDY     #SDOK0
                LDA     A,Y
                BNE     SSNRDY
                ANDCC   #$FE
                RTS
SSUNIT          LDB     #ERUNIT
                ORCC    #$01
                RTS
SSNRDY          LDB     #ERSNR
                ORCC    #$01
                RTS

;* SDCMD. SEND THE SIX BYTES AT X. ONE $FF WITH CS HIGH, THEN SDCS LOW.
;* THE SIX BYTES AND THE R1 WAIT STAY ON THIS PAGE. NO PAGE LATCH WRITE
;* WHILE THE CARD IS CLOCKED. A = R1, CS STILL LOW.
;* C = 1: A = $FF, CS HIGH.
SDCMD           JSR     FARCALL         ; CS HIGH BEFORE THE COMMAND
                FCB     PG_SPI
                FDB     SPI_IDLE
                BCS     SDCX
                LDA     #$FF
                JSR     P5CLK           ; ONE IDLE BYTE, CS STILL HIGH
                BCS     SDCX
                LDB     SDCS
                ANDB    #CTL_CS         ; CHIP NUMBER IN D1-D0
                JSR     FARCALL         ; THAT CS LOW
                FCB     PG_SPI
                FDB     SPI_SEL
                BCS     SDCX
                LDB     #6
SDC1                            LDA     ,X+
                JSR     P5CLK           ; CLOCK THIS BYTE WITHOUT A PAGE SWITCH
                BCS     SDCX
                DECB
                BNE     SDC1
                JSR     SDWAIT          ; A = R1, CS STILL LOW
                RTS
SDCX            JSR     FARCALL
                FCB     PG_SPI
                FDB     SPI_IDLE
                LDA     #$FF
                ORCC    #$01
                RTS

P13END          EQU     *
                FILL    $00,$EA00-*

;*--------------------------------------------------------------------
;* PAGE $14. CARD INIT. THE CC0-CC58 TABLES STAY ON THIS PAGE.

;* FARCALL. SAME BYTES AS ON EVERY OTHER PAGE.

                ORG     $E800
                FCB     $14            ; THIS PAGE'S NUMBER, READ BACK AS PAGEID
                PSHS    CC,A,B,X,Y      ; RETURN PC IS AT 7,S. U IS NOT USED
                LDX     7,S             ; FCB PAGE, THEN FDB ADDRESS
                LDA     ,X+             ; DESTINATION PAGE, KEPT IN A
                LDY     ,X++            ; DESTINATION ADDRESS
                STX     7,S             ; RETURN SKIPS THE FCB AND THE FDB
                STY     DESTMP          ; Y STILL HOLDS IT
                TFR     S,X             ; X = S AT THE SAVED REGISTERS
                ORCC    #$50            ; MASK IRQ BEFORE S LEAVES THE CALLER
                LDS     IODEP           ; $EC00, OR THE FRAME BELOW AN OUTER CALL
                LDB     PAGEID
                PSHS    X,Y,D           ; 1 PAGE, 2 CALLER S, 4 DESTINATION
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE NEW PAGE
                LDS     2,S             ; SAVED REGS. PULS LEAVES THE RETURN PC
                PULS    CC,A,B,X,Y
                JSR     [DESTMP]
                PSHS    CC,A            ; RESULT. S IS 2 BELOW THE RETURN PC
                ORCC    #$50
                STS     DESTMP
                LDS     IODEP
                LDA     1,S             ; CALLER PAGE
                LEAS    6,S             ; DROP THIS FRAME
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE CALLER PAGE
                LDS     DESTMP
                PULS    CC,A
                RTS

;* SDCCS6. COPY OF SDCCSX. SDTRY AND SDOCR BRANCH HERE.
;* THE ORIGINAL ON PAGE $12 IS OUT OF BSR RANGE.
SDCCS6          LDB     SDCS
                ANDB    #1
                LDX     #SDCCS0
                ABX
                RTS

;* SDC0. ONE CMD0 AT 125 KHZ FOR THE CARD IN SDCS. NO CMD8 AND NO CMD58.
;* C = 0 AND A = R1 WHEN THE CARD ANSWERED. C = 1 WHEN IT DID NOT.
;* CCS FOR THIS CARD IS CLEARED. THE FLAG BYTE IS NOT CHANGED.
SDC0            CLR     SDWSHT
                BSR     SDCCS6
                CLR     ,X              ; THIS CARD'S CCS IS UNKNOWN
                LDA     #IMG_IDLE       ; 125 KHZ AND CS HIGH, BEFORE ANY CLOCK
                BSR     FARCALL
                FCB     PG_SPI
                FDB     SPI_PUTC
                BCS     SDC0X
                LDB     #10             ; 80 CLOCKS, CS HIGH
                BSR     FARCALL
                FCB     PG_DATA
                FDB     SDFF
                BCS     SDC0X
                BSR     CMD0GO
                BCS     SDC0X
                BSR     FARCALL
                FCB     PG_SPI
                FDB     SPI_IDLE
                BCS     SDC0X
                RTS
SDC0X           ORCC    #$01
                RTS

;* SDTRY. CMD0, THEN CMD8 AND ACMD41 WHEN THE CARD IS IDLE.
;* C = 0 WHEN THE CARD IS READY FOR CMD58. THE FLAG BYTE IS LEFT UNCHANGED.
;* C = 1, B = $80, FLAG = $01 WHEN THE SOCKET DOES NOT ANSWER.
;* A, Y, U KEPT. X DESTROYED. THE COMMAND TABLES BELOW MUST STAY ON THIS PAGE.
SDTRY           PSHS    A,Y,U
                BSR     SDC0
                BCS     SIFAIL
                CMPA    #$01            ; IDLE
                BEQ     CMD8
                TSTA
                LBEQ    SREADY          ; R1=0, ALREADY IN TRANSFER STATE
                BRA     SIFAIL

;* CMD0GO. SEND CMD0. SHORT R1 WAIT. A = R1. C = 1 IF THE CARD IS SILENT.
CMD0GO          LDA     #1
                STA     SDWSHT
                LDX     #CC0
                JSR     COPY6
                JSR     FARCALL
                FCB     PG_DATA
                FDB     SDCMD
                CLR     SDWSHT          ; CARRY FROM SDCMD STAYS
                RTS

SIFAIL          JSR     FARCALL
                FCB     PG_SPI
                FDB     SPI_IDLE
                LBRA    SFAIL2

;* SDACMD. CMD8 AND ACMD41. THE CARD IS ALREADY IN IDLE, STILL AT 125 KHZ.
;* C = 0 READY FOR CMD58, FLAG UNCHANGED. C = 1, FLAG STORED AS $01.
SDACMD          PSHS    A,Y,U
CMD8            LDX     #CC8
                JSR     COPY6
                JSR     FARCALL
                FCB     PG_DATA
                FDB     SDCMD
                BCS     SIFAIL
                CMPA    #$01            ; CMD8 ACCEPTED: V2 CARD
                BNE     SIFAIL
                LDB     #4              ; R7 TAIL
                JSR     FARCALL
                FCB     PG_DATA
                FDB     SDFF
                BCS     SIFAIL
                JSR     FARCALL
                FCB     PG_SPI
                FDB     SPI_IDLE
                BCS     SIFAIL
                LDA     #100
                STA     SDSHF           ; ACMD41 RETRIES
ACLP            LDX     #CC55           ; APP_CMD
                JSR     COPY6
                JSR     FARCALL
                FCB     PG_DATA
                FDB     SDCMD
                BCS     SIFAIL
                JSR     FARCALL
                FCB     PG_SPI
                FDB     SPI_IDLE
                BCS     SIFAIL
                CMPA    #$01
                BNE     SIFAIL
                LDX     #CC41           ; ACMD41, HCS SET
                JSR     COPY6
                JSR     FARCALL
                FCB     PG_DATA
                FDB     SDCMD
                BCS     SIFAIL
                JSR     FARCALL
                FCB     PG_SPI
                FDB     SPI_IDLE
                BCS     SIFAIL
                TSTA
                BEQ     SREADY          ; LEFT IDLE
                CMPA    #$01
                BNE     SIFAIL
                DEC     SDSHF
                BEQ     SIFAIL
                JSR     DELAY
                BRA     ACLP
SREADY          CLRB
                ANDCC   #$FE
                PULS    A,Y,U,PC
SFAIL2          LDA     #$01            ; TESTED, NO CARD
                TST     SDCS
                BNE     SFL1
                STA     SDOK0
                BRA     SFL2
SFL1            STA     SDOK1
SFL2            LDB     #ERSNR
                ORCC    #$01
                PULS    A,Y,U,PC

;* SDOCR. CMD58 AT THE SPEED ALREADY SET. SDCS SELECTS THE CARD.
;* BIT 31 SET AND CCS STORED: FLAG = $00, C = 0.
;* ANY FAILURE: FLAG = $01, C = 1, B = $80. A, Y, U KEPT.
SDOCR           PSHS    A,Y,U
                LDX     #CC58           ; READ OCR
                JSR     COPY6
                JSR     FARCALL
                FCB     PG_DATA
                FDB     SDCMD
                LBCS    OCRF
                TSTA
                LBNE    OCRF
                LDA     #$FF            ; FIRST OCR BYTE, BIT 31
                JSR     FARCALL
                FCB     PG_SPI
                FDB     SPI_BYTE
                LBCS    OCRF
                PSHS    A
                LDB     #3              ; REST OF THE OCR
                JSR     FARCALL
                FCB     PG_DATA
                FDB     SDFF
                BCS     OCRBP
                JSR     FARCALL
                FCB     PG_SPI
                FDB     SPI_IDLE
                BCS     OCRBP
                PULS    A
                TSTA                    ; BIT 31, POWER UP DONE
                LBPL    OCRF
                ANDA    #$40            ; BIT 30, CCS
                BEQ     SETSC
                LDA     #1              ; BLOCK ADDRESS
                BRA     SETST
SETSC           CLRA                    ; SDSC, BYTE ADDRESS
SETST           JSR     SDCCS6
                STA     ,X              ; STORE CCS FOR THIS CARD
                CLRA                    ; $00 USABLE
                BRA     OCRPUT
OCRBP           PULS    A
OCRF            LDA     #$01
OCRPUT          TST     SDCS
                BNE     OCR1
                STA     SDOK0
                BRA     OCRX
OCR1            STA     SDOK1
OCRX            TSTA
                BNE     OCRBAD
                CLRB
                ANDCC   #$FE
                PULS    A,Y,U,PC
OCRBAD          LDB     #ERSNR
                ORCC    #$01
                PULS    A,Y,U,PC

;* DELAY. ABOUT ONE ACMD41 GAP. Y KEPT.
DELAY           PSHS    Y
                LDY     #0
DL1             LEAY    -1,Y
                BNE     DL1
                PULS    Y,PC

;* COPY6. COPY THE SIX BYTES AT X INTO CMDBUF. X RETURNS CMDBUF.
;* SDCMD IS ON PAGE $13. A TABLE IN THIS WINDOW WOULD BE READ AS ZEROS THERE.
COPY6           PSHS    B,Y
                LDY     #CMDBUF
                LDB     #6
CP61            LDA     ,X+
                STA     ,Y+
                DECB
                BNE     CP61
                LDX     #CMDBUF
                PULS    B,Y,PC

;* COMMANDS WHOSE ARGUMENT NEVER CHANGES. CRC IS REAL ON CMD0 AND CMD8.
;* COPY6 READS THEM ON THIS PAGE. THEY CANNOT MOVE TO ANOTHER PAGE.
CC0             FCB     $40,$00,$00,$00,$00,$95     ; CMD0
CC8             FCB     $48,$00,$00,$01,$AA,$87     ; CMD8
CC55            FCB     $77,$00,$00,$00,$00,$01     ; CMD55
CC41            FCB     $69,$40,$00,$00,$00,$01     ; ACMD41, HCS
CC58            FCB     $7A,$00,$00,$00,$00,$01     ; CMD58

P14END          EQU     *
                FILL    $00,$EA00-*

;*--------------------------------------------------------------------
;* PAGE $15. SPI MASTER AND THE SECTOR FRAMING.
;* OPEN, CLOSE, THE COMMAND BYTES AND THE TOKEN WAIT USE SPI_BYTE
;* ON THIS PAGE. THE 256-BYTE LOOPS STAY ON PAGE $13.

;* FARCALL. SAME BYTES AS ON EVERY OTHER PAGE.

                ORG     $E800
                FCB     $15            ; THIS PAGE'S NUMBER, READ BACK AS PAGEID
                PSHS    CC,A,B,X,Y      ; RETURN PC IS AT 7,S. U IS NOT USED
                LDX     7,S             ; FCB PAGE, THEN FDB ADDRESS
                LDA     ,X+             ; DESTINATION PAGE, KEPT IN A
                LDY     ,X++            ; DESTINATION ADDRESS
                STX     7,S             ; RETURN SKIPS THE FCB AND THE FDB
                STY     DESTMP          ; Y STILL HOLDS IT
                TFR     S,X             ; X = S AT THE SAVED REGISTERS
                ORCC    #$50            ; MASK IRQ BEFORE S LEAVES THE CALLER
                LDS     IODEP           ; $EC00, OR THE FRAME BELOW AN OUTER CALL
                LDB     PAGEID
                PSHS    X,Y,D           ; 1 PAGE, 2 CALLER S, 4 DESTINATION
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE NEW PAGE
                LDS     2,S             ; SAVED REGS. PULS LEAVES THE RETURN PC
                PULS    CC,A,B,X,Y
                JSR     [DESTMP]
                PSHS    CC,A            ; RESULT. S IS 2 BELOW THE RETURN PC
                ORCC    #$50
                STS     DESTMP
                LDS     IODEP
                LDA     1,S             ; CALLER PAGE
                LEAS    6,S             ; DROP THIS FRAME
                STS     IODEP
                STA     PAGEREG         ; NEXT OPCODE IS FETCHED FROM THE CALLER PAGE
                LDS     DESTMP
                PULS    CC,A
                RTS

;* SPI_INIT. CS HIGH, THEN 125 KHZ, INTN OFF.
;* EIGHT $FF AT THE SPEED ALREADY IN SPI_IMG, THEN THE SLOW CLOCK.
;* A CARD LEFT AT 1 MHZ IS RELEASED BEFORE THE CLOCK DROPS.
;* A DESTROYED. B KEPT. C = 0 DONE. C = 1 SHIFTER STILL BUSY.
SPI_INIT        PSHS    B
                LDA     SPI_IMG
                ANDA    #CTL_SPD        ; KEEP THE CURRENT SPEED, CS HIGH
                BSR     SPI_PUTC
                BCS     INIT_X
                LDB     #8              ; 64 CLOCKS BEFORE THE SLOWDOWN
INIT_FF         LDA     #$FF
                BSR     SPI_BYTE
                BCS     INIT_X
                DECB
                BNE     INIT_FF
                LDA     #IMG_IDLE       ; 125 KHZ, CS HIGH, INTN OFF
                BSR     SPI_PUTC
                BCS     INIT_X
                CLRA
INIT_X          PULS    B,PC

;* SPI_SEL. ASSERT CS NUMBER IN B (0-3). OTHER CS STAY HIGH.
;* SPEED AND IE ARE LEFT AS THEY ARE. B KEPT.
;* C = 0 DONE. C = 1 STILL BUSY, IMAGE NOT WRITTEN.
SPI_SEL         PSHS    A,B
                LDB     1,S             ; CALLER'S B
                ANDB    #CTL_CS
                ORB     #CTL_ON         ; THAT CS LOW
                LDA     SPI_IMG
                ANDA    #CTL_SPD|CTL_IE ; KEEP SPEED AND INTN
                PSHS    B
                ORA     ,S+
                BSR     SPI_PUTC
                PULS    A,B,PC

;* SPI_IDLE. ALL CHIP SELECTS HIGH. SPEED AND IE KEPT.
;* WAITS FOR THE SHIFTER, THEN CLOCKS ONE $FF WITH CS HIGH.
;* C = 0 DONE. C = 1 STILL BUSY, IMAGE NOT WRITTEN.
SPI_IDLE        PSHS    A
                LDA     SPI_IMG
                ANDA    #CTL_SPD|CTL_IE ; CS BITS OFF
                BSR     SPI_PUTC
                BCS     IDLE_X
                LDA     #$FF
                BSR     SPI_BYTE        ; CLOCK THE CARD WITH CS HIGH
IDLE_X          PULS    A,PC

;* SPI_SPD. A = 0..3, 1 MHZ DOWN TO 125 KHZ. A KEPT.
;* C = 0 DONE. C = 1 STILL BUSY, IMAGE NOT WRITTEN.
SPI_SPD         PSHS    A
                ANDA    #3
                LSLA                    ; SPEED INTO D4-D3
                LSLA
                LSLA
                PSHS    A
                LDA     SPI_IMG
                ANDA    #CTL_CS|CTL_ON|CTL_IE
                ORA     ,S+
                BSR     SPI_PUTC
                PULS    A,PC

;* SPI_BYTE. EXCHANGE A. A RETURNS MISO.
;* C = 0 BYTE VALID. C = 1 TIMEOUT, A = $FF. B, X, Y KEPT.
;* SAME CLOCK AS P5CLK. SPI_WAIT, WITH THE LONG GIVE-UP, STAYS ON SPI_PUTC.
SPI_BYTE        PSHS    A,B
                LDB     #SP_SPIN
BY0             LDA     SPI_STA
                BPL     BYSEND
                DECB
                BNE     BY0
                BRA     BY_TMO
BYSEND          LDA     ,S
                STA     SPI_DAT         ; WRITE STARTS THE EIGHT CLOCKS
                LDB     #SP_SPIN
BY1             LDA     SPI_STA
                BPL     BYOK
                DECB
                BNE     BY1
BY_TMO          PULS    A,B
                LDA     #$FF
                ORCC    #$01
                RTS
BYOK            LDA     SPI_DAT         ; BYTE NOW IN THE SHIFTER
                STA     ,S
                ANDCC   #$FE
                PULS    A,B,PC

;* SPI_PUTC. WRITE A TO CTRL ONCE THE SHIFTER IS IDLE. UPDATES SPI_IMG.
;* A, B, X, Y KEPT. C = 0 WRITTEN. C = 1 NOT WRITTEN.
SPI_PUTC        BSR     SPI_WAIT
                BCS     PUTC_R
                STA     SPI_IMG
                STA     SPI_CTL
                ANDCC   #%11111110
PUTC_R          RTS

;* SPI_WAIT. WAIT UNTIL D7 OF STAT IS CLEAR.
;* A, B, X, Y KEPT. C = 0 IDLE. C = 1 TIMEOUT.
SPI_WAIT        PSHS    A,X
                LDX     #SPI_TMO
WAIT_LP         LDA     SPI_STA
                BPL     WAIT_OK         ; D7 CLEAR
                LEAX    -1,X
                BNE     WAIT_LP
                PULS    A,X
                ORCC    #%00000001
                RTS
WAIT_OK         PULS    A,X
                ANDCC   #%11111110
                RTS


;* CMD7. SEND THE SIX BYTES AT X. SPI STAYS ON THIS PAGE. CS ENDS LOW.
;* A = R1. C = 1, A = $FF, CS HIGH ON FAILURE.
CMD7            BSR     SPI_IDLE
                BCS     CM7X
                LDA     #$FF
                BSR     SPI_BYTE
                BCS     CM7X
                LDB     SDCS
                ANDB    #CTL_CS
                JSR     SPI_SEL
                BCS     CM7X
                LDB     #6
CM71            LDA     ,X+
                BSR     SPI_BYTE
                BCS     CM7X
                DECB
                BNE     CM71
                JSR     TOK7            ; R1
                RTS
CM7X            JSR     SPI_IDLE
                LDA     #$FF
                ORCC    #$01
                RTS

;* TOK7. CLOCK UNTIL MISO IS NOT $FF. A = THAT BYTE. B KEPT.
;* C = 1 AND A = $FF AFTER $4000 BYTES OR AN SPI FAILURE.
TOK7            PSHS    B
                LDX     #$4000
TK71            LDA     #$FF
                JSR     SPI_BYTE
                BCS     TK72
                CMPA    #$FF
                BNE     TK73
                LEAX    -1,X
                BNE     TK71
                LDA     #$FF
                ORCC    #$01
TK72            PULS    B,PC
TK73            ANDCC   #$FE
                PULS    B,PC

;* BSY7. WAIT WHILE THE CARD HOLDS MISO LOW. C = 1 AFTER 65536 BYTES.
BSY7            LDX     #0
BS71            LDA     #$FF
                JSR     SPI_BYTE
                BCS     BS72
                TSTA
                BNE     BS73
                LEAX    -1,X
                BNE     BS71
                ORCC    #$01
BS72            RTS
BS73            RTS                     ; C IS ALREADY CLEAR

;* SDROPEN. CMD17. C = 0 AND THE $FE TOKEN HAS BEEN SEEN. CS STAYS LOW.
SDROPEN         LDA     #$51            ; CMD17
                JSR     FARCALL         ; PAGE $12, BUILD THE COMMAND
                FCB     PG_INIT
                FDB     MKCMD
                BCS     SPIBAD
                LDX     #CMDBUF
                BSR     CMD7
                BCS     SPIBAD
                TSTA
                BNE     SPIBAD
                BSR     TOK7            ; DATA TOKEN
                BCS     SPIBAD
                CMPA    #$FE
                BNE     SPIBAD          ; C IS ALREADY CLEAR WHEN EQUAL
                RTS
;* SHARED FAIL. C = 1 AND CS HIGH. THE OTHER THREE TAILS BRANCH HERE.
SPIBAD          JSR     SPI_IDLE
                ORCC    #$01
                RTS

;* SDRCLOSE. TWO CRC BYTES, THEN CS HIGH.
SDRCLOSE        LDA     #$FF
                JSR     SPI_BYTE
                BCS     RCLBAD
                LDA     #$FF
                JSR     SPI_BYTE
                BCS     RCLBAD
                JSR     SPI_IDLE
                BCS     RCLBAD          ; C IS ALREADY CLEAR
                RTS
RCLBAD          BRA     SPIBAD

;* SDWOPEN. CMD24, ONE $FF, THEN THE $FE DATA TOKEN.
;* C = 0 AND CS LOW WHEN THE DATA MAY BE SENT.
SDWOPEN         LDA     #$58            ; CMD24
                JSR     FARCALL
                FCB     PG_INIT
                FDB     MKCMD
                BCS     WOPBAD
                LDX     #CMDBUF
                JSR     CMD7
                BCS     WOPBAD
                TSTA
                BNE     WOPBAD
                LDA     #$FF            ; NWR, ONE BYTE BEFORE THE TOKEN
                JSR     SPI_BYTE
                BCS     WOPBAD
                LDA     #$FE            ; SINGLE BLOCK TOKEN
                JSR     SPI_BYTE
                BCS     WOPBAD          ; C IS ALREADY CLEAR
                RTS
WOPBAD          BRA     SPIBAD

;* SDWCLOSE. TWO CRC BYTES, DATA RESPONSE, BUSY, ONE $FF, CS HIGH.
;* C = 0 WHEN THE CARD ACCEPTED THE BLOCK.
SDWCLOSE        LDA     #$FF
                JSR     SPI_BYTE
                BCS     WCLBAD
                LDA     #$FF
                JSR     SPI_BYTE
                BCS     WCLBAD
                JSR     TOK7            ; DATA RESPONSE
                BCS     WCLBAD
                ANDA    #$1F
                CMPA    #$05            ; DATA ACCEPTED
                BNE     WCLBAD
                JSR     BSY7
                BCS     WCLBAD
                LDA     #$FF            ; ONE CLOCK BYTE, THEN CS HIGH
                JSR     SPI_BYTE
                BCS     WCLBAD
                JSR     SPI_IDLE
                BCS     WCLBAD          ; C IS ALREADY CLEAR
                RTS
WCLBAD          BRA     SPIBAD

P15END          EQU     *
                FILL    $00,$EA00-*

;* PAGES $16-$3F ARE FREE. THE CHIP ENDS AT $8000.
                ORG     $E800
                FILL    $00,($40-PG_SPI-1)*512

                END
