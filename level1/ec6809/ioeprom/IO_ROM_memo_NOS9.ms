.nr HY 0
.hy 0
.EH 'EC-6809 I/O EPROM, NitrOS-9 part''%'
.OH 'EC-6809 I/O EPROM, NitrOS-9 part''%'
.EF 'io_eprom_nos9, 17 November 2026''%'
.OF 'io_eprom_nos9, 17 November 2026''%'
.TL
EC-6809 I/O EPROM, NitrOS-9 part
.br
What is in pages $10\(en$3F, and how NitrOS-9 calls it
.AU
Philippe Roehr
.AI
EC-6809 / HD63C09, NitrOS-9
.AB
This note describes the NitrOS-9 part of the I/O EPROM, built from
.I level1/ec6809/ioeprom/io_eprom_nos9.asm
into
.I io_eprom_nos9.bin
by make in
.I recipes/ec6809 ,
and the NitrOS-9 modules that use it.
The chip is an AT28C256, 32 Kbytes.
Its first 8 Kbytes, pages $00\(en$0F, are the FLEX part,
.I IO_EPROM_V6.bin ,
unchanged.
The last 24 Kbytes, pages $10\(en$3F, are this part.
.PP
The two parts share the hardware, the page window and the FARCALL code, and nothing else.
No routine in one part calls a page of the other.
This part keeps its own copy of the SPI, SD and I2C code, copied from the FLEX part, with its public slots on page $10.
Its variables and the FARCALL frames are in the I/O RAM at $EA00\(en$EBFF, so it uses no main RAM.
The same entries serve NitrOS-9 Level 1 and Level 2.
One 256-byte sector takes about 8 ms, as in the FLEX part.
.AE
.NH
The chip and its two parts
.hy 0
.PP
The CPU sees one 512-byte page of the chip at $E800\(en$E9FF.
A write to the latch at $EEB0 chooses the page.
The latch has eight bits, so it reaches all 64 pages of an AT28C256.
Page N is the 512 bytes at chip offset N times 512.
.TS
center box;
c c lw(3.6i).
Pages	Chip bytes	Contents
$00\(en$09	$0000\(en$13FF	FLEX part, IO_EPROM_V6. Slots on page 1.
$0A\(en$0F	$1400\(en$1FFF	Spare for FLEX, $00.
$10\(en$15	$2000\(en$2BFF	NitrOS-9 part, this note. Slots on page $10.
$16\(en$3F	$2C00\(en$7FFF	Free, $00.
.TE
.PP
make builds only the NitrOS-9 part, 24 Kbytes, as
.I io_eprom_nos9.bin .
The chip image is the two files joined by hand, FLEX part first:
.DS L
.ft CW
cat IO_EPROM_V6.bin io_eprom_nos9.bin > chip.bin
.ft
.DE
.PP
Program chip.bin from address 0 of the AT28C256.
Do not load it as a CPU memory image at $E800.
.PP
The CPU board ROM at $F000\(en$FFFF decides which system starts.
ESS540 and ASSIST-09 start FLEX and use the FLEX part.
The NitrOS-9 boot ROM starts NitrOS-9 and uses this part.
Both parts can sit in the same chip, and either system can be started from it.
A card, however, holds either FLEX disks or one NitrOS-9 disk, not both.
Both systems put sector N in the first half of block N, from block 0.
.NH
The window and FARCALL
.hy 0
.PP
The first byte of every page, at $E800, is the page number.
Read it to see which page is mapped.
FARCALL occupies $E801 through the RTS at $E84A.
Those bytes are the same on every page of both parts.
A store to $EEB0 changes the page before the next opcode is fetched, so the bytes after that store must exist, identical, on the page just selected.
.PP
On page $10, $E84B\(en$E84F are spare and the first slot is $E850.
On every other page of this part the body begins at $E84B.
.PP
From outside the chip, select page $10 and JSR the slot.
.DS L
.ft CW
LDA   #$10             NOSPAGE
STA   $EEB0
LDA   #0               card CS0
JSR   $E868            example: P_SDSTAT
.ft
.DE
.PP
The slot calls the real routine on its own page and returns with page $10 mapped again.
Registers and flags are those of the routine.
Errors are NitrOS-9 error codes in B, with carry set.
.PP
Inside the chip, call the body on its own page with FARCALL.
Do not JSR a slot, and do not put a P_ address in an FDB.
.DS L
.ft CW
JSR   $E801            FARCALL
FCB   $15              page of SPI_IDLE
FDB   SPI_IDLE         the body
.ft
.DE
.PP
FARCALL saves the caller's CC, A, B, X and Y, switches page, and calls the body.
U is not saved and not used, so a slot can take a pointer in U.
The body runs on the caller's stack, with the caller's I and F bits.
IRQ and FIRQ are masked only across the latch write and while S is on the I/O stack.
.PP
The FARCALL frame is not on the caller's stack.
The word at $EA00 points at the next frame.
Each frame is 6 bytes, below $EC00, and a call is never more than four frames deep.
The word at $EA00 must hold $EC00 before the first call.
FARCALL does not set it.
Do not write $EC00 itself: that address is the 6845 CRTC.
.NH
Setting it up
.hy 0
.PP
The NitrOS-9 boot ROM replaces ESS540 and ASSIST-09, so nothing else sets up the I/O board.
Whatever page is mapped after reset, the booter does this before its first call:
.DS L
.ft CW
LDA   #$10
STA   $EEB0            EPROM page $10
CLR   $EEC0            I/O RAM page 0
LDD   #$EC00
STD   $EA00            no FARCALL frame yet
JSR   $E850            P_NINIT
.ft
.DE
.PP
I/O RAM page 0 must stay selected while any call runs, because it holds the frames and the variables.
P_NINIT gives every variable its start value and probes both cards.
It is called once, at boot.
.NH
What the pages hold
.hy 0
.LP
.TS
center box;
c c lw(3.6i).
Page	Last byte used	Contents
$10	$E8CF	Public slots. Next free slot is $E8D0.
$11	$E9C0	PCF8584, then the DS3231 read and BCDHEX.
$12	$E9F8	NINIT, NSDONE, SDSTAT, MKCMD, SDCCSX, SDINIT and SDONE.
$13	$E9F3	Fast data loops, RDSEC, WRSEC, SECSET and SDCMD.
$14	$E9DD	SDTRY, SDC0, SDOCR, and the fixed command tables.
$15	$E9DF	SPI master, and the sector command.
.TE
.PP
Unused bytes of a page are $00, through $E9FF.
On the HD63C09, $00 is a NEG direct instruction, so running into the fill does not return.
Page $12 has only 7 bytes left.
.PP
Pages $11, $14 and $15 are the FLEX part's pages 2, 6 and 7.
Page $12 is the FLEX page 4 plus the new card entries.
Page $13 is the FLEX page 5 with the NitrOS-9 sector entries in place of the FLEX ones.
The code is the same, with only the page numbers changed, and one addition in MKCMD (see below).
The FLEX sector entries, the spooler call, SDWRITE, SDBOOT and the FLEX disk page are not in this part.
.PP
A sector does not fit on one page together with the SPI master.
The 256-byte loops stay on page $13.
The command, the chip select and the token wait stay on page $15, next to SPI_BYTE.
Building the six command bytes is one FARCALL from page $15 to MKCMD on page $12.
.NH
RAM owned by this part
.hy 0
.PP
Everything is in I/O RAM page 0.
The NitrOS-9 kernel does not reserve any main RAM for the EPROM.
.TS
center box;
l l lw(3.6i).
Address	Name	Use
$EA00	IODEP	Next FARCALL frame, or $EC00 when no call runs.
$EA02	DESTMP	Destination address, then caller S on the way home.
$EA10	SDCS	Card of the command in progress, 0 = CS0, 1 = CS1.
$EA11	unused	Left alone.
$EA12	SDOK0	T{
.na
$00 usable. $01 tested, no card or it failed. $02 not tested.
T}
$EA13	SDOK1	Same three values for CS1.
$EA14	SDLBA0	LBA bits 7\(en0.
$EA15	SDLBA1	LBA bits 15\(en8.
$EA16	SDLBA2	LBA bits 23\(en16.
$EA17	SDLBA3	LBA bits 31\(en24. Always 0.
$EA18	SPI_IMG	Last byte written to the SPI control register.
$EA19	CMDBUF	Six-byte SD command, $EA19\(en$EA1E.
$EA1F	SDCCS0	0 = SDSC byte address. 1 = SDHC/SDXC block address.
$EA20	SDCCS1	Same flag for CS1.
$EA21	SDWSHT	Nonzero: SDWAIT stops after 16 bytes. Init CMD0 only.
$EA22	unused	Left alone.
$EA23	SDSHF	ACMD41 retry count during init.
$EA24	I2C_FLAG	PCF8584 state.
$EBFF\(en	frames	FARCALL frames, 6 bytes each, growing down from $EBFF.
.TE
.PP
The offsets from $EA10 are those of the FLEX part's block at $DE6B.
The FLEX part uses the same FARCALL words and frames, and nothing else in this RAM.
Only one system runs at a time, so they never meet.
.NH
SPI, briefly
.hy 0
.PP
The SPI master at $EE90 is driven exactly as in the FLEX part, whose memo describes it in full.
With E at 1.8432 MHz the four speeds are 921.6, 460.8, 230.4 and 115.2 kHz.
The source and this note call them 1 MHz, 500 kHz, 250 kHz and 125 kHz.
Cards are probed at 125 kHz and then run at 1 MHz.
The 256-byte loops take 30 E cycles a byte to read, 26 to send, and 25 to send $FF or $00.
.NH
Public routines
.hy 0
.PP
Addresses are the page-$10 slots.
Select page $10, then JSR the address.
.NH 2
SD cards
.hy 0
.PP
Each card has a flag: $00 usable, $01 no card or it failed, $02 not tested.
Only $00 can be read or written.
A card is numbered 0 for CS0 and 1 for CS1.
.IP \(bu 3
P_NINIT, $E850.
Body NINIT on page $12.
Gives every variable of the table above its start value, marks both cards $02, and sends the SPI master to 125 kHz with every chip select high.
Then it probes both cards, as P_SDINIA.
Carry clear and B = 0 when at least one card is usable.
Carry set and B = E$NotRdy ($F6) when none is.
A and X are destroyed.
Y and U are kept.
.IP \(bu 3
P_SDINIA, $E858.
Body SDINIT on page $12.
Probes each card whose flag is not $00 or $01: CMD0 to CS0, then CMD0 to CS1, at 125 kHz, then CMD8 and ACMD41 for the cards that answered.
The master then goes to 1 MHz once, and CMD58 stores $00 or $01 for each card that became ready.
A card already $00 or $01 receives no command.
Same exit as P_NINIT.
The disk driver calls this from its Init, so a second call costs nothing.
.IP \(bu 3
P_SDINIT, $E860.
Body NSDONE on page $12.
A = card.
Forces a probe of that card whatever its flag.
Carry clear and B = 0 when the card is now usable.
Carry set and B = E$NotRdy when it is not.
Carry set and B = E$Unit ($F0) when A is not 0 or 1.
A and X are destroyed.
Y and U are kept.
.IP \(bu 3
P_SDSTAT, $E868.
Body SDSTAT on page $12.
A = card.
B returns its flag, with carry clear.
Carry set and B = E$Unit when A is not 0 or 1.
A and X are kept.
.NH 2
One sector
.hy 0
.PP
A NitrOS-9 sector is 256 bytes.
On the card it is the first half of one 512-byte block, and the block number is the LSN.
A write stores the 256 data bytes and then 256 zeros.
Nothing reads the second half back.
.IP \(bu 3
P_RDSEC, $E870.
Body RDSEC on page $13.
A = card.
B = LSN bits 23\(en16.
X = LSN bits 15\(en0.
U = buffer.
This is the register order RBF gives a driver, with the card added in A.
Carry clear and B = 0 means the 256 bytes are in the buffer.
Carry set and B = E$Unit, E$NotRdy or E$Read ($F4) means failure.
A, X, Y and U are kept.
.IP \(bu 3
P_WRSEC, $E878.
Body WRSEC on page $13.
Same entry as P_RDSEC.
The buffer is not changed.
Carry set and B = E$Unit, E$NotRdy or E$Write ($F5) means failure.
.PP
Both entries check the card number and the flag first, so a driver need not.
An SDHC or SDXC card takes the LSN as its block number.
An SDSC card takes the byte address, the LSN shifted left 9.
MKCMD returns carry set when that address does not fit in 32 bits, so a large LSN on a small card fails instead of wrapping to block 0.
That check is the one addition to the code copied from the FLEX part, where an LSN never has more than 16 bits.
.PP
The buffer is read and written in the map of the caller.
It must not be in $E000\(en$FFFF.
.PP
A sector read looks like this.
.DS L
.ft CW
LDA   #$10
STA   $EEB0
LDA   #0               card CS0
CLRB                   LSN bits 23-16
LDX   #lsn             LSN bits 15-0
LDU   #buffer
JSR   $E870            P_RDSEC
BCS   failed           B is the error code
.ft
.DE
.NH 2
I2C and the DS3231
.hy 0
.PP
These are the FLEX part's I2C and DS3231 routines, unchanged, at other addresses.
The FLEX memo describes the sequences in full.
The state byte is I2C_FLAG at $EA24.
Z set means success.
.TS
center box;
l l lw(3.4i).
Slot	Address	Job
P_I2C_INIT	$E880	PCF8584 init. Call once before the first transfer.
P_I2C_START	$E888	Wait for a free bus. The next write sends START.
P_I2C_RESTART	$E890	Repeated START.
P_I2C_STOP	$E898	STOP.
P_I2C_WRITE	$E8A0	Send B. A is the status, Z set on ACK.
P_I2C_READ_ACK	$E8A8	Receive one byte into B, with ACK.
P_I2C_READ_NACK	$E8B0	Receive the last byte into B.
P_RTC_OK	$E8B8	Z set if the DS3231 answers. A, B, X destroyed.
P_RTC_GET_BYTE	$E8C0	T{
.na
A = register. Z set and B = its value. A, X destroyed.
T}
P_BCDHEX	$E8C8	BCD in A, binary in A. B kept.
.TE
.NH
How NitrOS-9 uses it
.hy 0
.PP
The sources are in the
.I ec6809
branch of the NitrOS-9 tree.
The modules include
.I ec6809.d ,
which names NOSPAGE ($10), the latches, $EA00 and every slot.
.IP \(bu 3
The booter, boot_ec6809spi, sets up the I/O board as shown above and calls P_NINIT.
It checks the boot card with P_SDSTAT, then reads OS9Boot with P_RDSEC.
The boot card is chosen when the ROM is built, CS0 by default.
.IP \(bu 3
The disk driver, rbec6809spi, makes drive 0 CS0 and drive 1 CS1.
Its Init calls P_SDINIA.
Read and Write select page $10, put the drive number in A and the path buffer in U, and call P_RDSEC or P_WRSEC.
The error code comes from the EPROM unchanged.
.IP \(bu 3
The RTC module, clock2_ec6809rtc, sets up the PCF8584 and reads the DS3231 once at boot, from its Init.
It reads it again once a minute from the tick interrupt, and sets it with the I2C entries when setime is used.
.IP \(bu 3
The disk image is laid out for the card by
.I recipes/ec6809/sdimage.py ,
sector N in the first half of block N.
.PP
Only one call into this part may run at a time.
The driver and the clock module call it only in system state.
The minute read runs at IRQ level, so it calls the EPROM only while $EA00 holds $EC00, which means no FARCALL is in progress.
It reads the page number at $E800 first and writes it back to $EEB0 afterwards.
Otherwise it counts the minute in software.
The set runs with IRQ masked, so the minute read cannot start in the middle of it.
.PP
Under Level 2 the same entries are called from the system task.
The system task's map must put the I/O block at $E000, and a buffer address is a system address.
User tasks need not see the I/O block.
.NH
Differences from the FLEX part
.hy 0
.LP
.TS
center box;
l lw(2.4i) lw(2.4i).
	FLEX part	NitrOS-9 part
Pages	$00\(en$09	$10\(en$15
Slots	page 1, from $E870	page $10, from $E850
Variables	main RAM, $DE6B\(en$DE7F	I/O RAM, $EA10\(en$EA24
Card choice	SDCS in RAM	A, on each call
Sector number	A = track, B = sector, 16 bits	B:X, 24 bits
Buffer	X	U
Errors	$40, $80	E$Unit, E$NotRdy, E$Read, E$Write
Spooler	SWI3 when $CC34 is not 0	none
Not present	\(em	T{
.na
SPI and SDCMD helper slots, SDWRITE, SDBOOT, FLEX disk entry
T}
.TE
.NH
Points worth remembering
.hy 0
.IP 1 3
Program the FLEX part at chip address 0 and this part at $2000, as one 32-Kbyte file.
.IP 2 3
From outside: select page $10, JSR the slot.
From inside: FARCALL with the page byte and the body address.
.IP 3 3
Before the first call, select I/O RAM page 0 and store $EC00 at $EA00.
Then call P_NINIT once.
.IP 4 3
Errors are NitrOS-9 codes in B with carry set.
.IP 5 3
A card is passed in A on each call.
There is no current-card variable to set first.
.IP 6 3
Only one call may run at a time.
Interrupt code may call a slot only while $EA00 holds $EC00, and must put back the page it read at $E800.
.IP 7 3
Neither part calls the other.
A change to the FLEX part does not change this one, and the reverse.
.IP 8 3
The next free slot is $E8D0.
Do not insert a slot in front of an existing one.
.NH
Slot list
.hy 0
.LP
.TS
center box;
l l lw(2.4i).
Slot	Address	Body
P_NINIT	$E850	page $12, NINIT
P_SDINIA	$E858	page $12, SDINIT
P_SDINIT	$E860	page $12, NSDONE
P_SDSTAT	$E868	page $12, SDSTAT
P_RDSEC	$E870	page $13, RDSEC
P_WRSEC	$E878	page $13, WRSEC
P_I2C_INIT	$E880	page $11, I2C_INIT
P_I2C_START	$E888	page $11, I2C_START
P_I2C_RESTART	$E890	page $11, I2C_RESTART
P_I2C_STOP	$E898	page $11, I2C_STOP
P_I2C_WRITE	$E8A0	page $11, I2C_WRITE
P_I2C_READ_ACK	$E8A8	page $11, I2C_READ_ACK
P_I2C_READ_NACK	$E8B0	page $11, I2C_READ_NACK
P_RTC_OK	$E8B8	page $11, RTC_OK
P_RTC_GET_BYTE	$E8C0	page $11, RTC_GET_BYTE
P_BCDHEX	$E8C8	page $11, BCDHEX
.TE
.NH
Files
.hy 0
.LP
.TS
center box;
l l lw(2.6i).
Source	Output	Use
io_eprom_nos9.asm	T{
.na
io_eprom_nos9.bin, .lst
T}	T{
.na
This part. make in recipes/ec6809 builds it with lwasm.
T}
IO_EPROM_V6.asm	IO_EPROM_V6.bin	T{
.na
The FLEX part, pages $00\(en$0F. Built with a09.
T}
IO_ROM_memo_V6	\(em	T{
.na
The FLEX part's memo.
T}
boot_ec6809spi.asm	bootrom	T{
.na
NitrOS-9 booter, in the CPU board ROM.
T}
rbec6809spi.asm	OS9Boot	T{
.na
SD card disk driver.
T}
clock2_ec6809rtc.asm	OS9Boot	T{
.na
DS3231 clock module.
T}
ec6809.d	\(em	T{
.na
Latches, $EA00, NOSPAGE and the slot addresses.
T}
sdimage.py	*.sd	T{
.na
Card layout of the disk image.
T}
.TE
.PP
io_eprom_nos9.asm and this memo are in
.I level1/ec6809/ioeprom .
The modules are in
.I level1/ec6809/modules ,
ec6809.d in
.I level1/ec6809/defs ,
and sdimage.py in
.I recipes/ec6809 ,
all in the NitrOS-9 tree.
IO_EPROM_V6.asm and its memo are in
.I Flex_Drivers/WITH_SD
of the EC-6809 project.
