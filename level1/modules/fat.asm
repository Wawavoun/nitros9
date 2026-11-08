* FAT - read-only FAT32 file manager over BlkDev ABI 1.
                    use       defsfile
                    use       blkdev.d
                    use       fat32.d
                    mod       eom,name,FlMgr+Objct,ReEnt+1,start,0
name                fcs       /FAT/
                    fcb       1
start               lbra      ReadOnly
                    lbra      Open
                    lbra      ReadOnly
                    lbra      ChgDir
                    lbra      ReadOnly
                    lbra      Seek
                    lbra      Read
                    lbra      ReadOnly
                    lbra      ReadLn
                    lbra      ReadOnly
                    lbra      GetStat
                    lbra      ReadOnly
                    lbra      Close
ReadOnly            ldb       #E$WP
                    coma
                    rts
BadMedia            ldb       #E$BTyp
                    coma
                    rts
EOFError            ldb       #E$EOF
                    coma
                    rts
PathError           ldb       #E$BPNam
                    coma
                    rts
NotFound            ldb       #E$PNNF
                    coma
                    rts
AccessError         ldb       #E$FNA
                    coma
                    rts
Success             clrb
                    rts

* Internals: Y=path descriptor, U=private workspace. X/D scratch.
* Decode unaligned little-endian disk integers into the big-endian Val.
LE32                lda       3,x
                    ldb       2,x
                    std       F.Val,u
LELow               lda       1,x
                    ldb       ,x
                    std       F.Val+2,u
                    rts
LE16                clr       F.Val,u
                    clr       F.Val+1,u
                    lbra      LELow
LoadVal             ldd       ,x
                    std       F.Val,u
                    ldd       2,x
                    std       F.Val+2,u
                    rts
StoreVal            ldd       F.Val,u
                    std       ,x
                    ldd       F.Val+2,u
                    std       2,x
                    rts
AddVal              ldd       2,x
                    addd      F.Val+2,u
                    std       2,x
                    ldd       ,x
                    adcb      F.Val+1,u
                    adca      F.Val,u
                    std       ,x
                    rts
SubVal              ldd       2,x
                    subd      F.Val+2,u
                    std       2,x
                    ldd       ,x
                    sbcb      F.Val+1,u
                    sbca      F.Val,u
                    std       ,x
                    rts
CompareVal          ldd       F.Val,u
                    cmpd      ,x
                    lbne      cmpdone@
                    ldd       F.Val+2,u
                    cmpd      2,x
cmpdone@            rts
IncVal              ldd       F.Val+2,u
                    addd      #1
                    std       F.Val+2,u
                    ldd       F.Val,u
                    adcb      #0
                    adca      #0
                    std       F.Val,u
                    rts
DecVal              ldd       F.Val+2,u
                    subd      #1
                    std       F.Val+2,u
                    ldd       F.Val,u
                    sbcb      #0
                    sbca      #0
                    std       F.Val,u
                    rts
ShiftRight          lsr       F.Val,u
                    ror       F.Val+1,u
                    ror       F.Val+2,u
                    ror       F.Val+3,u
                    decb
                    lbne      ShiftRight
                    rts
ShiftLeft           lsl       F.Val+3,u
                    rol       F.Val+2,u
                    rol       F.Val+1,u
                    rol       F.Val,u
                    lbcs      shiftbad@
                    decb
                    lbne      ShiftLeft
                    clrb
                    rts
shiftbad@           lbra      BadMedia

* X=request or info, A=driver slot. No PD.BUF/RBF deblocking convention.
Driver              pshs      a,x,y,u
                    ldx       PD.DEV,y
                    ldu       V$STAT,x
                    ifgt      Level-1
                    ldx       V$DRIVEX,x
                    else
                    ldx       V$DRIV,x
                    ldd       M$Exec,x
                    leax      d,x
                    endc
                    lda       ,s
                    leax      a,x
                    pshs      x
                    ldx       3,s
                    jsr       [,s]
                    leas      2,s
                    puls      a,x,y,u,pc

* Val=absolute LBA. Separate one-sector FAT and data caches.
ReadData            tst       F.DataValid,u
                    lbeq      datafill@
                    leax      F.DataLBA,u
                    lbsr      CompareVal
                    lbeq      dataok@
datafill@           clr       F.DataValid,u
                    leax      F.Data,u
                    stx       F.Request+BR.Buffer,u
                    lbsr      ReadBlock
                    lbcs      dataret@
                    leax      F.DataLBA,u
                    lbsr      StoreVal
                    inc       F.DataValid,u
dataok@             leax      F.Data,u
                    clrb
dataret@            rts
ReadFat             tst       F.FatValid,u
                    lbeq      fatfill@
                    leax      F.FatLBA,u
                    lbsr      CompareVal
                    lbeq      fatok@
fatfill@            clr       F.FatValid,u
                    leax      F.Fat,u
                    stx       F.Request+BR.Buffer,u
                    lbsr      ReadBlock
                    lbcs      fatret@
                    leax      F.FatLBA,u
                    lbsr      StoreVal
                    inc       F.FatValid,u
fatok@              leax      F.Fat,u
                    clrb
fatret@             rts
ReadBlock           leax      F.Request+BR.LBA,u
                    lbsr      StoreVal
                    leax      F.Request,u
                    lda       #BD.Read
                    lbsr      Driver
                    lbcs      blockret@
                    ldd       F.Request+BR.Done,u
                    cmpd      #1
                    lbne      BadMedia
                    clrb
blockret@           rts

