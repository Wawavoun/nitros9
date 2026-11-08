* PCF mutation support. Caller holds the device-wide file-manager lock.
* Writes are synchronous. The media must not be modified outside this mount.
Create              pshs      x
                    leax      CreateImpl,pcr
                    bra       FMLocked
MkDir               pshs      x
                    leax      MkDirImpl,pcr
                    lbra      FMLocked
Open                pshs      x
                    leax      OpenImpl,pcr
                    bra       FMLocked
ChgDir              pshs      x
                    leax      ChgDirImpl,pcr
                    bra       FMLocked
Delete              pshs      x
                    leax      DeleteImpl,pcr
                    bra       FMLocked
Seek                pshs      x
                    leax      SeekImpl,pcr
                    bra       FMLocked
Read                pshs      x
                    leax      ReadImpl,pcr
                    bra       FMLocked
ReadLn              pshs      x
                    leax      ReadLnImpl,pcr
                    bra       FMLocked
Write               pshs      x
                    leax      WriteImpl,pcr
                    bra       FMLocked
WriteLn             pshs      x
                    leax      WriteLnImpl,pcr
                    bra       FMLocked
GetStat             pshs      x
                    leax      GetStatImpl,pcr
                    bra       FMLocked
SetStat             pshs      x
                    leax      SetStatImpl,pcr
                    bra       FMLocked
Close               pshs      x
                    leax      CloseImpl,pcr
FMLocked            pshs      x
                    ldx       PD.DEV,y
                    ldx       V$STAT,x
                    pshs      cc
                    orcc      #IntMasks
                    tst       V.BUSY,x
                    bne       fmbusy@
                    inc       V.BUSY,x
                    puls      cc
* Per-open buffers must not hide changes made through another open path.
                    ldx       PD.BUF,y
                    beq       fmcall@
                    clr       F.DataValid,x
                    clr       F.FatValid,x
fmcall@             jsr       [,s]
                    pshs      b,cc
                    ldx       PD.DEV,y
                    ldx       V$STAT,x
                    clr       V.BUSY,x
                    puls      b,cc
                    leas      2,s
                    puls      x,pc
fmbusy@             puls      cc
                    ldb       #E$DevBsy
                    coma
                    leas      2,s
                    puls      x,pc

Writable            lda       F.Info+BI.Flags,u
                    bita      #BF.ReadOnly
                    lbne      ReadOnly
                    clrb
                    rts
CanWriteFile        bsr       Writable
                    bcs       canret@
                    lda       F.Entry+11,u
                    bita      #$11                 readonly or directory
                    lbne      AccessError
                    tst       F.HasLFN,u           mutations are short-name only for now
                    lbne      AccessError
                    clrb
canret@             rts
Attributes          lda       #READ.+EXEC.+PREAD.+PEXEC.
                    bitb      #1
                    bne       attrdir@
                    pshs      b
                    ldb       F.Info+BI.Flags,u
                    bitb      #BF.ReadOnly
                    puls      b
                    bne       attrdir@
                    ora       #WRITE.+PWRIT.
attrdir@            bitb      #$10
                    beq       attrret@
                    ora       #DIR.
attrret@            rts

* Link live paths through opaque blkdrv file-manager storage. A writer excludes
* other opens of the same file; delete refuses even a read-open target.
RegisterPath        lda       PD.MOD,y
                    anda      #WRITE.
                    bsr       CheckSharing
                    bcs       registerret@
                    ldx       PD.DEV,y
                    ldx       V$STAT,x
                    ldd       BV.FMPaths,x
                    std       F.NextPath,u
                    stu       BV.FMPaths,x
                    inc       F.Registered,u
                    clrb
registerret@        rts
CheckSharing        pshs      a,x,y
                    ldx       PD.DEV,y
                    ldx       V$STAT,x
                    ldx       BV.FMPaths,x
shareloop@          cmpx      #0
                    beq       shareok@
                    pshs      u
                    cmpx      ,s++
                    beq       sharenext@
                    ldd       F.DirLBA,u
                    cmpd      F.DirLBA,x
                    bne       sharenext@
                    ldd       F.DirLBA+2,u
                    cmpd      F.DirLBA+2,x
                    bne       sharenext@
                    ldd       F.DirOff,u
                    cmpd      F.DirOff,x
                    bne       sharenext@
                    lda       F.Entry+11,u
                    bita      #$10
                    bne       sharenext@
                    tst       ,s
                    bne       sharebad@
                    ldy       F.Owner,x
                    lda       PD.MOD,y
                    bita      #WRITE.
                    bne       sharebad@
sharenext@          ldx       F.NextPath,x
                    bra       shareloop@
