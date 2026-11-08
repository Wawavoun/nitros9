#!/usr/bin/env python3
"""Create a real 64 MiB FAT32 image with PyFatFS, including a fragmented file.
Requires pyfatfs and setuptools<81 (PyFilesystem's pkg_resources dependency).
"""
import argparse
import json
import struct
from pathlib import Path
from pyfatfs.PyFat import PyFat
from pyfatfs.PyFatFS import PyFatFS

SIZE=64*1024*1024
HELLO=b'FIRST\rSECOND\rTAIL'
FRAGMENT=bytes((i*73+19)&255 for i in range(1300))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('image',type=Path)
    args=parser.parse_args()
    args.image.parent.mkdir(parents=True,exist_ok=True)
    args.image.touch()
    fat=PyFat()
    fat.mkfs(str(args.image),PyFat.FAT_TYPE_FAT32,size=SIZE,label='FAT32TEST')
    fat.close()
    with PyFatFS(str(args.image),preserve_case=False) as fs:
        fs.writebytes('/HELLO.TXT',HELLO)
        fs.writebytes('/FRAG.BIN',FRAGMENT[:512])
        fs.writebytes('/GAP1.TMP',b'1'*512)
        with fs.openbin('/FRAG.BIN','a') as f:f.write(FRAGMENT[512:1024])
        fs.writebytes('/GAP2.TMP',b'2'*512)
        with fs.openbin('/FRAG.BIN','a') as f:f.write(FRAGMENT[1024:])
        chain=list(fs.fs.get_cluster_chain(fs._get_dir_entry('/FRAG.BIN').get_cluster()))
        assert len(chain)>=3 and any(b!=a+1 for a,b in zip(chain,chain[1:])),chain
        fs.remove('/GAP1.TMP');fs.remove('/GAP2.TMP')
        fs.writebytes('/EMPTY.TXT',b'')
        fs.makedir('/SUBDIR');fs.writebytes('/SUBDIR/NEST.TXT',b'NESTED\r')
        fs.makedir('/SUBDIR/CHILD')
    # Reopen independently of the writer's in-memory FAT/directory state.
    with PyFatFS(str(args.image),read_only=True) as fs:
        assert fs.readbytes('/HELLO.TXT')==HELLO
        assert fs.readbytes('/FRAG.BIN')==FRAGMENT
        assert fs.readbytes('/SUBDIR/NEST.TXT')==b'NESTED\r'
    # PyFatFS updates allocation tables but leaves mkfs's free-count hint stale.
    # Recompute both FSInfo copies from the on-disk FAT, not writer state.
    with args.image.open('r+b') as image:
        boot=image.read(512)
        reserved=int.from_bytes(boot[14:16],'little')
        fat_size=int.from_bytes(boot[36:40],'little')
        clusters=(SIZE//512-reserved-boot[16]*fat_size)//boot[13]
        image.seek(reserved*512)
        entries=list(struct.unpack('<'+'I'*(fat_size*128),image.read(fat_size*512)))
        free=[i for i in range(2,clusters+2) if entries[i]&0x0fffffff==0]
        info=int.from_bytes(boot[48:50],'little')
        backup=int.from_bytes(boot[50:52],'little')
        for sector in (info,backup+info):
            image.seek(sector*512+488)
            image.write(struct.pack('<II',len(free),free[0]))
    print(json.dumps({'image':str(args.image),'bytes':SIZE,'fragment_clusters':chain}))

if __name__=='__main__':main()