* Validate BPB and all derived geometry before any FAT/directory reads.
Mount               leax      F.Info,u
                    ldd       #BI.Len*256+BD.Version
                    std       BI.Size,x
                    lda       #BD.Info
                    lbsr      Driver
                    lbcs      mountret
                    ldd       F.Info+BI.BlockSize,u
                    cmpd      #512
                    lbne      BadMedia
                    ldd       #BR.Len*256+BD.Version
                    std       F.Request+BR.Size,u
                    lda       F.Info+BI.Unit,u
                    sta       F.Request+BR.Unit,u
                    ldd       #1
                    std       F.Request+BR.Count,u
                    ldd       #512
                    std       F.Request+BR.Bytes,u
                    ldx       PD.DEV,y
                    ldx       V$DESC,x
                    pshs      x
                    leax      FT.Base,x
                    lbsr      LoadVal
                    leax      F.Base,u
                    lbsr      StoreVal
                    leax      F.Info+BI.Last,u
                    lbsr      CompareVal
                    lbhi      mountdescbad
                    ldx       ,s
                    leax      FT.Length,x
                    lbsr      LoadVal
                    leax      F.Span,u
                    lbsr      StoreVal
                    leas      2,s
                    leax      F.Base,u
                    lbsr      LoadVal
                    lbsr      ReadData
                    lbcs      mountret
                    ldd       510,x
                    cmpd      #$55AA
                    lbne      BadMedia
                    ldd       11,x
                    cmpd      #$0002               512 little endian
                    lbne      BadMedia
                    ldd       17,x                 root entry count must be zero
                    lbne      BadMedia
                    ldd       19,x                 total16 must be zero on FAT32
                    lbne      BadMedia
                    ldd       22,x                 FAT16 size must be zero
                    lbne      BadMedia
                    ldd       42,x                 filesystem version 0
                    lbne      BadMedia
                    lda       16,x
                    lbeq      mountbad
                    cmpa      #2
                    lbhi      mountbad
                    sta       F.Fats,u
                    lda       13,x
                    lbeq      mountbad
                    lbmi      spc128@
                    lbra      spcpower@
spc128@             cmpa      #128
                    lbne      mountbad
spcpower@           sta       F.SPC,u
                    deca
                    anda      F.SPC,u
                    lbne      mountbad
                    lda       F.SPC,u
spcshift@           lsra
                    lbeq      spcdone@
                    inc       F.Shift,u
                    lbra      spcshift@
spcdone@            leax      32,x
                    lbsr      LE32
                    leax      F.Total,u
                    lbsr      StoreVal
                    ldd       F.Val,u
                    lbne      totalok@
                    ldd       F.Val+2,u
                    lbeq      mountbad
totalok@            ldd       F.Span,u
                    lbne      spancheck@
                    ldd       F.Span+2,u
                    lbeq      endcheck@
spancheck@          leax      F.Span,u
                    lbsr      CompareVal
                    lbhi      mountbad
endcheck@           lbsr      DecVal
                    leax      F.Base,u
                    lbsr      AddBase
                    lbcs      mountret
                    leax      F.Info+BI.Last,u
                    lbsr      CompareVal
                    lbhi      mountbad
                    leax      F.Data+14,u
                    lbsr      LE16
                    ldd       F.Val+2,u
                    lbeq      mountbad
                    leax      F.Temp,u
                    lbsr      StoreVal            relative data start begins at reserved count
                    leax      F.Base,u
                    lbsr      AddBase
                    lbcs      mountret
                    leax      F.FatStart,u
                    lbsr      StoreVal
                    leax      F.Data+36,u
                    lbsr      LE32
                    ldd       F.Val,u
                    lbne      fatszok@
                    ldd       F.Val+2,u
                    lbeq      mountbad
fatszok@            leax      F.FatSize,u
                    lbsr      StoreVal
                    lda       F.Fats,u
                    pshs      a
fatmultiply@        leax      F.Temp,u
                    lbsr      AddVal
                    lbcs      mountbadpop
                    dec       ,s
                    lbne      fatmultiply@
                    leas      1,s
                    leax      F.Temp,u
                    lbsr      LoadVal
                    leax      F.Total,u
                    lbsr      CompareVal
                    lbhs      mountbad
                    leax      F.Base,u
                    lbsr      AddBase
                    lbcs      mountret
                    leax      F.DataStart,u
                    lbsr      StoreVal
                    leax      F.Total,u
                    lbsr      LoadVal
                    leax      F.MaxCluster,u
                    lbsr      StoreVal
                    leax      F.Temp,u
                    lbsr      LoadVal
                    leax      F.MaxCluster,u
                    lbsr      SubVal
                    lbsr      LoadVal
                    ldb       F.Shift,u
                    lbeq      clusters@
                    lbsr      ShiftRight
clusters@           ldd       F.Val,u
                    lbne      minimum@
                    ldd       F.Val+2,u
                    cmpd      #65525               discriminate FAT32 by cluster count
                    lblo      mountbad
minimum@            lbsr      IncVal
                    leax      F.MaxCluster,u
                    lbsr      StoreVal
                    lbsr      ValidCluster
                    lbcs      mountret
* FAT must contain entries zero through MaxCluster inclusive.
                    lbsr      IncVal
                    ldd       F.Val+2,u
                    addd      #127
                    std       F.Val+2,u
                    ldd       F.Val,u
                    adcb      #0
                    adca      #0
                    std       F.Val,u
                    ldb       #7
                    lbsr      ShiftRight
                    leax      F.FatSize,u
                    lbsr      CompareVal
                    lbhi      mountbad
