"""Generate standard MIDI fixtures from the existing score; no FPGA tools."""
from pathlib import Path
from fractions import Fraction
import argparse,json,struct,zlib,hashlib
root=Path(__file__).resolve().parents[1]
out=root/'android/examples'
def vlq(value):
    result=[value&127];value>>=7
    while value:result.insert(0,(value&127)|128);value>>=7
    return bytes(result)
def save(name,notes,ppqn):
    title=name.removesuffix('.mid').encode('ascii');events=[(0,-2,0,b'\xff\x03'+vlq(len(title))+title),(0,-1,0,b'\xff\x51\x03\x07\xa1\x20')]
    for i,note in enumerate(notes):
        start,pitch,velocity,length=note[:4];channel=note[4] if len(note)>4 else 0
        events.append((start,1,i,bytes([0x90|channel,pitch,velocity])))
        events.append((start+length,0,i,bytes([0x80|channel,pitch,0])))
    track=bytearray();previous=0
    for tick,_,_,payload in sorted(events):track+=vlq(tick-previous)+payload;previous=tick
    track+=b'\x00\xff\x2f\x00'
    midi=b'MThd'+struct.pack('>IHHH',6,0,1,ppqn)+b'MTrk'+struct.pack('>I',len(track))+track
    (out/name).write_bytes(midi)
    records=b'';events=[];duration=0
    for note in sorted(notes,key=lambda n:n[0]):
        start,pitch,vel,length=note[:4]
        start_ms=(start*500+ppqn//2)//ppqn;end_ms=((start+length)*500+ppqn//2)//ppqn
        records+=struct.pack('<IBBH',start_ms,pitch,vel,end_ms-start_ms);duration=max(duration,end_ms)
        events.extend([(start_ms,1),(end_ms,-1)])
    held=poly=0
    for _,delta in sorted(events):held+=delta;poly=max(poly,held)
    return dict(file=name,notes=len(notes),duration_ms=duration,polyphony=poly,min_pitch=min(n[1] for n in notes),max_pitch=max(n[1] for n in notes),crc32=f'{zlib.crc32(records):08X}',sha256=hashlib.sha256(midi).hexdigest()),records

def melody():
    notes=[]
    for line in (root/'src/scores/twinkle.txt').read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.lstrip().startswith(('#','end ')):continue
        start,length,identity=line.split();notes.append((int(Fraction(start)*480),int(identity.split(':')[0]),100,int(Fraction(length)*480)))
    return notes

CHORDS=[(48,52,55),(48,52,55),(48,53,57),(48,52,55),(50,55,59),(48,52,55),(48,52,55),(48,53,57),(48,52,55),(48,53,57),(50,55,59),(48,52,55)]

def demo():
    # Independent MIDI channels distinguish overlapping notes of the same pitch.
    # The FPGA converts all channels to its one currently selected timbre.
    notes=[];sections=[]
    for offset,voices,label in [(0,1,'melody'),(52,4,'chord accompaniment'),(104,8,'bass chords pad arpeggio')]:
        part=[(start+offset*480,pitch,96,length,0) for start,pitch,_,length in melody()]
        for bar,chord in enumerate(CHORDS):
            start=(offset+bar*4)*480
            if voices==4:
                part.extend((start,pitch,62,1680,2) for pitch in chord)
            elif voices==8:
                part.append((start,chord[0],70,1800,1))
                part.extend((start,pitch+12,44,1800,2) for pitch in chord)
                part.extend((start,pitch+24,30,1800,4) for pitch in chord[1:])
                for pulse in range(8):
                    part.append((start+pulse*240,chord[pulse%3]+12,52 if pulse%2==0 else 42,180,3))
        sections.append(dict(label=label,start_ms=offset*500,end_ms=(offset+48)*500,expected_polyphony=voices,notes=len(part)))
        notes.extend(part)
    # A short consonant C-major ending uses 16 logical voices, including
    # octave/unison doubling, rather than 16 different pitch classes.
    voicing=[48,52,55,60,64,67,72,76,79,48,55,60,64,67,72,79]
    for beat in (156,160):
        notes.extend((beat*480,pitch,56 if i<9 else 44,1920,i%5) for i,pitch in enumerate(voicing))
    sections.append(dict(label='16 voice ending',start_ms=78000,end_ms=82000,expected_polyphony=16,notes=32))
    info,records=save('twinkle_capability_demo.mid',notes,480)
    info.update(format=0,ppqn=480,bpm=120,sections=sections,rests_ms=[[24000,26000],[50000,52000],[76000,78000]],record_bytes=len(records),scope='Generated arrangement; Android parser verification is separate. Hardware playback pending.')
    report_dir=root/'reports/midi_capability_demo';report_dir.mkdir(parents=True,exist_ok=True)
    (report_dir/'expected_records.bin').write_bytes(records)
    (report_dir/'generated.json').write_text(json.dumps(info,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(info,indent=2))

def fixtures():
    notes=melody()
    for bar,chord in enumerate(CHORDS):
        for pitch in chord:notes.append((bar*4*480,pitch,80,1680))
    info=[save('twinkle_polyphonic.mid',notes,480)[0]]
    notes=[(start,60 if k%2==0 else 62,112+k,length) for start,length in [(0,4),(4,4),(8,16)] for k in range(16)]
    info.append(save('poly16_boundary_12ms.mid',notes,1000)[0])
    report=root/'reports/library_integration/midi_examples.json';report.parent.mkdir(parents=True,exist_ok=True);report.write_text(json.dumps(info,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(info,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--demo',action='store_true',help='Generate the staged musical demonstration without rewriting historical fixtures/reports')
    args=parser.parse_args()
    demo() if args.demo else fixtures()