shareok@            clrb
                    puls      a,x,y,pc
sharebad@           ldb       #E$Share
                    coma
                    puls      a,x,y,pc
UnregisterPath      pshs      x
                    tst       F.Registered,u
                    beq       unlinkdone@
                    ldx       PD.DEV,y
                    ldx       V$STAT,x
                    leax      BV.FMPaths,x
unlinkloop@         tfr       u,d
                    cmpd      ,x
                    beq       unlinkfound@
                    ldx       ,x
                    beq       unlinkdone@
                    leax      F.NextPath,x
                    bra       unlinkloop@
unlinkfound@        ldd       F.NextPath,u
                    std       ,x
                    clr       F.Registered,u
unlinkdone@         puls      x,pc
EntryLocation       pshs      x
                    tfr       x,d
                    leax      F.Data,u
                    pshs      x
                    subd      ,s++
                    std       F.DirOff,u
                    leax      F.DataLBA,u
                    lbsr      LoadVal
                    leax      F.DirLBA,u
                    lbsr      StoreVal
                    puls      x,pc

* Remember valid reserved-sector FSInfo locations. Backup FSInfo is at
* BPB_BkBootSec + BPB_FSInfo; either may legitimately be absent.
MountWriteInfo      lda       F.Data+40,u
                    bita      #$80
                    bne       infoaddr@
                    inc       F.Mirror,u
infoaddr@           leax      F.Data+48,u
                    lbsr      LE16
                    ldd       F.Val+2,u
                    beq       infodone@
                    pshs      d
                    leax      F.Data+14,u
                    lbsr      LE16
                    ldd       ,s
                    cmpd      F.Val+2,u
                    bhs       infopop@
                    std       F.Saved+2,u
                    leax      F.Data+48,u
                    lbsr      LE16
                    leax      F.Base,u
                    lbsr      AddBase
                    leax      F.FSInfo,u
                    lbsr      StoreVal
                    leax      F.Data+50,u
                    lbsr      LE16
                    ldd       F.Val+2,u
                    beq       infopop@
                    addd      ,s
                    bcs       infopop@
                    std       ,s
                    leax      F.Data+14,u
                    lbsr      LE16
                    ldd       ,s
                    cmpd      F.Val+2,u
                    bhs       infopop@
                    std       F.Val+2,u
                    leax      F.Base,u
                    lbsr      AddBase
                    leax      F.BackInfo,u
                    lbsr      StoreVal
infopop@            leas      2,s
infodone@           rts

* Store Val little endian at X without changing its reserved FAT bits elsewhere.
PutLE               lda       F.Val+3,u
                    sta       ,x
                    lda       F.Val+2,u
                    sta       1,x
                    lda       F.Val+1,u
                    sta       2,x
                    lda       F.Val,u
                    sta       3,x
                    rts
WriteBlock          leax      F.Request+BR.LBA,u
                    lbsr      StoreVal
                    leax      F.Request,u
                    lda       #BD.Write
                    lbsr      Driver
                    bcs       writeblockret@
                    ldd       F.Request+BR.Done,u
                    cmpd      #1
                    lbne      BadMedia
                    clrb
writeblockret@      rts
WriteData           leax      F.Data,u
                    stx       F.Request+BR.Buffer,u
                    leax      F.DataLBA,u
                    lbsr      LoadVal
                    bra       WriteBlock
Flush               leax      F.Request,u
                    lda       #BD.Flush
                    lbra      Driver

* F.Cluster entry <- F.Value. Update every FAT if mirrored, active FAT only
* otherwise. Re-read each copy so its upper four reserved bits are preserved.
SetFat              clr       F.FatCopy,u
setfatloop@         lbsr      FatEntry
                    bcs       setfatret@
                    tst       F.FatCopy,u
                    beq       setfatstore@
                    leax      F.FatLBA,u
                    lbsr      LoadVal
                    leax      F.FatSize,u
                    lbsr      AddBase
                    lbsr      ReadFat
                    bcs       setfatret@
                    ldb       F.Cluster+3,u
                    andb      #127
                    clra
                    lslb
                    rola
                    lslb
                    rola
                    leax      d,x
setfatstore@        pshs      x
                    lda       3,x
                    anda      #$F0
                    pshs      a
                    leax      F.Value,u
                    lbsr      LoadVal
                    lda       F.Val,u
                    anda      #15
                    ora       ,s+
                    sta       F.Val,u
                    puls      x
                    lbsr      PutLE
                    leax      F.Fat,u
                    stx       F.Request+BR.Buffer,u
                    leax      F.FatLBA,u
                    lbsr      LoadVal
                    lbsr      WriteBlock
                    bcs       setfatret@
                    tst       F.Mirror,u
                    beq       setfatok@
                    inc       F.FatCopy,u
                    lda       F.FatCopy,u
                    cmpa      F.Fats,u
                    blo       setfatloop@
