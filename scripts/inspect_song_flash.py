"""Read-only checker for an exported U7 library region; never opens hardware."""
import argparse,json,pathlib,struct,zlib,heapq

SIZE=0x220000
def directory(image,bank):
    data=image[bank*4096:bank*4096+1056]
    if data[:6]!=b'FSC1\x01\x20' or data[16:20]!=b'DONE':
        return None
    if zlib.crc32(data[:12]+data[20:])!=struct.unpack_from('<I',data,12)[0]:
        return None
    rows=[];slots=set()
    for index in range(32):
        row=data[32+index*32:64+index*32]
        present,slot,count,duration,crc=struct.unpack_from('<BBHII',row)
        if present not in (0,1):return None
        if not present:continue
        if slot>32 or slot in slots or not 1<=count<=4096 or not 1<=duration<=3600000:return None
        slots.add(slot)
        try:name=row[12:19].split(b'\0')[0].decode('ascii')
        except UnicodeDecodeError:return None
        rows.append(dict(index=index+1,slot=slot,count=count,duration_ms=duration,crc32=f'{crc:08X}',name=name))
    return dict(bank=bank,generation=struct.unpack_from('<I',data,8)[0],songs=rows)

def inspect(path):
    image=pathlib.Path(path).read_bytes()
    if len(image)<SIZE:raise ValueError(f'need at least {SIZE} bytes from U7 address0')
    catalogs=[item for b in (0,1) if (item:=directory(image,b)) is not None]
    if not catalogs:raise ValueError('no complete CRC-valid committed directory')
    chosen=catalogs[0]
    for candidate in catalogs[1:]:
        difference=(candidate['generation']-chosen['generation'])&0xffffffff
        if 0<difference<0x80000000:chosen=candidate
    total=0
    for song in chosen['songs']:
        start=0x10000+song['slot']*65536
        payload=image[start:start+song['count']*8]
        if f'{zlib.crc32(payload):08X}'!=song['crc32']:raise ValueError(f"S{song['index']:03d} payload CRC mismatch")
        ends=[];last=0;duration=0;poly=0
        for i in range(song['count']):
            time,pitch,velocity,length=struct.unpack_from('<IBBH',payload,i*8)
            if time<last or not 48<=pitch<=83 or not 1<=velocity<=127 or not length or time+length>3600000:
                raise ValueError(f"S{song['index']:03d} illegal note {i}")
            while ends and ends[0]<=time:heapq.heappop(ends)
            heapq.heappush(ends,time+length);poly=max(poly,len(ends));duration=max(duration,time+length);last=time
        if poly>16 or duration!=song['duration_ms']:raise ValueError(f"S{song['index']:03d} polyphony/duration mismatch")
        song['polyphony']=poly;total+=song['count']
    return dict(valid=True,active_bank=chosen['bank'],generation=chosen['generation'],song_count=len(chosen['songs']),total_notes=total,songs=chosen['songs'])

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('image');parser.add_argument('--output');args=parser.parse_args()
    result=inspect(args.image);text=json.dumps(result,ensure_ascii=False,indent=2)
    if args.output:pathlib.Path(args.output).write_text(text+'\n',encoding='utf-8')
    print(f"PASS library image: {result['song_count']} songs, {result['total_notes']} notes, directory{result['active_bank']} generation{result['generation']}")