* FAT32 ExtFlags: mirroring enabled chooses FAT 0; otherwise select active FAT.
                    lda       F.Data+40,u
                    bita      #$80
                    lbeq      root@
                    anda      #15
                    cmpa      F.Fats,u
                    lbhs      mountbad
                    sta       F.Active,u
                    tsta
                    lbeq      root@
                    leax      F.FatSize,u
                    lbsr      LoadVal
                    leax      F.FatStart,u
                    lbsr      AddVal
                    lbcs      mountbad
root@               leax      F.Data+44,u
                    lbsr      LE32
                    lbsr      ValidCluster
                    lbcs      mountret
                    leax      F.Root,u
                    lbsr      StoreVal
                    clrb
mountret            rts
mountdescbad        leas      1,s
mountbadpop         leas      1,s
mountbad            lbra      BadMedia

* Val += 32-bit value at X, with checked overflow.
AddBase             ldd       F.Val+2,u
                    addd      2,x
                    std       F.Val+2,u
                    ldd       F.Val,u
                    adcb      1,x
                    adca      ,x
                    std       F.Val,u
                    lbcs      BadMedia
                    clrb
                    rts
ValidCluster        ldd       F.Val,u
                    cmpd      #$0FFF
                    lbhi      invalid@
                    lblo      lowcheck@
                    ldd       F.Val+2,u
                    cmpd      #$FFF0
                    lbhs      invalid@
lowcheck@           ldd       F.Val,u
                    lbne      maxcheck@
                    ldd       F.Val+2,u
                    cmpd      #2
                    lblo      invalid@
maxcheck@           leax      F.MaxCluster,u
                    lbsr      CompareVal
                    lbhi      invalid@
                    clrb
                    rts
invalid@            lbra      BadMedia

* Cluster in/out, EOF only for FAT EOC markers; free/bad/reserved links fail.
NextCluster         leax      F.Cluster,u
                    lbsr      LoadVal
                    lbsr      ValidCluster
                    lbcs      nextret@
                    ldb       #7
                    lbsr      ShiftRight
                    leax      F.FatStart,u
                    lbsr      AddBase
                    lbcs      nextret@
                    lbsr      ReadFat
                    lbcs      nextret@
                    ldb       F.Cluster+3,u
                    andb      #127
                    clra
                    lslb
                    rola
                    lslb
                    rola
                    leax      d,x
                    lbsr      LE32
                    lda       F.Val,u
                    anda      #15
                    sta       F.Val,u
                    ldd       F.Val,u
                    cmpd      #$0FFF
                    lbne      linkvalid@
                    ldd       F.Val+2,u
                    cmpd      #$FFF8
                    lbhs      EOFError
linkvalid@          lbsr      ValidCluster
                    lbcs      nextret@
                    leax      F.Cluster,u
                    lbsr      StoreVal
                    clrb
nextret@            rts

* File/dir chain cursor with Floyd cycle detection; no cluster-number truncation.
ResetWalk           leax      F.Start,u
                    lbsr      LoadVal
                    lbsr      ValidCluster
                    lbcs      resetret@
                    leax      F.Walk,u
                    lbsr      StoreVal
                    leax      F.Hare,u
                    lbsr      StoreVal
                    clra
                    clrb
                    std       F.WalkIndex,u
                    std       F.WalkIndex+2,u
                    lda       #1
                    sta       F.WalkValid,u
resetret@           rts
Advance             leax      F.Walk,u
                    lbsr      LoadVal
                    leax      F.Cluster,u
                    lbsr      StoreVal
                    lbsr      NextCluster
                    lbcs      advret@
                    leax      F.Walk,u
                    lbsr      StoreVal
                    leax      F.WalkIndex,u
                    lbsr      LoadVal
                    lbsr      IncVal
                    leax      F.WalkIndex,u
                    lbsr      StoreVal
                    ldd       F.Hare,u
                    lbne      harego@
                    ldd       F.Hare+2,u
                    lbeq      advok@
harego@             leax      F.Hare,u
                    lbsr      LoadVal
                    leax      F.Cluster,u
                    lbsr      StoreVal
                    ldb       #2
                    pshs      b
harestep@           lbsr      NextCluster
                    lbcs      hareend@
                    dec       ,s
                    lbne      harestep@
                    leas      1,s
                    leax      F.Hare,u
                    lbsr      StoreVal
                    leax      F.Walk,u
                    lbsr      CompareVal
                    lbeq      BadMedia
advok@              clrb
advret@             rts
hareend@            leas      1,s
                    cmpb      #E$EOF
                    lbne      advfail@
                    clra
                    clrb
                    std       F.Hare,u
                    std       F.Hare+2,u
                    rts
advfail@            coma
                    rts

* Offset is logical byte offset within Start's chain. Return X=byte in data.
Locate              leax      F.Offset,u
                    lbsr      LoadVal
                    ldb       F.Shift,u
                    addb      #9
                    lbsr      ShiftRight
                    leax      F.Target,u
                    lbsr      StoreVal
                    tst       F.WalkValid,u
                    lbeq      restart@
                    leax      F.WalkIndex,u
                    lbsr      CompareVal
                    lbhs      locatewalk@
restart@            lbsr      ResetWalk
                    lbcs      locret@
locatewalk@         leax      F.Target,u
                    lbsr      LoadVal
                    leax      F.WalkIndex,u
                    lbsr      CompareVal
                    lbeq      locsector@
                    lbsr      Advance
                    lbcs      locret@
                    lbra      locatewalk@
locsector@          leax      F.Walk,u
                    lbsr      LoadVal
                    lbsr      DecVal
                    lbsr      DecVal
                    ldb       F.Shift,u
                    lbeq      locbase@
                    lbsr      ShiftLeft
                    lbcs      locret@