setfatok@           clrb
setfatret@          pshs      cc
                    clr       F.FatValid,u
                    puls      cc,pc

* Read and update optional FSInfo hints. Unknown counts stay unknown.
* Invalid/missing FSInfo is ignored; it is not authoritative allocation data.
UpdateHints         leax      F.FSInfo,u
                    lbsr      LoadVal
                    bsr       UpdateHint
                    bcs       hintret@
                    leax      F.BackInfo,u
                    lbsr      LoadVal
UpdateHint          ldd       F.Val,u
                    bne       hintread@
                    ldd       F.Val+2,u
                    beq       hintret@
hintread@           lbsr      ReadData
                    bcs       hintret@
                    ldd       ,x
                    cmpd      #$5252
                    bne       hintok@
                    ldd       2,x
                    cmpd      #$6141
                    bne       hintok@
                    ldd       484,x
                    cmpd      #$7272
                    bne       hintok@
                    ldd       486,x
                    cmpd      #$4161
                    bne       hintok@
                    leax      488,x
                    pshs      x
                    lbsr      LE32
                    ldd       F.Val,u
                    cmpd      #$FFFF
                    beq       hintunknown@
                    tst       F.HintDelta,u
                    bmi       hintdec@
                    lbsr      IncVal
                    bra       hintput@
hintdec@            lbsr      DecVal
hintput@            ldx       ,s
                    lbsr      PutLE
hintunknown@        puls      x
                    ldd       #$FFFF
                    std       4,x
                    std       6,x
                    lbra      WriteData
hintok@             clrb
hintret@            rts

ClusterBase         lbsr      DecVal
                    lbsr      DecVal
                    ldb       F.Shift,u
                    beq       clusterbase@
                    lbsr      ShiftLeft
                    bcs       baseret@
clusterbase@        leax      F.DataStart,u
                    lbsr      AddBase
baseret@            rts
* Return New = allocated, zeroed EOC cluster. Always consult the FAT itself.
Allocate            clra
                    clrb
                    std       F.New,u
                    ldd       #2
                    std       F.New+2,u
allocscan@          leax      F.New,u
                    lbsr      LoadVal
                    leax      F.MaxCluster,u
                    lbsr      CompareVal
                    lbhi      allocfull@
                    leax      F.Cluster,u
                    lbsr      StoreVal
                    lbsr      FatEntry
                    lbcs      allocret@
                    lbsr      LE32
                    lda       F.Val,u
                    anda      #15
                    ora       F.Val+1,u
                    ora       F.Val+2,u
                    ora       F.Val+3,u
                    beq       allocfree@
                    leax      F.New,u
                    lbsr      LoadVal
                    lbsr      IncVal
                    lbsr      StoreVal
                    bra       allocscan@
allocfree@          leax      F.New,u
                    lbsr      LoadVal
                    bsr       ClusterBase
                    bcs       allocret@
                    leax      F.DataLBA,u
                    lbsr      StoreVal
                    leax      F.Data,u
                    ldd       #512
alloczero@          clr       ,x+
                    subd      #1
                    bne       alloczero@
                    clr       F.DataValid,u
                    lda       F.SPC,u
                    sta       F.Sectors,u
allocsector@        lbsr      WriteData
                    bcs       allocret@
                    leax      F.DataLBA,u
                    lbsr      LoadVal
                    lbsr      IncVal
                    lbsr      StoreVal
                    dec       F.Sectors,u
                    bne       allocsector@
                    ldd       #$0FFF
                    std       F.Value,u
                    ldd       #$FFFF
                    std       F.Value+2,u
                    leax      F.New,u
                    lbsr      LoadVal
                    leax      F.Cluster,u
                    lbsr      StoreVal
                    lbsr      SetFat
                    bcs       allocret@
                    lda       #$FF
                    sta       F.HintDelta,u
                    lbsr      UpdateHints
                    rts
allocfull@          ldb       #E$Full
                    coma
allocret@           rts

* Validate the complete chain before destructive operations (including cycles).
ValidateChain       ldd       F.Start,u
                    bne       validatebegin@
                    ldd       F.Start+2,u
                    beq       validateok@
validatebegin@      lbsr      ResetWalk
                    bcs       validateret@
validateloop@       lbsr      Advance
                    bcc       validateloop@
                    cmpb      #E$EOF
                    bne       validatebad@
validateok@         clrb
validateret@        rts
validatebad@        coma
                    rts
