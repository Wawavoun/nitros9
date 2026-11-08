* Read-only FAT32 file manager. Include os9.d, rbf.d and blkdev.d first.
FT.Base             equ       BT.Config+BC.Len    32-bit partition base LBA
FT.Length           equ       FT.Base+4           partition blocks (zero=device remainder)
FT.End              equ       FT.Length+4
                    org       0
F.Request           rmb       BR.Len
F.Info              rmb       BI.Len
F.Regs              rmb       2
F.Base              rmb       4
F.Span              rmb       4
F.Total             rmb       4
F.FatStart          rmb       4
F.DataStart         rmb       4
F.FatSize           rmb       4
F.MaxCluster        rmb       4                   last valid data cluster
F.Root              rmb       4
F.SPC               rmb       1
F.Shift             rmb       1
F.Fats              rmb       1
F.Active            rmb       1
F.DataValid         rmb       1
F.FatValid          rmb       1
F.DataLBA           rmb       4
F.FatLBA            rmb       4
F.Start             rmb       4                   open object's first cluster
F.Size              rmb       4                   visible byte length
F.Pos               rmb       4
F.Entry             rmb       32                  original FAT directory entry
F.Val               rmb       4                   arithmetic / sector operand
F.Temp              rmb       4
F.Cluster           rmb       4                   FAT chain operand
F.Walk              rmb       4                   cached file cluster
F.Hare              rmb       4                   cycle detector; zero after reaching EOC
F.WalkIndex         rmb       4
F.WalkValid         rmb       1
F.Offset            rmb       4                   logical byte offset for Locate
F.Target            rmb       4
F.Scan              rmb       4
F.Cursor            rmb       2
F.Name              rmb       11
F.Dots              rmb       1
F.Remain            rmb       2
F.Actual            rmb       2
F.Dest              rmb       2
F.Move              rmb       2
F.Line              rmb       1
F.Stop              rmb       1
F.Cookie            rmb       4
F.Meta              rmb       32
F.Path              rmb       256
F.Record            rmb       256
                    org       $400
F.Data              rmb       512
F.Fat               rmb       512
F.Len               equ       .                   2048 bytes per system path
