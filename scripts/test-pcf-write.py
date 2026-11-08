#!/usr/bin/env python3
"""Execute PCF + blkdrv + VHD on MC6809 against mutable FAT32 sector maps."""
import importlib.util
from pathlib import Path
import tempfile
spec=importlib.util.spec_from_file_location('fat',Path(__file__).with_name('test-fat32.py'))
f=importlib.util.module_from_spec(spec);spec.loader.exec_module(f)
b=f.blk
class Machine(f.FatMachine):
    def ok(self,name,**kw):
        if name=='Init':
            self.word(self.config+self.s['BC.Port'],0xff80)
            self.long(self.config+self.s['BC.Base'],self.volume.base+self.volume.total-1)
            self.byte(self.config+self.s['BC.Flags'],0)
            self.reg=bytearray(7);self.status=0;self.writes=[];self.fail_write=None;self.fail_read=None
            for a in range(0xff80,0xff87):self.m.add_write_byte_callback(self.device,a)
            self.m.add_read_byte_callback(lambda *_:self.status,0xff83)
        return super().ok(name,**kw)
    def device(self,cycles,pc,address,value):
        self.reg[address-0xff80]=value
        if address!=0xff83:return
        assert value in (0,1)
        record=int.from_bytes(self.reg[:3],'big');buf=int.from_bytes(self.reg[4:6],'big')
        sector=self.volume.sectors.setdefault(record//2,bytearray(512))
        off=256*(record&1);self.status=0
        if value:
            self.writes.append(record)
            if len(self.writes)==self.fail_write:self.status=6;return
            sector[off:off+256]=self.data(buf,256)
        elif record==self.fail_read:self.status=6
        else:self.m.load(buf,sector[off:off+256])

def build(tmp,level,v):
    modules=b.assemble(tmp,level)
    modules['fixture']=f.assemble_source(tmp,level,f.ROOT/'level1/modules/llcocovhd.asm','vhd')
    pcf=f.assemble_source(tmp,level,f.ROOT/'level1/modules/pcf.asm','pcf')
    return Machine(modules,pcf,v)

def main():
    with tempfile.TemporaryDirectory(prefix='pcf-write-') as d:
        for level in (1,2):
            tmp=Path(d);v=f.Volume(base=2048)
            # Populate the mirrored copy as a real formatter would.
            for lba,data in list(v.sectors.items()):
                if v.base+32<=lba<v.base+32+v.fatsize:v.sectors[lba+v.fatsize]=bytearray(data)
            p=build(tmp,level,v)
            def ok(name,**kw):
                r=p.call(name,**kw);assert not r[0],(level,name,r);return r
            def error(name,code,**kw):
                r=p.call(name,**kw);assert r[:2]==(1,p.s[code]),(name,r,code)
            def put(data,line=False):
                p.m.load(f.OUTPUT,data)
                return ok('WriteLn' if line else 'Write',count=len(data))
            # A second-half transfer failure must invalidate either cache and
            # propagate E$Read; retry must fetch the complete sector afresh.
            for offset,record,valid in (
                (0,(v.data+8)*2+1,'F.DataValid'),
                (512,(v.base+32)*2+1,'F.FatValid'),
            ):
                ok('Open',mode=1,path='/pc0/frag.bin')
                ok('Seek',position=offset)
                p.fail_read=record
                error('Read','E$Read',count=512)
                assert p.byte(f.WORK+p.fs[valid])==0,(level,valid)
                assert p.data(f.WORK+p.fs['F.Pos'],4)==offset.to_bytes(4,'big')
                p.fail_read=None
                assert ok('Read',count=512)[2]==512
                assert p.data(f.OUTPUT,512)==v.fragment[offset:offset+512]
                ok('Close')
            payload=bytes((i*37+11)&255 for i in range(1800))
            ok('Create',mode=3,path='/pc0/new.bin')
            assert put(payload)[2]==len(payload)
            ok('Seek',position=0);assert ok('Read',count=2000)[2]==len(payload)
            assert p.data(f.OUTPUT,len(payload))==payload
            ok('Seek',position=510);assert put(b'XY\rBAD',True)[2]==3
            expected=payload[:510]+b'XY\r'+payload[513:]
            ok('Seek',position=0);ok('Read',count=2000)
            assert p.data(f.OUTPUT,len(expected))==expected,'WriteLn changed bytes after CR'
            ok('Seek',position=2300);put(b'END')
            expected+=bytes(500)+b'END'
            ok('Seek',position=0);ok('Read',count=3000)
            assert p.data(f.OUTPUT,len(expected))==expected,'seek gap'
            ok('SetStat',status=p.s['SS.Size'],position=513)
            ok('SetStat',status=p.s['SS.Size'],position=1400)
            expected=expected[:513]+bytes(887)
            ok('Seek',position=0);assert ok('Read',count=2000)[2]==1400
            assert p.data(f.OUTPUT,1400)==expected,'resize'
            ok('Close')
            error('Create','E$CEF',mode=3,path='/pc0/new.bin')
            ok('Open',mode=1,path='/pc0/new.bin');ok('Read',count=2000)
            assert p.data(f.OUTPUT,1400)==expected
            ok('Close');ok('Delete',path='/pc0/new.bin')
            error('Open','E$PNNF',mode=1,path='/pc0/new.bin')
            for i in range(24):
                ok('Create',mode=3,path=f'/pc0/N{i}.TXT');put(b'hello\r');ok('Close')
            for i in range(24):ok('Delete',path=f'/pc0/N{i}.TXT')
            for lba,data in v.sectors.items():
                if v.base+32<=lba<v.base+32+v.fatsize:
                    assert data==v.sectors.get(lba+v.fatsize,bytearray(512)),('FAT mirrors',lba)
            assert p.allocations==[b.STATE],p.allocations
            print(f'PASS Level {level}: cache failure/retry/create/read/write/WriteLn/seek gaps/resize/reopen/delete/directory growth/mirrors',flush=True)
if __name__=='__main__':main()