* Free a previously validated chain beginning at Saved (zero is empty).
FreeChain           ldd       F.Saved,u
                    bne       freechainloop@
                    ldd       F.Saved+2,u
                    beq       freechainok@
freechainloop@      leax      F.Saved,u
                    lbsr      LoadVal
                    leax      F.Cluster,u
                    lbsr      StoreVal
                    lbsr      NextCluster
                    bcc       freenext@
                    cmpb      #E$EOF
                    bne       freechainbad@
                    clra
                    clrb
                    std       F.Val,u
                    std       F.Val+2,u
freenext@           leax      F.Link,u
                    lbsr      StoreVal
                    leax      F.Saved,u
                    lbsr      LoadVal
                    leax      F.Cluster,u
                    lbsr      StoreVal
                    clra
                    clrb
                    std       F.Value,u
                    std       F.Value+2,u
                    lbsr      SetFat
                    bcs       freechainret@
                    lda       #1
                    sta       F.HintDelta,u
                    lbsr      UpdateHints
                    bcs       freechainret@
                    leax      F.Link,u
                    lbsr      LoadVal
                    leax      F.Saved,u
                    lbsr      StoreVal
                    bra       FreeChain
freechainok@        clrb
freechainret@       rts
freechainbad@       coma
                    rts

* FAT timestamps from the kernel's six-byte clock (year is since 1900).
Stamp               pshs      x,y,cc
                    orcc      #IntMasks
                    ldx       #D.Time
                    leay      F.Time,u
                    ldb       #6
stampclock@         lda       ,x+
                    sta       ,y+
                    decb
                    bne       stampclock@
                    puls      cc,x,y
EncodeTime          lda       F.Time,u
                    cmpa      #80
                    bhs       stampyear@
                    lda       #80
stampyear@          suba      #80
                    lsla
                    sta       F.Entry+25,u
                    ldb       F.Time+1,u
                    bne       stampmonth@
                    ldb       #1
stampmonth@         tfr       b,a
                    lsra
                    lsra
                    lsra
                    ora       F.Entry+25,u
                    sta       F.Entry+25,u
                    lslb
                    lslb
                    lslb
                    lslb
                    lslb
                    lda       F.Time+2,u
                    bne       stampday@
                    lda       #1
stampday@           pshs      b
                    ora       ,s+
                    sta       F.Entry+24,u
                    lda       F.Time+3,u
                    lsla
                    lsla
                    lsla
                    sta       F.Entry+23,u
                    lda       F.Time+4,u
                    lsra
                    lsra
                    lsra
                    ora       F.Entry+23,u
                    sta       F.Entry+23,u
                    lda       F.Time+4,u
                    lsla
                    lsla
                    lsla
                    lsla
                    lsla
                    sta       F.Entry+22,u
                    lda       F.Time+5,u
                    lsra
                    ora       F.Entry+22,u
                    sta       F.Entry+22,u
                    rts
UpdateEntry         bsr       Stamp
CommitEntry         leax      F.Start,u
                    lbsr      LoadVal
                    lda       F.Val+1,u
                    sta       F.Entry+20,u
                    lda       F.Val,u
                    sta       F.Entry+21,u
                    lda       F.Val+3,u
                    sta       F.Entry+26,u
                    lda       F.Val+2,u
                    sta       F.Entry+27,u
                    leax      F.Size,u
                    lbsr      LoadVal
                    leax      F.Entry+28,u
                    lbsr      PutLE
                    lda       F.Entry+11,u
                    ora       #$20
                    sta       F.Entry+11,u
                    leax      F.DirLBA,u
                    lbsr      LoadVal
                    lbsr      ReadData
                    bcs       commitret@
                    ldd       F.DirOff,u
                    leax      d,x
                    pshs      x,y
                    leay      F.Entry,u
                    ldb       #11
commitcheck@        lda       ,x+
                    cmpa      ,y+
                    bne       commitgone@
                    decb
                    bne       commitcheck@
                    puls      x,y
                    bsr       CopyEntryToDisk
                    lbra      WriteData
commitgone@         puls      x,y
                    ldb       #E$Share
                    coma
commitret@          rts
CopyEntryToDisk     pshs      y
                    leay      F.Entry,u
                    ldb       #32
entryout@           lda       ,y+
                    sta       ,x+
                    decb
                    bne       entryout@
                    puls      y,pc

* The parent has already been resolved and Lookup proved the name absent.
CreateEntry         lbsr      Writable
                    lbcs      createret@
                    lda       PD.MOD,y
                    bita      #DIR.
                    beq       createkind@
                    lda       F.Creating,u
                    cmpa      #2
                    lbne      AccessError
