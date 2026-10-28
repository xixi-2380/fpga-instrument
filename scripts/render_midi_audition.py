"""Render the same project MIDI through existing ROM/envelopes and both limiter policies.
This is a sample-domain audition model, not a board recording or a replacement for RTL tests.
"""
from pathlib import Path
import collections,hashlib,json,math,struct,sys,wave
from functools import lru_cache
import numpy as np
from reference_audio_limiter import Limiter
# Avoid importing the analysis script because it intentionally executes its study.
class HeldLimiter(Limiter):
 def __init__(self):super().__init__();self.remaining=0
 def step(self,x):
  self.audio.append(x*self.pre);peak=max(abs(v) for v in self.audio);bound=min(65536,self.ceiling*65536//max(1,peak))
  if bound<=self.release:self.release=bound;self.error=0;self.remaining=240
  elif self.remaining:self.remaining-=1
  else:
   total=65536-self.release+self.error;candidate=self.release+(total>>self.shift);self.error=0 if bound<candidate else total%(1<<self.shift);self.release=min(bound,candidate)
  self.gains.append(self.release);g=sum(self.gains)//self.w;p=self.audio[0]*g;y=(abs(p)>>16)*(-1 if p<0 else 1);assert abs(y)<=self.ceiling
  return y,g

def read_midi(path):
 data=path.read_bytes();assert data[:4]==b'MThd';header=struct.unpack('>IHHH',data[4:14]);_,fmt,tracks,division=header;assert not division&0x8000
 offset=8+header[0];events=[];order=0
 def var(d,p):
  v=0
  while True:
   b=d[p];p+=1;v=(v<<7)|(b&127)
   if b<128:return v,p
 for tr in range(tracks):
  assert data[offset:offset+4]==b'MTrk';n=int.from_bytes(data[offset+4:offset+8],'big');d=data[offset+8:offset+8+n];offset+=8+n;p=0;tick=0;running=0
  while p<len(d):
   delta,p=var(d,p);tick+=delta;b=d[p]
   if b&128:p+=1;status=b
   else:status=running
   if status==255:
    kind=d[p];p+=1;length,p=var(d,p);payload=d[p:p+length];p+=length
    if kind==81:events.append((tick,order,'tempo',int.from_bytes(payload,'big')));order+=1
   elif status in [240,247]:length,p=var(d,p);p+=length;running=0
   else:
    running=status;length=1 if status>>4 in [12,13] else 2;payload=d[p:p+length];p+=length
    if status>>4 in [8,9]:events.append((tick,order,'on' if status>>4==9 and payload[1] else 'off',(status&15,payload[0],payload[1])));order+=1
 events.sort();tempo=500000;previous=0;micros=0;held=collections.defaultdict(collections.deque);notes=[]
 for tick,order,kind,arg in events:
  micros+=(tick-previous)*tempo/division;previous=tick;ms=int(micros/1000+.5)
  if kind=='tempo':tempo=arg
  elif kind=='on':held[arg[:2]].append((ms,arg[2]))
  elif held[arg[:2]]:
   start,vel=held[arg[:2]].popleft();notes.append((start,arg[1],vel,max(1,ms-start)))
 assert not any(held.values());return sorted(notes)

@lru_cache(maxsize=64)
def envelope(timbre,frames):
 a=np.zeros(frames+9648,dtype=np.int64);level=0;state=1;release=0
 for k in range(len(a)):
  a[k]=level
  if k==frames:
   if timbre<3:release=level
   else:release=(level>>(9 if timbre==5 else 10 if timbre==4 else 11))+1
   state=3
  elif state==1:
   if timbre<3:level=min(65536,((k+1)*65536)//480);state=2 if k+1>=480 else 1
   else:
    level=min(65536,level+{3:32,4:1024,5:2048,6:512}[timbre]);state=2 if level==65536 else 1
  elif state==2:
   if timbre<3:level=65536-min(19661,max(0,k+1-480)*19661//4800)
   elif timbre==3:
    if level>49152:level-=max(1,(level-49152)>>11)
   else:level=max(0,level-max(1,level>>(13 if timbre==4 else 12 if timbre==5 else 14)))
  elif state==3:
   if timbre<3:level=max(0,release-((k-frames)*release//9600))
   else:level=max(0,level-release)
 return a

r=Path(__file__).resolve().parents[1];out=r/'reports/timing_audio_flash_2026-10-27/midi_audition';out.mkdir(parents=True,exist_ok=True)
# This 82s project fixture includes explicit1/4/8/16-voice sections.
p=r/'android/examples/twinkle_capability_demo.mid';notes=read_midi(p);assert len(notes)==362 and max(x[0]+x[3] for x in notes)==82000
(out/'fixture_records.json').write_text(json.dumps({'file':str(p.relative_to(r)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'notes':notes},indent=2),encoding='utf-8')
# Keep four4s excerpts, one per polyphony section, to make audition practical.
starts=sorted({n[0] for n in notes});by_ms=[]
for t in starts:
 count=sum(s<=t<s+d for s,p,v,d in notes);by_ms.append((t,count))
segments=[]
for count in [1,4,8,16]:
 t=next(t for t,c in by_ms if c==count);segments.append((max(0,t-100),max(0,t-100)+4000,count))
summary=[]
for timbre,name in enumerate(['sine','flute','reed','cello','piano','guitar','vibraphone']):
 table=np.array([int(x,16) for x in (r/f'src/rom/{name}4096.hex').read_text().split()],dtype=np.int64);table=np.where(table>=32768,table-65536,table)
 all_before=[];all_after=[];all_mix=[];all_g0=[];all_g1=[];metrics=[]
 for start,end,count in segments:
  length=(end-start)*48;mix=np.zeros((length,2),dtype=np.int64)
  selected=[n for n in notes if n[0]<end and n[0]+n[3]+201>start]
  # Model32 physical slots including release tails. Truncate oldest release when full.
  physical=[];bounded=[]
  for note in selected:
   s,pitch,vel,d=note;physical=[v for v in physical if v['end']>s]
   if len(physical)==32:
    released=[v for v in physical if v['off']<=s];old=min(released or physical,key=lambda v:v['start']);old['end']=s;physical.remove(old)
   item=dict(start=s,off=s+d,end=s+d+201,note=note);physical.append(item);bounded.append(item)
  for item in bounded:
   s,pitch,vel,d=item['note'];a=max(start,s);b=min(end,item['end']);
   if b<=a:continue
   k=np.arange((a-s)*48,(b-s)*48,dtype=np.int64);e=envelope(timbre,d*48)[k];g=(vel*256+63)//127;e=e*g//256
   fcw=round(440*2**((pitch-69)/12)*2**32/48000);waveform=table[((k*fcw)&0xffffffff)>>20];voice=(waveform*e)>>13
   if pitch<60:l=voice-(voice>>2);rr=voice>>2
   elif pitch<66:l=voice;rr=voice>>1
   elif pitch<72:l=voice>>1;rr=voice
   else:l=voice>>2;rr=voice-(voice>>2)
   mix[(a-start)*48:(b-start)*48,0]+=l;mix[(a-start)*48:(b-start)*48,1]+=rr
  mix=mix>>8;assert np.max(np.abs(mix))<=32768
  before=np.zeros_like(mix);after=np.zeros_like(mix);g0=[];g1=[]
  for channel in range(2):
   old=Limiter();new=HeldLimiter()
   for n,x in enumerate(mix[:,channel]):
    before[n,channel],ga=old.step(int(x));after[n,channel],gb=new.step(int(x));g0.append(ga);g1.append(gb)
  ga0=np.array(g0,dtype=np.int32).reshape(2,length).T;ga1=np.array(g1,dtype=np.int32).reshape(2,length).T
  metrics.append(dict(voices=count,source_ms=[start,end],before_peak=int(np.max(np.abs(before))),after_peak=int(np.max(np.abs(after))),before_rms=float(np.sqrt(np.mean(before.astype(float)**2))),after_rms=float(np.sqrt(np.mean(after.astype(float)**2))),before_gain_q16=[int(ga0.min()),int(ga0.max())],after_gain_q16=[int(ga1.min()),int(ga1.max())],before_hard_clips=int(np.count_nonzero(np.abs(before)>29204)),after_hard_clips=int(np.count_nonzero(np.abs(after)>29204))))
  all_before.append(before);all_after.append(after)
  all_mix.append(mix);all_g0.append(ga0);all_g1.append(ga1)
 np.savez_compressed(out/f'{name}_sample_trace.npz',mix=np.concatenate(all_mix).astype(np.int16),before=np.concatenate(all_before).astype(np.int16),after=np.concatenate(all_after).astype(np.int16),gain_before_q16=np.concatenate(all_g0),gain_after_q16=np.concatenate(all_g1),sample_rate=np.int32(48000))
 for label,arrays in [('before',all_before),('after',all_after)]:
  y=np.concatenate(arrays);f=out/f'{name}_{label}.wav'
  with wave.open(str(f),'wb') as w:w.setparams((2,2,48000,0,'NONE','not compressed'));w.writeframes(y.astype('<i2').tobytes())
 summary.append(dict(timbre=name,segments=metrics));print('AUDITION',name,'four polyphonic excerpts rendered',flush=True)
(out/'audition_summary.json').write_text(json.dumps({'scope':'same project MIDI, sample-domain audition model; not a physical or RTL recording','sample_rate':48000,'segments':segments,'tables':summary},indent=2),encoding='utf-8')