locbase@            leax      F.DataStart,u
                    lbsr      AddBase
                    lbcs      locret@
                    leax      F.Temp,u
                    lbsr      StoreVal
                    leax      F.Offset,u
                    lbsr      LoadVal
                    ldb       #9
                    lbsr      ShiftRight
                    lda       F.SPC,u
                    deca
                    anda      F.Val+3,u
                    clrb
                    stb       F.Val,u
                    stb       F.Val+1,u
                    stb       F.Val+2,u
                    sta       F.Val+3,u
                    leax      F.Temp,u
                    lbsr      AddBase
                    lbcs      locret@
                    lbsr      ReadData
                    lbcs      locret@
                    ldd       F.Offset+2,u
                    anda      #1
                    leax      d,x
                    clrb
locret@             rts

Open                pshs      x,y,u
                    clr       PD.BUF,y
                    clr       PD.BUF+1,y
                    lda       PD.MOD,y
                    bita      #WRITE.
                    lbne      openwp
                    bita      #READ.+EXEC.
                    lbeq      openaccess
                    ldd       #F.Len
                    os9       F$SRqMem
                    lbcs      openreturn
                    stu       PD.BUF,y
                    tfr       u,x
                    ldd       #F.Len
openzero@           clr       ,x+
                    subd      #1
                    lbne      openzero@
                    ldx       4,s
                    stx       F.Regs,u
                    lbsr      Mount
                    lbcs      openfailed
                    lbsr      CopyPath
                    lbcs      openfailed
                    lbsr      Resolve
                    lbcs      openfailed
                    lda       F.Entry+11,u
                    anda      #$10
                    lbeq      openfile@
                    lda       PD.MOD,y
                    bita      #DIR.
                    lbeq      openaccessfree
                    lbsr      DirectorySize
                    lbcs      openfailed
                    lbra      openok@
openfile@           lda       PD.MOD,y
                    bita      #DIR.
                    lbne      openaccessfree
                    ldd       F.Size,u
                    lbne      openvalid@
                    ldd       F.Size+2,u
                    lbeq      openok@
openvalid@          leax      F.Start,u
                    lbsr      LoadVal
                    lbsr      ValidCluster
                    lbcs      openfailed
openok@             lda       #READ.+EXEC.+PREAD.+PEXEC.
                    ldb       F.Entry+11,u
                    bitb      #$10
                    lbeq      openattr@
                    ora       #DIR.
openattr@           sta       PD.ATT,y
                    clr       F.WalkValid,u
                    clrb
openreturn          puls      x,y,u,pc
openwp              ldb       #E$WP
                    coma
                    lbra      openreturn
openaccess          ldb       #E$FNA
                    coma
                    lbra      openreturn
openaccessfree      ldb       #E$FNA
                    coma
openfailed          pshs      b
                    lbsr      FreePath
                    puls      b
                    coma
                    lbra      openreturn

* Copy caller path to private memory. OS-9 high-bit terminators are accepted.
CopyPath            pshs      y
                    ldx       F.Regs,u
                    ldx       R$X,x
                    leay      F.Path,u
                    pshs      y
copychar@           pshs      y
                    ifgt      Level-1
                    ldy       <D.Proc
                    ldb       P$Task,y
                    os9       F$LDABX
                    else
                    lda       ,x
                    endc
                    puls      y
                    tsta
                    lbeq      pathdone@
                    cmpa      #C$CR
                    lbeq      pathdone@
                    cmpa      #C$SPAC
                    lbeq      pathdone@
                    cmpa      #',
                    lbeq      pathdone@
                    pshs      a
                    anda      #$7F
                    sta       ,y+
                    leax      1,x
                    tfr       y,d
                    subd      1,s                compare copied length (saved char is atop pointer)
                    cmpd      #255
                    lbhi      pathtoolong@
                    puls      a
                    tsta
                    lbpl      copychar@
pathdone@           clr       ,y
* Return the next argument, skipping OS-9 command-line separators.
pathskip@           equ       *
                    ifgt      Level-1
                    ldy       <D.Proc
                    ldb       P$Task,y
                    os9       F$LDABX
                    else
                    lda       ,x
                    endc
                    cmpa      #C$SPAC
                    lbeq      pathadvance@
                    cmpa      #',
                    lbne      pathreturn@
pathadvance@        leax      1,x
                    lbra      pathskip@
pathreturn@         leas      2,s
                    ldy       F.Regs,u
                    stx       R$X,y
                    clrb
                    puls      y,pc
pathtoolong@        leas      3,s
                    puls      y
                    lbra      PathError

* Starting directory: absolute paths skip the device name; relative paths
* use all four file-manager bytes in P$DIO (CWD) or P$DIO+6 (CXD).
Resolve             leax      F.Root,u
                    lbsr      LoadVal
                    leax      F.Start,u
                    lbsr      StoreVal
                    lda       #$10
                    sta       F.Entry+11,u
                    leax      F.Path,u
                    lda       ,x
                    lbeq      resolvebad@
                    cmpa      #'/
                    lbeq      skipdevice@
                    pshs      x
                    ldx       <D.Proc
                    leax      P$DIO,x
                    lda       PD.MOD,y
                    bita      #EXEC.
                    lbeq      cwd@
                    leax      6,x
cwd@                ldd       ,x
                    cmpd      PD.DEV,y
                    lbne      cwdroot@
                    leax      2,x
                    lbsr      LoadVal
                    ldd       F.Val,u
                    lbne      cwdvalid@
                    ldd       F.Val+2,u
                    lbeq      cwdroot@