createkind@         clr       F.WalkValid,u
                    clra
                    clrb
                    std       F.Scan,u
                    std       F.Scan+2,u
createscan@         leax      F.Scan,u
                    lbsr      LoadVal
                    leax      F.Offset,u
                    lbsr      StoreVal
                    lbsr      Locate
                    bcc       createslot@
                    cmpb      #E$EOF
                    lbne      createbad@
* A full directory grows by one zeroed cluster, including a fragmented root.
                    leax      F.Walk,u
                    lbsr      LoadVal
                    leax      F.Link,u
                    lbsr      StoreVal
                    lbsr      Allocate
                    lbcs      createret@
                    leax      F.New,u
                    lbsr      LoadVal
                    leax      F.Value,u
                    lbsr      StoreVal
                    leax      F.Link,u
                    lbsr      LoadVal
                    leax      F.Cluster,u
                    lbsr      StoreVal
                    lbsr      SetFat
                    lbcs      createret@
                    clr       F.WalkValid,u
                    bra       createscan@
createslot@         lda       ,x
                    beq       createfree@
                    cmpa      #$E5
                    beq       createfree@
                    lbsr      ScanNext
                    lbcs      createret@
                    bra       createscan@
createfree@         sta       F.Zero,u             zero means preserve end marker
                    lbsr      EntryLocation
                    pshs      x
                    leax      F.Entry,u
                    ldb       #32
createzero@         clr       ,x+
                    decb
                    bne       createzero@
                    pshs      y
                    leax      F.Name,u
                    leay      F.Entry,u
                    ldb       #11
createname@         lda       ,x+
                    sta       ,y+
                    decb
                    bne       createname@
                    puls      y
                    lda       #$20
                    ldb       F.Creating,u
                    cmpb      #2
                    bne       createattr@
                    lda       #$10
createattr@         sta       F.Entry+11,u
                    lbsr      Stamp
                    ldd       F.Entry+24,u
                    std       F.Entry+16,u
                    std       F.Entry+18,u
                    ldd       F.Entry+22,u
                    std       F.Entry+14,u
                    puls      x
                    lda       F.Creating,u
                    cmpa      #2
                    bne       createpublish@
                    lbsr      NewDirectory
                    bcs       createret@
createpublish@      lbsr      CopyEntryToDisk
                    lbsr      WriteData
                    bcs       createret@
                    tst       F.Zero,u
                    bne       createdone@
                    lbsr      ScanNext
                    bcs       createret@
                    leax      F.Scan,u
                    lbsr      LoadVal
                    leax      F.Offset,u
                    lbsr      StoreVal
                    lbsr      Locate
                    bcc       createend@
                    cmpb      #E$EOF
                    bne       createbad@
                    bra       createdone@
createend@          clr       ,x
                    lbsr      WriteData
                    bcs       createret@
createdone@         clr       F.Creating,u
                    clr       F.HasLFN,u
                    leax      F.Entry,u
                    lbsr      AdoptEntry
                    bcs       createret@
                    lbsr      Flush
createret@          rts
createbad@          coma
                    rts

* Locate a write position, allocating/linking a zeroed cluster as necessary.
EnsureCluster       ldd       F.Start,u
                    bne       ensurelocate@
                    ldd       F.Start+2,u
                    bne       ensurelocate@
                    lbsr      Allocate
                    bcs       ensureret@
                    leax      F.New,u
                    lbsr      LoadVal
                    leax      F.Start,u
                    lbsr      StoreVal
                    lbsr      UpdateEntry
                    bcs       ensureret@
                    clr       F.WalkValid,u
ensurelocate@       lbsr      Locate
                    bcc       ensureret@
                    cmpb      #E$EOF
                    bne       ensurebad@
                    leax      F.Walk,u
                    lbsr      LoadVal
                    leax      F.Link,u
                    lbsr      StoreVal
                    lbsr      Allocate
                    bcs       ensureret@
                    leax      F.New,u
                    lbsr      LoadVal
                    leax      F.Value,u
                    lbsr      StoreVal
                    leax      F.Link,u
                    lbsr      LoadVal
                    leax      F.Cluster,u
                    lbsr      StoreVal
                    lbsr      SetFat
                    bcs       ensureret@
                    clr       F.WalkValid,u
                    bra       ensurelocate@
ensurebad@          coma
ensureret@          rts

