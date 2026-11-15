********************************************************************
* rbdesc - Device Descriptor Template
*
* Edt/Rev  YYYY/MM/DD  Modified by
* Comment
* 1/1	2013-12/10 Gene heskett
*	Raised default SAS to $10, shortens FD.SEG
*	usage for longer files
* ------------------------------------------------------------------

                    nam       rbdesc
                    ttl       Device Descriptor Template

* Disassembled 98/08/23 17:09:41 by Disasm v1.6 (C) 1988 by RML

                    ifp1
                    use       defsfile
                    endc

tylg                set       Devic+Objct
atrv                set       ReEnt+rev
rev                 set       $01

                    ifndef    DNum
DNum                set       0
                    endc
* EC-6809 SPI SD card: DNum 0 = CS0, 1 = CS1. One OS-9 sector per SD
* block, up to 65536 sectors (16 MB): 256 cylinders of 256 sectors.
Type                set       TYP.HARD
                    ifndef    Density
Density             set       0
                    endc
                    ifndef    Step
Step                set       STP.6ms
                    endc
                    ifndef    Cyls
Cyls                set       256
                    endc
                    ifndef    Sides
Sides               set       1
                    endc
Verify              set       1
                    ifndef    SectTrk
SectTrk             set       256
                    endc
                    ifndef    SectTrk0
SectTrk0            set       256
                    endc
                    ifndef    Interlv
Interlv             set       1
                    endc
                    ifndef    SAS
SAS                 set       10
                    endc

                    mod       eom,name,tylg,atrv,mgrnam,drvnam

                    fcb       DIR.!SHARE.!PEXEC.!PWRIT.!PREAD.!EXEC.!UPDAT. mode byte
                    fcb       HW.Page             extended controller address
                    fdb       $EE90               physical controller address (SPI)
                    fcb       initsize-*-1        initalization table size
                    fcb       DT.RBF              device type:0=scf,1=rbf,2=pipe,3=scf
                    fcb       DNum                drive number
                    fcb       Step                step rate
                    fcb       Type                drive device type
                    fcb       Density             media density:0=single,1=double
                    fdb       Cyls                number of cylinders (tracks)
                    fcb       Sides               number of sides
                    fcb       Verify              verify disk writes:0=on
                    fdb       SectTrk             # of sectors per track
                    fdb       SectTrk0            # of sectors per track (track 0)
                    fcb       Interlv             sector interleave factor
                    fcb       SAS                 minimum size of sector allocation
initsize            equ       *

                    ifne      DD
name                fcs       /DD/
                    else
name                fcc       /H/
                    fcb       '0+DNum+$80
                    endc
mgrnam              fcs       /RBF/
drvnam              fcs       /rbec6809spi/

                    emod
eom                 equ       *
                    end