cwdvalid@           lbsr      ValidCluster
                    lbcs      cwderror@
                    leax      F.Start,u
                    lbsr      StoreVal
cwdroot@            puls      x
                    lbra      component@
cwderror@           leas      2,s
                    rts
skipdevice@         leax      1,x
skipdevchar@        lda       ,x+
                    lbeq      resolveroot@
                    cmpa      #'/
                    lbne      skipdevchar@
component@          lda       ,x
                    lbeq      resolveroot@
                    cmpa      #'/
                    lbne      parsename@
                    leax      1,x
                    lbra      component@
parsename@          stx       F.Cursor,u
                    lbsr      ParseName
                    lbcs      resolveret@
                    tst       F.Dots,u
                    lbeq      ordinary@
                    dec       F.Dots,u
                    lbeq      aftercomponent@
parentloop@         leax      F.Start,u
                    lbsr      LoadVal
                    leax      F.Root,u
                    lbsr      CompareVal
                    lbeq      parentdone@
                    lbsr      Lookup
                    lbcs      resolveret@
parentdone@         dec       F.Dots,u
                    lbne      parentloop@
                    lbra      aftercomponent@
ordinary@           lbsr      Lookup
                    lbcs      resolveret@
aftercomponent@     ldx       F.Cursor,u
                    lda       ,x
                    lbeq      resolved@
                    lda       F.Entry+11,u
                    bita      #$10
                    lbeq      NotFound
                    lbra      component@
resolveroot@        clrb
                    rts
resolved@           clrb
resolveret@         rts
resolvebad@         lbra      PathError

* ASCII 8.3 aliases, case insensitive. Dot-only names use OS-9 ascent rules.
ParseName           pshs      y
                    leay      F.Name,u
                    ldb       #11
                    lda       #C$SPAC
padname@            sta       ,y+
                    decb
                    lbne      padname@
                    clr       F.Dots,u
                    ldx       F.Cursor,u
dotcount@           lda       ,x+
                    cmpa      #'.
                    lbne      dotend@
                    inc       F.Dots,u
                    lbra      dotcount@
dotend@             tsta
                    lbeq      alldots@
                    cmpa      #'/
                    lbeq      alldots@
normalname@         clr       F.Dots,u
                    ldx       F.Cursor,u
                    leay      F.Name,u
                    ldb       #8
basename@           lda       ,x+
                    lbeq      nameterm@
                    cmpa      #'/
                    lbeq      nameterm@
                    cmpa      #'.
                    lbeq      extension@
                    lbsr      NameChar
                    lbcs      namebad@
                    tstb
                    lbeq      namebad@
                    sta       ,y+
                    decb
                    lbra      basename@
extension@          cmpb      #8
                    lbeq      namebad@
                    leay      F.Name+8,u
                    ldb       #3
extchar@            lda       ,x+
                    lbeq      nameterm@
                    cmpa      #'/
                    lbeq      nameterm@
                    lbsr      NameChar
                    lbcs      namebad@
                    tstb
                    lbeq      namebad@
                    sta       ,y+
                    decb
                    lbra      extchar@
alldots@            tst       F.Dots,u
                    lbeq      normalname@
                    lda       #'.
                    sta       F.Name,u
                    sta       F.Name+1,u
nameterm@           leax      -1,x
                    stx       F.Cursor,u
                    clrb
                    puls      y,pc
namebad@            puls      y
                    lbra      PathError
NameChar            cmpa      #'a
                    lblo      charcheck@
                    cmpa      #'z
                    lbhi      charcheck@
                    suba      #32
charcheck@          cmpa      #33
                    lblo      charbad@
                    cmpa      #127
                    lbhs      charbad@
                    pshs      x
                    leax      IllegalChars,pcr
charloop@           tst       ,x
                    lbeq      charok@
                    cmpa      ,x+
                    lbne      charloop@
                    puls      x
charbad@            coma
                    rts
charok@             puls      x
                    andcc     #$FE
                    rts
IllegalChars        fcc       /"*+,.:;<=>?[\]|/
                    fcb       0

* Scan one directory for Name; all addresses and offsets are 32 bits.
Lookup              clr       F.WalkValid,u
                    clra
                    clrb
                    std       F.Scan,u
                    std       F.Scan+2,u
lookloop@           leax      F.Scan,u
                    lbsr      LoadVal
                    leax      F.Offset,u
                    lbsr      StoreVal
                    lbsr      Locate
                    lbcs      lookerror@
                    lda       ,x
                    lbeq      lookmissing@
                    cmpa      #$E5
                    lbeq      looknext@
                    lda       11,x
                    bita      #8                  skips volume labels and LFN slots
                    lbne      looknext@
                    pshs      x,y
                    leay      F.Name,u
                    ldb       #11
lookcompare@        lda       ,x+
                    cmpa      ,y+
                    lbne      looknomatch@
                    decb
                    lbne      lookcompare@
                    puls      x,y
                    lbsr      AdoptEntry
                    rts
looknomatch@        puls      x,y
looknext@           lbsr      ScanNext
                    lbcc      lookloop@
                    rts
lookerror@          cmpb      #E$EOF
                    lbne      lookio@
lookmissing@        lbra      NotFound
lookio@             coma
                    rts
ScanNext            leax      F.Scan,u
                    lbsr      LoadVal
                    ldd       F.Val+2,u
                    addd      #32
                    std       F.Val+2,u
                    ldd       F.Val,u
                    adcb      #0
                    adca      #0
                    std       F.Val,u
                    lbcs      BadMedia
                    leax      F.Scan,u
                    lbsr      StoreVal
                    clrb
                    rts