* Move F.Move bytes from caller F.Dest to system X, handling Level 2 tasks.
MoveIn              pshs      x,y,u
                    ifgt      Level-1
                    tfr       x,d
                    pshs      d
                    ldx       F.Dest,u
                    ldy       F.Move,u
                    pshs      y
                    ldy       <D.Proc
                    lda       P$Task,y
                    ldb       <D.SysTsk
                    puls      y
                    ldu       ,s++
                    os9       F$Move
                    else
                    ldy       F.Dest,u
                    ldd       F.Move,u
moveinloop@         cmpd      #0
                    beq       moveindone@
                    pshs      a
                    lda       ,y+
                    sta       ,x+
                    puls      a
                    subd      #1
                    bra       moveinloop@
moveindone@         clrb
                    endc
                    puls      x,y,u,pc

WriteImpl           clra
                    bra       WriteCommon
WriteLnImpl         lda       #1
WriteCommon         pshs      x,y,u
                    tfr       u,x
                    ldu       PD.BUF,y
                    stx       F.Regs,u
                    sta       F.Line,u
                    clr       F.Stop,u
                    clr       F.Zero,u
                    ldd       R$Y,x
                    std       F.Remain,u
                    ldd       R$X,x
                    std       F.Dest,u
                    clra
                    clrb
                    std       F.Actual,u
                    std       R$Y,x
                    lda       PD.MOD,y
                    bita      #WRITE.
                    lbeq      writemode@
                    lbsr      CanWriteFile
                    bcs       writereturn@
                    ldd       F.Remain,u
                    beq       writesuccess@
                    ldd       F.Pos+2,u
                    addd      F.Remain,u
                    ldd       F.Pos,u
                    adcb      #0
                    adca      #0
                    bcs       writeoverflow@
                    leax      F.Pos,u
                    lbsr      LoadVal
                    leax      F.GapEnd,u
                    lbsr      StoreVal
                    bsr       FillGap
                    bcs       writereturn@
writeloop@          ldd       F.Remain,u
                    beq       writesuccess@
                    bsr       ChunkSpace
                    cmpd      F.Remain,u
                    bls       writecount@
                    ldd       F.Remain,u
writecount@         std       F.Move,u
                    lbsr      PutChunk
                    bcs       writereturn@
                    ldd       F.Move,u
                    addd      F.Actual,u
                    std       F.Actual,u
                    ldd       F.Remain,u
                    subd      F.Move,u
                    std       F.Remain,u
                    ldd       F.Dest,u
                    addd      F.Move,u
                    std       F.Dest,u
                    tst       F.Stop,u
                    beq       writeloop@
writesuccess@       lbsr      Flush
writereturn@        pshs      b,cc
                    ldx       F.Regs,u
                    ldd       F.Actual,u
                    std       R$Y,x
                    puls      b,cc
                    puls      x,y,u,pc
writeoverflow@      ldb       #E$BTyp
                    coma
                    bra       writereturn@
writemode@          ldb       #E$BMode
                    coma
                    bra       writereturn@
ChunkSpace          ldd       F.Pos+2,u
                    anda      #1
                    pshs      d
                    ldd       #512
                    subd      ,s++
                    rts

* Fill a seek/resize gap with zeros; do not expose stale disk bytes.
FillGap             leax      F.GapEnd,u
                    lbsr      LoadVal
                    leax      F.Size,u
                    lbsr      CompareVal
                    bls       gapok@
                    leax      F.Size,u
                    lbsr      LoadVal
                    leax      F.Pos,u
                    lbsr      StoreVal
                    inc       F.Zero,u
gaploop@            leax      F.GapEnd,u
                    lbsr      LoadVal
                    leax      F.Pos,u
                    lbsr      CompareVal
                    beq       gapdone@
                    leax      F.Wanted,u
                    lbsr      StoreVal
                    leax      F.Pos,u
                    lbsr      LoadVal
                    leax      F.Wanted,u
                    lbsr      SubVal
                    bsr       ChunkSpace
                    std       F.Move,u
                    ldd       F.Wanted,u
                    bne       gapchunk@
                    ldd       F.Wanted+2,u
                    cmpd      F.Move,u
                    bhs       gapchunk@
                    std       F.Move,u
gapchunk@           bsr       PutChunk
                    bcc       gaploop@
                    pshs      cc
                    clr       F.Zero,u
                    puls      cc,pc
gapdone@            clr       F.Zero,u
gapok@              clrb
                    rts

PutChunk            leax      F.Pos,u
                    lbsr      LoadVal
                    leax      F.Offset,u
                    lbsr      StoreVal
                    lbsr      EnsureCluster
                    bcs       putret@
                    tst       F.Zero,u
                    beq       putuser@
                    ldd       F.Move,u
putzero@            clr       ,x+
                    subd      #1
                    bne       putzero@
                    bra       putdisk@
