#!/usr/bin/env python3
"""Build and verify a FAT32 /DD boot with no resident floppy driver."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from pyfatfs.PyFatFS import PyFatFS

ROOT=Path(__file__).resolve().parents[1]
COMMANDS=('grfdrv','shell','mdir','dir','list','copy','cmp')

def module_names(data, lowercase=True):
    result=set();offset=0
    while offset<len(data):
        assert data[offset:offset+2]==b'\x87\xcd'
        size=int.from_bytes(data[offset+2:offset+4],'big')
        assert size>=13 and offset+size<=len(data)
        at=offset+int.from_bytes(data[offset+4:offset+6],'big');name=bytearray()
        while True:
            value=data[at];at+=1;name.append(value&127)
            if value&128:break
        result.add(name.decode().lower() if lowercase else name.decode());offset+=size
    return result

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def prepare(args):
    recipe=args.recipe.resolve();root=args.root.resolve()
    root.mkdir(parents=True,exist_ok=True)
    stage=root/'system'
    if stage.exists():shutil.rmtree(stage)
    (stage/'CMDS').mkdir(parents=True);(stage/'SYS').mkdir()
    boot=(recipe/'bootfile').read_bytes();names=module_names(boot)
    assert {'dd','pcf','blkdrv','llcocovhd'}<=names
    assert {'pcf','blkdrv'}<=module_names(boot,lowercase=False),'runtime module names must be lowercase'
    assert 'blkdev' not in names
    assert not names&{'rbf','rb1773','d0','sysgo','shell','grfdrv'},names
    commands=COMMANDS+(('del','deldir','attr','dcheck','pwd','pxd','pcfshare') if args.write_test else ())
    for name in commands:shutil.copyfile(recipe/'.mods'/name,stage/'CMDS'/name.upper())
    shutil.copyfile(recipe/'.mods/sysgo_dd',stage/'SYSGO')
    (stage/'STARTUP').write_bytes((recipe/'startup').read_text().replace('\n','\r').encode())
    for name in ('stdfonts','stdptrs','errmsg','helpmsg','password','motd'):
        source=recipe/'.sys'/name
        if source.exists():shutil.copyfile(source,stage/'SYS'/name.upper())
    (stage/'FRAGCOPY.BIN').write_bytes(bytes((i*73+19)&255 for i in range(1300)))
    image=root/'fat32-root.vhd'
    subprocess.run([sys.executable,str(ROOT/'scripts/make-fat32-image.py'),str(image),
        '--boot-file',str(recipe/'bootfile'),'--system-root',str(stage)],check=True)
    disk=(recipe/'bootstrap.dsk').read_bytes()
    assert disk[0x15:0x1a]==bytes(5),'floppy has an OS9Boot pointer'
    assert len((recipe/'.mods/boot_fat32').read_bytes())==464
    # Record data-sector locations independently of emulator/guest code.
    with image.open('rb') as stream:bpb=stream.read(512)
    spc=bpb[13];data=int.from_bytes(bpb[14:16],'little')+bpb[16]*int.from_bytes(bpb[36:40],'little')
    records={}
    with PyFatFS(str(image),read_only=True) as fs:
        for name in ('/OS9BOOT','/SYSGO','/STARTUP',*(f'/CMDS/{n.upper()}' for n in commands)):
            entry=fs._get_dir_entry(name)
            chain=list(fs.fs.get_cluster_chain(entry.get_cluster()))
            count=(len(fs.readbytes(name))+255)//256
            records[name]=[2*(data+(c-2)*spc)+i for c in chain for i in range(2*spc)][:count]
    (root/'manifest.json').write_text(json.dumps({'resident':sorted(names),'records':records},indent=2))
    print('Prepared FAT32 /DD: SysGo, shell, GrfDrv, commands and startup; no RBF/floppy modules',flush=True)

def run(args):
    recipe=args.recipe.resolve();root=args.root.resolve()
    for folder in ('cfg','nvram','snap'):(root/folder).mkdir(exist_ok=True)
    disk=root/'bootstrap.dsk';media=root/'media.vhd'
    shutil.copyfile(recipe/'bootstrap.dsk',disk);shutil.copyfile(root/'fat32-root.vhd',media)
    hashes=(digest(disk),digest(media))
    commands=(recipe/'commands').read_text().splitlines()
    lua='commands={\n'+''.join(' '+json.dumps(c+'\n')+',\n' for c in commands if c)+'}\n'
    lua+='snapshot_path='+json.dumps(str(root/'screen.png'))+'\n'
    lua+='console_path='+json.dumps(str(root/'console.log'))+'\n'
    lua+='writes_path='+json.dumps(str(root/'vhd-writes.log'))+'\n'
    lua+='errors_path='+json.dumps(str(root/'errors.log'))+'\n'
    lua+='reads_path='+json.dumps(str(root/'vhd-reads.log'))+'\n'
    lua+=(ROOT/'scripts/fat32-root-mame.lua').read_text()+'\n'
    lua+=(ROOT/'scripts/fat32-mame.lua').read_text()
    (root/'run.lua').write_text(lua)
    cmd=[args.mame,'coco3','-rompath',args.rompath,'-skip_gameinfo','-cfg_directory',str(root/'cfg'),
        '-nvram_directory',str(root/'nvram'),'-snapshot_directory',str(root/'snap'),'-ram','512K',
        '-ext','fdc,bios=v11','-ext:fdc:wd17xx:0','525qd','-flop1',str(disk),'-hard1',str(media),
        '-autoboot_delay','3','-autoboot_script',str(root/'run.lua'),'-seconds_to_run',str(args.seconds),
        '-video','none','-sound','none','-nothrottle']
    if args.video:
        args.video.parent.mkdir(parents=True,exist_ok=True)
        cmd+=['-aviwrite',str(args.video.resolve()),'-snapsize','640x480']
    print('Booting with FAT32 /DD and kernel-track-only floppy:',root,flush=True)
    with (root/'mame.log').open('w') as log:
        subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=args.seconds+60)
    assert hashes[0]==digest(disk),'bootstrap floppy changed'
    if not args.write_test:assert hashes[1]==digest(media),'read-only FAT32 image changed'
    console=(root/'console.log').read_bytes()
    (root/'console.txt').write_bytes(console.replace(b'\r',b'\n'))
    startup=console.split(b'Shell+')[0]
    assert b'FAT32STARTUPDONE' in startup and b'Module Directory' in startup,'startup did not finish before the interactive shell'
    errors=[int(n) for n in (root/'errors.log').read_text().splitlines()]
    if args.write_test:
        assert errors==[249]*6,('expected six RBF-only rejections',errors)
        assert console.count(b'rbf only')==6
        assert b'PCFWRITEDONE' in console
        assert b'PCFSHARE PASS: 13 parent/child checks' in console
        assert b'PCFSHARE FAIL' not in console
        writes=(root/'vhd-writes.log').read_text().splitlines()
        assert writes and not any(line.startswith('GUARD ') for line in writes),'utility guard wrote to disk'
        with PyFatFS(str(media),read_only=True) as fs:
            assert fs.readbytes('/NEW.TXT')==b'FIRST\rSECOND\r'
            assert fs.readbytes('/COPY.BIN')==bytes((i*73+19)&255 for i in range(1300))
            assert fs.readbytes('/SUBDIR/NEW.TXT')==b'NESTEDWRITE\r'
            assert fs.readbytes('/SUBDIR/NEST.TXT')==b'NESTED\r'
            assert set(fs.listdir('/SUBDIR'))=={'NEW.TXT','NEST.TXT','CHILD'}
            assert fs.isdir('/SUBDIR/CHILD') and fs.listdir('/SUBDIR/CHILD')==[]
            assert not fs.exists('/GONE.BIN')
            assert not fs.exists('/SHARE.TXT') and not fs.exists('/OTHER.TXT')
    else:
        assert errors==[203],('expected only write-mode rejection from copy',errors)
        assert b'FATROOTEXEC' in console and b'FATROOTRELATIVE' in console
        assert b'FATROOTDONE' in console,'interactive tests did not finish'
        assert console.count(b'FIRST\rSECOND\rTAIL')==2 and b'NESTED' in console
        exec_listing=console.split(b'FATROOTRELATIVE',1)[1].split(b'FATROOTEXEC',1)[0]
        assert b'NEST.TXT' in exec_listing and b'CHILD' in exec_listing
    assert 'FLOPPY EJECTED' in (root/'mame.log').read_text()
    assert re.search(rb'Bytes compared:\s*00000514',console),console[-2000:]
    assert re.search(rb'Bytes different:\s*00000000',console),console[-2000:]
    reads={int(n) for n in (root/'vhd-reads.log').read_text().splitlines()}
    manifest=json.loads((root/'manifest.json').read_text())
    for name,records in manifest['records'].items():
        assert set(records)<=reads,f'file was not fully read from VHD: {name}'
    (root/'result.json').write_text(json.dumps({'passed':True,'resident':manifest['resident'],
        'loaded_files':list(manifest['records']),'floppy_sha256':hashes[0],'fat32_sha256':digest(media),'write_test':args.write_test,'errors':errors,
        'rbf_only_rejections':console.count(b'rbf only') if args.write_test else 0,
        'parent_child_sharing_checks':13 if args.write_test else 0},indent=2))
    if args.write_test:print('PASS: 13 parent/child sharing checks, independent read positions, SS.Lock rejected as unsupported',flush=True)
    if args.write_test:print('PASS: PCF create/write/append/copy/delete; attr/dcheck/pxd/pwd/deldir rejected without disk writes; deldir preserves the full subtree',flush=True)
    print('PASS: FAT32 OS9Boot + /DD, disk-loaded SysGo/shell/GrfDrv/commands, startup and cmp; bootstrap unchanged',flush=True)

def main():
    p=argparse.ArgumentParser()
    p.add_argument('action',choices=('prepare','run'));p.add_argument('--recipe',type=Path,required=True)
    p.add_argument('--root',type=Path,required=True);p.add_argument('--mame',default='mame')
    p.add_argument('--rompath',default=os.environ.get('MAME_ROMPATH',''));p.add_argument('--seconds',type=int,default=260)
    p.add_argument('--write-test',action='store_true')
    p.add_argument('--video',type=Path)
    args=p.parse_args();(prepare if args.action=='prepare' else run)(args)

if __name__=='__main__':main()
