* A=open path. Reject non-RBF before interpreting option/FD/directory bytes.
* Preserve A/X/Y/U; return B and carry as an OS-9 error result.
RequireRBF          pshs      a,x,y,u
                    leas      -32,s
                    leax      ,s
                    ldb       #SS.Opt
                    os9       I$GetStt
                    bcs       rbfgret@
                    lda       ,s
                    cmpa      #DT.RBF
                    beq       rbfgok@
                    leax      RBFOnlyMessage,pcr
                    ldy       #RBFOnlyLength
                    lda       #2
                    os9       I$WritLn
                    ldb       #E$BTyp
                    coma
                    bra       rbfgret@
rbfgok@             clrb
rbfgret@            leas      32,s
                    puls      a,x,y,u,pc
RBFOnlyMessage      fcc       /rbf only/
                    fcb       C$CR
RBFOnlyLength       equ       *-RBFOnlyMessage
