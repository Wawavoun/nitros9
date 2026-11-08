#!/usr/bin/env python3
"""Execute BlkDev + llcocovhd against modeled MAME VHD register/DMA behavior."""
import importlib.util
from pathlib import Path
import tempfile
spec=importlib.util.spec_from_file_location('fat_tests',Path(__file__).with_name('test-fat32.py'))
f=importlib.util.module_from_spec(spec);spec.loader.exec_module(f)
b=f.blk
b.BUF=0x5000
PORT=0xff80

class VHD:
    def __init__(self,p):
        self.p=p;self.reg=bytearray(7);self.status=255;self.reads=[];self.fail=None;self.fail_on=None
        for address in range(PORT,PORT+7):p.m.add_write_byte_callback(self.write,address)
        p.m.add_read_byte_callback(lambda *_:self.status,PORT+3)
    @staticmethod
    def data(record):return bytes((record*17+i*73)&255 for i in range(256))
    def write(self,cycles,pc,address,value):
        off=address-PORT;self.reg[off]=value
        if off!=3:return
        assert value==0,'backend issued a write/flush command'
        record=int.from_bytes(self.reg[:3],'big')
        buffer=int.from_bytes(self.reg[4:6],'big')
        assert buffer&255==0 and (buffer&8191)<=7936
        self.reads.append((self.reg[6],record,buffer))
        self.status=6 if len(self.reads)==self.fail_on else (self.fail if self.fail is not None else 0)
        if not self.status:self.p.m.load(buffer,self.data(record))

with tempfile.TemporaryDirectory(prefix='cocovhd-test-') as folder:
    tmp=Path(folder)
    for level in (1,2):
        modules=b.assemble(tmp,level)
        modules['llcocovhd']=f.assemble_source(tmp,level,f.ROOT/'level1/modules/llcocovhd.asm','llcocovhd')
        for unit in (0,1):
            p=b.Machine(modules,backend='llcocovhd',base=0x7fffff)
            p.word(p.config+p.s['BC.Port'],PORT)
            p.byte(p.config+p.s['BC.Unit'],unit)
            device=VHD(p);p.ok('Init')
            assert p.allocation_sizes[b.STATE]==512
            for lba,buffer in ((0,b.BUF),(0x7fff,0x5f81),(0x8000,0x5fff),(0x7fffff,b.BUF)):
                p.request(lba=lba,buf=buffer);p.byte(b.REQ+p.s['BR.Unit'],unit)
                p.ok('Read',cc=0x50)
                assert p.data(buffer,512)==device.data(lba*2)+device.data(lba*2+1)
                assert [r[:2] for r in device.reads[-2:]]==[(unit,lba*2),(unit,lba*2+1)]
                assert p.word(b.REQ+p.s['BR.Done'])==1
            for status,code in ((2,'E$NotRdy'),(255,'E$NotRdy'),(5,'E$Read'),(6,'E$Read')):
                device.fail=status;p.request(buf=b.BUF);p.byte(b.REQ+p.s['BR.Unit'],unit)
                result=p.run('Read')
                assert result[:2]==(1,p.s[code]),(status,result)
                assert p.word(b.REQ+p.s['BR.Done'])==0
            device.fail=None;device.fail_on=len(device.reads)+2
            p.m.load(b.BUF,b'\xa5'*512)
            p.request(buf=b.BUF);p.byte(b.REQ+p.s['BR.Unit'],unit)
            assert p.run('Read')[:2]==(1,p.s['E$Read'])
            assert p.word(b.REQ+p.s['BR.Done'])==0
            assert p.data(b.BUF,512)==device.data(0)+b'\xa5'*256
            device.fail_on=None
            device.fail=None;p.request(buf=b.BUF);p.byte(b.REQ+p.s['BR.Unit'],unit);p.ok('Read')
            before=len(device.reads)
            p.request(lba=0x800000,buf=b.BUF);p.byte(b.REQ+p.s['BR.Unit'],unit)
            assert p.run('Read')[:2]==(1,p.s['E$Sect'])
            p.request(buf=b.BUF);p.byte(b.REQ+p.s['BR.Unit'],unit)
            assert p.run('Write')[:2]==(1,p.s['E$WP'])
            assert len(device.reads)==before
            p.ok('Term');assert not p.allocations
        for port,unit,last in ((0xff90,0,100),(PORT,2,100),(PORT,0,0x800000)):
            p=b.Machine(modules,backend='llcocovhd',base=last)
            p.word(p.config+p.s['BC.Port'],port);p.byte(p.config+p.s['BC.Unit'],unit)
            assert p.run('Init')[:2]==(1,p.s['E$IllArg'])
            assert not p.allocations
        print(f'Level {level}: VHD units, carry/high limits, unaligned/cross-bank buffers, errors/retry, write protection and cleanup PASS',flush=True)