AdoptEntry          pshs      y
                    leay      F.Entry,u
                    ldb       #32
adoptcopy@          lda       ,x+
                    sta       ,y+
                    decb
                    lbne      adoptcopy@
                    puls      y
                    leax      F.Entry+28,u
                    lbsr      LE32
                    leax      F.Size,u
                    lbsr      StoreVal
                    lda       F.Entry+21,u
                    anda      #15
                    ldb       F.Entry+20,u
                    std       F.Val,u
                    lda       F.Entry+27,u
                    ldb       F.Entry+26,u
                    std       F.Val+2,u
                    lda       F.Entry+11,u
                    bita      #$10
                    lbeq      adoptstart@
                    ldd       F.Val,u
                    lbne      adoptvalid@
                    ldd       F.Val+2,u
                    lbne      adoptvalid@
* Only the actual '..' entry is allowed to encode the root as cluster zero.
                    ldd       F.Entry,u
                    cmpd      #$2E2E
                    lbne      BadMedia
                    leax      F.Root,u
                    lbsr      LoadVal
adoptvalid@         lbsr      ValidCluster
                    lbcs      adoptret@
adoptstart@         leax      F.Start,u
                    lbsr      StoreVal
                    clr       F.WalkValid,u
                    clrb
adoptret@           rts

* Directory view contains two synthetic dot records followed by physical slots.
* Deleted/LFN/volume/disk dot slots become zero records, preserving cookie offsets.
DirectorySize       clr       F.WalkValid,u
                    clra
                    clrb
                    std       F.Scan,u
                    std       F.Scan+2,u
dirsizewalk@        leax      F.Scan,u
                    lbsr      LoadVal
                    leax      F.Offset,u
                    lbsr      StoreVal
                    lbsr      Locate
                    lbcs      dirsizeend@
                    tst       ,x
                    lbeq      dirsizefound@
                    lbsr      ScanNext
                    lbcs      dirsizeret@
                    lbra      dirsizewalk@
dirsizeend@         cmpb      #E$EOF
                    lbne      dirsizeerror@
dirsizefound@       leax      F.Scan,u
                    lbsr      LoadVal
                    ldd       F.Val+2,u
                    addd      #64
                    std       F.Val+2,u
                    ldd       F.Val,u
                    adcb      #0
                    adca      #0
                    std       F.Val,u
                    lbcs      BadMedia
                    leax      F.Size,u
                    lbsr      StoreVal
                    clrb
dirsizeret@         rts
dirsizeerror@       coma
                    rts

ChgDir              pshs      x,y,u
                    lda       PD.MOD,y
                    ora       #DIR.
                    sta       PD.MOD,y
                    lbsr      Open
                    lbcs      chgret@
                    ldu       PD.BUF,y
                    ldx       <D.Proc
                    lda       PD.MOD,y
                    bita      #READ.
                    lbeq      chgexec@
                    ldd       F.Start,u
                    std       P$DIO+2,x
                    ldd       F.Start+2,u
                    std       P$DIO+4,x
chgexec@            lda       PD.MOD,y
                    bita      #EXEC.
                    lbeq      chgfree@
                    ldd       F.Start,u
                    std       P$DIO+8,x
                    ldd       F.Start+2,u
                    std       P$DIO+10,x
chgfree@            lbsr      FreePath
chgret@             puls      x,y,u,pc
Close               tst       PD.CNT,y
                    lbne      closeshared@
                    lbra      FreePath
closeshared@        clrb
                    rts
FreePath            pshs      x,y,u
                    ldu       PD.BUF,y
                    lbeq      freeok@
                    clr       PD.BUF,y
                    clr       PD.BUF+1,y
                    ldd       #F.Len
                    os9       F$SRtMem
                    puls      x,y,u,pc
freeok@             clrb
                    puls      x,y,u,pc

Seek                pshs      x,y,u
                    tfr       u,x
                    ldu       PD.BUF,y
                    ldd       R$X,x
                    std       F.Pos,u
                    ldd       R$U,x
                    std       F.Pos+2,u
                    clrb
                    puls      x,y,u,pc

Read                clra
                    lbra      ReadCommon
ReadLn              lda       #1
ReadCommon          pshs      x,y,u
                    tfr       u,x
                    ldu       PD.BUF,y
                    stx       F.Regs,u
                    sta       F.Line,u
                    clr       F.Stop,u
                    ldd       R$Y,x
                    std       F.Remain,u
                    clra
                    clrb
                    std       R$Y,x
                    std       F.Actual,u
                    ldd       R$X,x
                    std       F.Dest,u
readloop@           ldd       F.Remain,u
                    lbeq      readsuccess@
                    leax      F.Pos,u
                    lbsr      LoadVal
                    leax      F.Size,u
                    lbsr      CompareVal
                    lbhs      readeof@
                    lda       F.Entry+11,u
                    bita      #$10
                    lbne      readdirectory@
                    leax      F.Offset,u
                    lbsr      StoreVal
                    lbsr      Locate
                    lbcs      readchainerror@
                    ldd       F.Pos+2,u
                    anda      #1
                    pshs      d
                    ldd       #512
                    subd      ,s++
                    lbra      readlimit@
readdirectory@      lbsr      DirectoryRecord
                    lbcs      readexit@
                    ldb       F.Pos+3,u
                    andb      #31
                    abx
                    negb
                    addb      #32
                    clra
readlimit@          cmpd      F.Remain,u
                    lbls      readfilesize@
                    ldd       F.Remain,u