putuser@            lbsr      WriteLineCount
                    lbsr      MoveIn
                    bcs       putret@
putdisk@            lbsr      WriteData
                    bcs       putret@
                    ldd       F.Pos+2,u
                    addd      F.Move,u
                    std       F.Pos+2,u
                    ldd       F.Pos,u
                    adcb      #0
                    adca      #0
                    std       F.Pos,u
                    lbcs      BadMedia
                    leax      F.Pos,u
                    lbsr      LoadVal
                    leax      F.Size,u
                    lbsr      CompareVal
                    bls       putmetadata@
                    lbsr      StoreVal
putmetadata@        lbsr      UpdateEntry
putret@             rts

DeleteImpl          pshs      x,y,u
                    lda       PD.MOD,y
                    pshs      a
                    lda       #READ.
                    sta       PD.MOD,y
                    lbsr      OpenImpl
                    bcs       deletereturn@
                    ldu       PD.BUF,y
                    lbsr      CanWriteFile
                    bcs       deletefree@
                    lda       #WRITE.
                    lbsr      CheckSharing
                    bcs       deletefree@
                    lbsr      ValidateChain
                    bcs       deletefree@
                    leax      F.Start,u
                    lbsr      LoadVal
                    leax      F.Saved,u
                    lbsr      StoreVal
                    leax      F.DirLBA,u
                    lbsr      LoadVal
                    lbsr      ReadData
                    bcs       deletefree@
                    ldd       F.DirOff,u
                    leax      d,x
                    lda       #$E5
                    sta       ,x
                    lbsr      WriteData
                    bcs       deletefree@
                    lbsr      FreeChain
                    bcs       deletefree@
                    lbsr      Flush
deletefree@         pshs      b,cc
                    lbsr      FreePath
                    puls      b,cc
deletereturn@       puls      a
                    sta       PD.MOD,y
                    puls      x,y,u,pc

SetStatImpl         pshs      x,y,u
                    tfr       u,x
                    ldu       PD.BUF,y
                    stx       F.Regs,u
                    lbsr      Writable
                    bcs       setreturn@
                    ldx       F.Regs,u
                    ldb       R$B,x
                    cmpb      #SS.Size
                    beq       SetSize
                    ldb       #E$UnkSvc            PCF does not promise RBF permissions/FD writes
                    coma
setreturn@          puls      x,y,u,pc
SetSize             lda       PD.MOD,y
                    bita      #WRITE.
                    lbeq      setmode@
                    lbsr      CanWriteFile
                    bcs       setreturn@
                    leax      F.Pos,u
                    lbsr      LoadVal
                    leax      F.SavedPos,u
                    lbsr      StoreVal
                    ldx       F.Regs,u
                    ldd       R$X,x
                    std       F.GapEnd,u
                    ldd       R$U,x
                    std       F.GapEnd+2,u
                    leax      F.GapEnd,u
                    lbsr      LoadVal
                    leax      F.Size,u
                    lbsr      CompareVal
                    lbeq      sizerestore@
                    blo       sizeshrink@
                    lbsr      FillGap
                    lbra      sizerestore@
sizeshrink@         lbsr      ValidateChain
                    lbcs      sizerestore@
                    leax      F.GapEnd,u
                    lbsr      LoadVal
                    ldd       F.Val,u
                    bne       sizepartial@
                    ldd       F.Val+2,u
                    bne       sizepartial@
                    leax      F.Start,u
                    lbsr      LoadVal
                    leax      F.Saved,u
                    lbsr      StoreVal
                    clra
                    clrb
                    std       F.Start,u
                    std       F.Start+2,u
                    bra       sizepublish@
sizepartial@        lbsr      DecVal
                    leax      F.Offset,u
                    lbsr      StoreVal
                    lbsr      Locate
                    bcs       sizerestore@
                    leax      F.Walk,u
                    lbsr      LoadVal
                    leax      F.New,u
                    lbsr      StoreVal
                    leax      F.Cluster,u
                    lbsr      StoreVal
                    lbsr      NextCluster
                    bcc       sizetail@
                    cmpb      #E$EOF
                    bne       sizebad@
                    clra
                    clrb
                    std       F.Val,u
                    std       F.Val+2,u
sizetail@           leax      F.Saved,u
                    lbsr      StoreVal
sizepublish@        leax      F.GapEnd,u
                    lbsr      LoadVal
                    leax      F.Size,u
                    lbsr      StoreVal
                    lbsr      UpdateEntry
                    bcs       sizerestore@
                    ldd       F.Start,u
                    bne       sizedetach@
                    ldd       F.Start+2,u
                    beq       sizefree@
