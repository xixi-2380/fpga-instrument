"""Self-authored SMF fixtures; no third-party music or samples."""
from pathlib import Path
import struct,json
root=Path(__file__).resolve().parents[1];out=root/'android/examples';out.mkdir(exist_ok=True)
def vlq(n):
 b=[n&127];n>>=7
 while n:b.insert(0,(n&127)|128);n>>=7
 return bytes(b)
def track(events,end):
 data=b'';last=0
 for t,raw in sorted(events,key=lambda x:x[0]):data+=vlq(t-last)+bytes(raw);last=t
 data+=vlq(end-last)+bytes([255,47,0]);return b'MTrk'+struct.pack('>I',len(data))+data
def write(name,tracks,ppqn):
 raw=b'MThd'+struct.pack('>IHHH',6,1,len(tracks),ppqn)+b''.join(tracks);(out/name).write_bytes(raw)
write('midi_timbre_protocol.mid',[track([(0,[0xc0,40]),(0,[0x90,21,100]),(100,[0x80,21,0])],250),track([(0,[0xc1,32]),(0,[0x91,108,100]),(100,[0x81,108,0])],250),track([(0,[0x99,36,100]),(1,[0x89,36,0])],250)],500)
tracks=[track([(0,[255,81,3,7,161,32]),(16*480,[255,81,3,6,26,128])],32*480)]
for ch,pgm,pitch in [(0,0,64),(1,24,60),(2,32,36),(3,48,72)]:
 e=[(0,[0xc0+ch,pgm])]
 for beat in range(32):
  at=beat*480
  if ch==0 and beat%4==0:e.append((at,[0xb0+ch,64,127]))
  e.extend([(at,[0x90+ch,pitch+([0,2,4,7][beat%4] if ch==0 else 0),100]),(at+300,[0x80+ch,pitch+([0,2,4,7][beat%4] if ch==0 else 0),0])])
  if ch==0 and beat%4==3:e.append((at+420,[0xb0+ch,64,0]))
 tracks.append(track(e,32*480))
e=[]
for beat in range(32):
 for key in ([36,42] if beat%2==0 else [38,42]):e.extend([(beat*480,[0x99,key,100]),(beat*480+12,[0x89,key,0])])
 if beat%8==0:e.extend([(beat*480,[0x99,49,90]),(beat*480+12,[0x89,49,0])])
tracks.append(track(e,32*480));write('midi_multitimbral_ensemble.mid',tracks,480)
programs=[0,8,16,21,24,32,40,42,48,56,64,68,72,80,88]
e=[]
for i,p in enumerate(programs):e.extend([(i*960,[0xc0,p]),(i*960,[0x90,60,110]),(i*960+720,[0x80,60,0])])
write('gm_melodic_palette.mid',[track(e,len(programs)*960)],480)
print('Generated 3 self-authored multitimbral MIDI files')