readfilesize@       std       F.Move,u
                    pshs      x
                    leax      F.Size,u
                    lbsr      LoadVal
                    leax      F.Temp,u
                    lbsr      StoreVal
                    leax      F.Pos,u
                    lbsr      LoadVal
                    leax      F.Temp,u
                    lbsr      SubVal
                    ldd       F.Temp,u
                    lbne      readscan@
                    ldd       F.Temp+2,u
                    cmpd      F.Move,u
                    lbhs      readscan@
                    std       F.Move,u
readscan@           puls      x
                    tst       F.Line,u
                    lbeq      readmove@
                    pshs      x
                    ldd       F.Move,u
                    pshs      d
linescan@           lda       ,x+
                    cmpa      #C$CR
                    lbeq      linefound@
                    ldd       ,s
                    subd      #1
                    std       ,s
                    lbne      linescan@
                    lbra      lineend@
linefound@          ldd       F.Move,u
                    subd      ,s
                    addd      #1
                    std       F.Move,u
                    inc       F.Stop,u
lineend@            leas      2,s
                    puls      x
readmove@           lbsr      MoveOut
                    lbcs      readexit@
                    ldd       F.Move,u
                    addd      F.Actual,u
                    std       F.Actual,u
                    ldd       F.Remain,u
                    subd      F.Move,u
                    std       F.Remain,u
                    ldd       F.Dest,u
                    addd      F.Move,u
                    std       F.Dest,u
                    ldd       F.Pos+2,u
                    addd      F.Move,u
                    std       F.Pos+2,u
                    ldd       F.Pos,u
                    adcb      #0
                    adca      #0
                    std       F.Pos,u
                    tst       F.Stop,u
                    lbeq      readloop@
readsuccess@        clrb
readexit@           pshs      b,cc
                    ldx       F.Regs,u
                    ldd       F.Actual,u
                    std       R$Y,x
                    puls      b,cc
                    puls      x,y,u,pc
readeof@            ldd       F.Actual,u
                    lbne      readsuccess@
                    ldb       #E$EOF
                    coma
                    lbra      readexit@
readchainerror@     cmpb      #E$EOF
                    lbne      readerror@
                    ldb       #E$BTyp              chain ended before file size
readerror@          coma
                    lbra      readexit@

* X=system source, F.Dest=caller destination, F.Move=count.
MoveOut             pshs      x,y,u
                    ldy       F.Move,u
                    ifgt      Level-1
                    pshs      y
                    ldy       <D.Proc
                    ldb       P$Task,y
                    lda       <D.SysTsk
                    puls      y
                    ldu       F.Dest,u
                    os9       F$Move
                    else
                    ldu       F.Dest,u
movebyte@           cmpy      #0
                    lbeq      movedone@
                    lda       ,x+
                    sta       ,u+
                    leay      -1,y
                    lbra      movebyte@
movedone@           clrb
                    endc
                    puls      x,y,u,pc

* Build a stable OS-9 directory record at Pos. Cookie = physical slot + 1,
* scoped to this open directory, not a truncated FAT cluster or disk address.
DirectoryRecord     leax      F.Record,u
                    ldb       #32
recordzero@         clr       ,x+
                    decb
                    lbne      recordzero@
                    leax      F.Pos,u
                    lbsr      LoadVal
                    ldd       F.Val,u
                    lbne      recordraw@
                    ldd       F.Val+2,u
                    cmpd      #64
                    lbhs      recordraw@
                    leax      F.Record,u
                    cmpd      #32
                    lbhs      recorddot@
                    lda       #'.
                    sta       ,x
                    lda       #'.+$80
                    sta       1,x
                    clrb
                    rts
recorddot@          lda       #'.+$80
                    sta       ,x
                    clrb
                    rts
recordraw@          ldd       F.Val+2,u
                    subd      #64
                    std       F.Val+2,u
                    ldd       F.Val,u
                    sbcb      #0
                    sbca      #0
                    std       F.Val,u
                    lda       F.Val+3,u
                    anda      #$E0
                    sta       F.Val+3,u
                    leax      F.Offset,u
                    lbsr      StoreVal
                    ldb       #5
                    lbsr      ShiftRight
                    lbsr      IncVal
                    tst       F.Val,u
                    lbne      BadMedia             cookie must fit SS.FDInf's 24 bits
                    leax      F.Cookie,u
                    lbsr      StoreVal
                    lbsr      Locate
                    lbcs      recordret@
                    lda       ,x
                    lbeq      recordblank@
                    cmpa      #$E5
                    lbeq      recordblank@
                    cmpa      #'.
                    lbeq      recordblank@
                    lda       11,x
                    bita      #8
                    lbne      recordblank@
                    pshs      y
                    leay      F.Record,u
                    ldb       #8
recordbase@         lda       ,x+
                    cmpa      #C$SPAC
                    lbeq      recordbaseskip@
                    sta       ,y+
recordbaseskip@     decb
                    lbne      recordbase@
                    lda       ,x
                    cmpa      #C$SPAC
                    lbeq      recordnameend@
                    lda       #'.
                    sta       ,y+
                    ldb       #3
recordext@          lda       ,x+
                    cmpa      #C$SPAC
                    lbeq      recordextskip@
                    sta       ,y+
recordextskip@      decb
                    lbne      recordext@
recordnameend@      lda       -1,y
                    ora       #$80
                    sta       -1,y
                    puls      y
                    lda       F.Cookie+1,u
                    sta       F.Record+29,u
                    ldd       F.Cookie+2,u
                    std       F.Record+30,u
recordblank@        leax      F.Record,u
                    clrb
recordret@          rts