sizedetach@         leax      F.New,u
                    lbsr      LoadVal
                    leax      F.Cluster,u
                    lbsr      StoreVal
                    ldd       #$0FFF
                    std       F.Value,u
                    ldd       #$FFFF
                    std       F.Value+2,u
                    lbsr      SetFat
                    bcs       sizerestore@
sizefree@           lbsr      FreeChain
sizerestore@        pshs      b,cc
                    leax      F.SavedPos,u
                    lbsr      LoadVal
                    leax      F.Pos,u
                    lbsr      StoreVal
                    clr       F.WalkValid,u
                    puls      b,cc
                    lbcs      setreturn@
                    lbsr      Flush
                    lbra      setreturn@
sizebad@            coma
                    bra       sizerestore@
setmode@            ldb       #E$BMode
                    coma
                    lbra      setreturn@

* Determine WriteLn's actual transfer length before modifying the data cache.
WriteLineCount      tst       F.Line,u
                    beq       linecountok@
                    pshs      x,y
                    ldx       F.Dest,u
                    ldd       F.Move,u
                    pshs      d
linecountloop@      equ       *
                    ifgt      Level-1
                    ldy       <D.Proc
                    ldb       P$Task,y
                    os9       F$LDABX
                    else
                    lda       ,x
                    endc
                    leax      1,x
                    cmpa      #C$CR
                    beq       linecountfound@
                    ldd       ,s
                    subd      #1
                    std       ,s
                    bne       linecountloop@
                    leas      2,s
                    puls      x,y
                    bra       linecountok@
linecountfound@     ldd       F.Move,u
                    subd      ,s++
                    addd      #1
                    std       F.Move,u
                    inc       F.Stop,u
                    puls      x,y
linecountok@        clrb
                    rts


* I$MakDir has no persistent open path. Reuse create resolution with a private
* kind flag, then release the temporary directory path on success or failure.
MkDirImpl           pshs      x,y,u
                    lda       PD.MOD,y
                    pshs      a
                    lda       #DIR.+READ.
                    sta       PD.MOD,y
                    lda       #2
                    lbsr      OpenBegin
                    bcs       mkdirreturn@
                    lbsr      FreePath
mkdirreturn@        puls      a
                    sta       PD.MOD,y
                    puls      x,y,u,pc

* Initialize the child fully before publishing its parent's entry. F.Start is
* still the parent cluster. Return X pointing at the reloaded parent slot.
NewDirectory        lbsr      Allocate
                    lbcs      newdirret@
                    leax      F.New,u
                    lbsr      LoadVal
                    leax      F.Child,u
                    lbsr      StoreVal
                    lbsr      ClusterBase
                    lbcs      newdirundo@
                    lbsr      ReadData
                    lbcs      newdirundo@
                    leax      F.Child,u
                    lbsr      LoadVal
                    leax      F.Data,u
                    lbsr      DotEntry
                    leax      F.Start,u
                    lbsr      LoadVal
                    leax      F.Root,u
                    lbsr      CompareVal
                    bne       newdirparent@
* FAT32 encodes a root parent as cluster zero in '..'.
                    clra
                    clrb
                    std       F.Val,u
                    std       F.Val+2,u
newdirparent@       leax      F.Data+32,u
                    lbsr      DotEntry
                    lda       #'.
                    sta       F.Data+33,u
                    lbsr      WriteData
                    bcs       newdirundo@
                    leax      F.Child,u
                    lbsr      LoadVal
                    leax      F.Entry,u
                    bsr       EntryCluster
                    leax      F.DirLBA,u
                    lbsr      LoadVal
                    lbsr      ReadData
                    bcs       newdirundo@
                    ldd       F.DirOff,u
                    leax      d,x
                    clrb
newdirret@          rts
* The child is not reachable yet. Best-effort reclaim preserves the original
* error; an additional media error during rollback still requires fsck.
newdirundo@         pshs      b,cc
                    leax      F.Child,u
                    lbsr      LoadVal
                    leax      F.Saved,u
                    lbsr      StoreVal
                    lbsr      FreeChain
                    lbsr      Flush
                    puls      b,cc,pc
DotEntry            pshs      x
                    lbsr      CopyEntryToDisk
                    puls      x
                    pshs      x
                    lda       #C$SPAC
                    ldb       #11
dotname@            sta       ,x+
                    decb
                    bne       dotname@
                    puls      x
                    lda       #'.
                    sta       ,x
EntryCluster        lda       F.Val+1,u
                    sta       20,x
                    lda       F.Val,u
                    sta       21,x
                    lda       F.Val+3,u
                    sta       26,x
                    lda       F.Val+2,u
                    sta       27,x
                    rts
