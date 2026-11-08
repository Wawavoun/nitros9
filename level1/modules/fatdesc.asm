* FAT32/BlkDev descriptor template. Explicit partition offset and length.
                    use       defsfile
                    use       blkdev.d
                    use       fat32.d
                    ifndef    FATBase
FATBase             equ       0
                    endc
                    ifndef    FATLength
FATLength           equ       0
                    endc
                    ifndef    FATPort
FATPort             equ       $FE90
                    endc
                    mod       eom,name,Devic+Objct,ReEnt+1,manager,driver
                    fcb       $85                 directory/read/execute only
                    fcb       0                   port extension
                    fdb       FATPort
                    fcb       1                   only DTP copied to PD.OPT
                    fcb       DT.RBF
                    fcb       BD.Version
                    fdb       backend
                    fdb       FATPort             BC.Port
                    fcb       0,0                 unit, flags
                    fdb       0,0                 RAM base, blocks (unused)
                    ifne      FATVHD
                    fdb       (FATBase+FATLength-1)/65536,(FATBase+FATLength-1)&$FFFF
                    else
                    fdb       0,0                 RAM sparse base (unused)
                    endc
                    fdb       $FFFF               failure injection disabled
                    fdb       FATBase/65536,FATBase&$FFFF
                    fdb       FATLength/65536,FATLength&$FFFF
name                fcs       /fat0/
manager             fcs       /fatfm/
driver              fcs       /BlkDev/
backend
                    ifne      FATVHD
                    fcs       /llcocovhd/
                    else
                    fcs       /llwbsdblk/
                    endc
                    emod
eom                 equ       *
                    end