GetStat             pshs      x,y,u
                    tfr       u,x
                    ldu       PD.BUF,y
                    stx       F.Regs,u
                    ldb       R$B,x
                    cmpb      #SS.Opt
                    lbeq      statok
                    cmpb      #SS.DevNm
                    lbeq      statok                IOMan copies these common results
                    cmpb      #SS.Size
                    lbeq      statsize
                    cmpb      #SS.Pos
                    lbeq      statpos
                    cmpb      #SS.EOF
                    lbeq      stateof
                    cmpb      #SS.Ready
                    lbeq      statready
                    cmpb      #SS.FD
                    lbeq      statfd
                    cmpb      #SS.FDInf
                    lbeq      statfdinf
                    ldb       #E$UnkSvc
                    coma
statreturn          puls      x,y,u,pc
statok              clrb
                    lbra      statreturn
statsize            ldd       F.Size,u
                    std       R$X,x
                    ldd       F.Size+2,u
                    std       R$U,x
                    lbra      statok
statpos             ldd       F.Pos,u
                    std       R$X,x
                    ldd       F.Pos+2,u
                    std       R$U,x
                    lbra      statok
stateof             leax      F.Pos,u
                    lbsr      LoadVal
                    leax      F.Size,u
                    lbsr      CompareVal
                    lblo      statok
                    ldb       #E$EOF
                    coma
                    lbra      statreturn
statready           clr       R$B,x
                    lbra      statok
statfd              ldd       R$Y,x
                    cmpd      #256
                    lbls      statfdlen@
                    ldd       #256
statfdlen@          std       F.Move,u
                    ldd       R$X,x
                    std       F.Dest,u
                    leax      F.Entry,u
                    lbsr      MakeFD
                    leax      F.Record+FD.SIZ,u
                    ldd       F.Size,u
                    std       ,x
                    ldd       F.Size+2,u
                    std       2,x
                    lbra      statfdcopy
statfdinf           lda       F.Entry+11,u
                    bita      #$10
                    lbeq      statbad@
                    ldb       R$Y+1,x              low Y is requested byte count
                    clra
                    std       F.Move,u
                    ldd       R$X,x
                    std       F.Dest,u
                    clr       F.Val,u
                    lda       R$Y,x                high Y is cookie high byte
                    sta       F.Val+1,u
                    ldd       R$U,x
                    std       F.Val+2,u
                    lbne      statcookie@
                    tst       F.Val+1,u
                    lbne      statcookie@
                    leax      F.Entry,u
                    lbsr      MakeFD
                    lbra      statfdcopy
statcookie@         lbsr      DecVal
                    ldb       #5
                    lbsr      ShiftLeft
                    lbcs      statreturn
                    leax      F.Offset,u
                    lbsr      StoreVal
* Cookie must refer to a physical record within this directory's visible size.
                    ldd       F.Val+2,u
                    addd      #64
                    std       F.Val+2,u
                    ldd       F.Val,u
                    adcb      #0
                    adca      #0
                    std       F.Val,u
                    lbcs      statbad@
                    leax      F.Size,u
                    lbsr      CompareVal
                    lbhs      statbad@
                    lbsr      Locate
                    lbcs      statreturn
                    lda       ,x
                    lbeq      statbad@
                    cmpa      #$E5
                    lbeq      statbad@
                    lda       11,x
                    bita      #8
                    lbne      statbad@
                    lbsr      MakeFD
statfdcopy          leax      F.Record,u
                    lbsr      MoveOut
                    lbra      statreturn
statbad@            ldb       #E$IllArg
                    coma
                    lbra      statreturn

* Translate FAT metadata to a synthetic read-only OS-9 FD (no segment list).
MakeFD              pshs      x,y
                    leay      F.Meta,u
                    ldb       #32
metacopy@           lda       ,x+
                    sta       ,y+
                    decb
                    lbne      metacopy@
                    leax      F.Record,u
                    clrb
fdzero@             clr       ,x+
                    decb
                    lbne      fdzero@
                    lda       #READ.+EXEC.+PREAD.+PEXEC.
                    ldb       F.Meta+11,u
                    bitb      #$10
                    lbeq      fdattr@
                    ora       #DIR.
fdattr@             sta       F.Record+FD.ATT,u
                    lda       #1
                    sta       F.Record+FD.LNK,u
                    leax      F.Meta+28,u
                    lbsr      LE32
                    leax      F.Record+FD.SIZ,u
                    lbsr      StoreVal
                    leax      F.Meta+24,u
                    leay      F.Record+FD.DAT,u
                    lbsr      DateToOS9
                    lda       F.Meta+23,u
                    lsra
                    lsra
                    lsra
                    sta       F.Record+FD.DAT+3,u
                    lda       F.Meta+23,u
                    anda      #7
                    lsla
                    lsla
                    lsla
                    sta       F.Record+FD.DAT+4,u
                    lda       F.Meta+22,u
                    lsra
                    lsra
                    lsra
                    lsra
                    lsra
                    ora       F.Record+FD.DAT+4,u
                    sta       F.Record+FD.DAT+4,u
                    leax      F.Meta+16,u
                    leay      F.Record+FD.Creat,u
                    lbsr      DateToOS9
                    puls      x,y,pc
DateToOS9           lda       1,x
                    lsra
                    adda      #80
                    sta       ,y
                    lda       1,x
                    anda      #1
                    lsla
                    lsla
                    lsla
                    sta       1,y
                    lda       ,x
                    lsra
                    lsra
                    lsra
                    lsra
                    lsra
                    ora       1,y
                    sta       1,y
                    lda       ,x
                    anda      #31
                    sta       2,y
                    rts
                    emod
eom                 equ       *
                    end
