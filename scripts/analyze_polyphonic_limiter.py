"""Measure introduced gain modulation at identical polyphonic input levels."""
from pathlib import Path
import collections,json,math,sys,wave,struct
import numpy as np
from reference_audio_limiter import Limiter,write_wav
r=Path(__file__).resolve().parents[1];out=r/'reports/timing_audio_flash_2026-10-27/audio_analysis';out.mkdir(parents=True,exist_ok=True)
class HeldLimiter(Limiter):
 def __init__(self,*args,hold=240,**kwargs):super().__init__(*args,**kwargs);self.hold=hold;self.remaining=0
 def step(self,sample):
  self.audio.append(sample*self.pre);peak=max(abs(x) for x in self.audio);bound=min(65536,(self.ceiling*65536)//max(1,peak))
  if self.hold and bound<=self.release:self.release=bound;self.error=0;self.remaining=self.hold
  elif self.remaining:self.remaining-=1
  else:
   total=65536-self.release+self.error;candidate=self.release+(total>>self.shift);self.error=0 if bound<candidate else total% (1<<self.shift);self.release=min(bound,candidate)
  self.gains.append(self.release);gain=sum(self.gains)//self.w;product=self.audio[0]*gain;v=(abs(product)>>16)*(-1 if product<0 else 1)
  assert abs(v)<=self.ceiling
  return v,gain
rows=[]
for kind in ['unison','chord']:
 for count in [1,4,8,16]:
  length=48000;raw=np.zeros(length,dtype=np.int64)
  for k in range(count):
   freq=130.8127826503 if kind=='unison' else 130.8127826503*2**(([0,4,7,12,16,19,24,28,31,36,40,43,5,9,14,17][k])/12)
   raw+=np.rint(32767*.7/32*np.sin(2*np.pi*freq*np.arange(length)/48000)).astype(np.int64)
  assert np.max(np.abs(raw))<32768
  ys=[];gs=[]
  for model in [Limiter(),HeldLimiter()]:
   a=[model.step(int(x)) for x in raw];ys.append(np.array([x[0] for x in a],dtype=np.int64));gs.append(np.array([x[1] for x in a],dtype=np.int64))
  delayed=np.concatenate([np.zeros(63),raw[:-63]])[24000:].astype(float)
  def measure(y,g):
   a=y[24000:].astype(float);fit=np.dot(a,delayed)/np.dot(delayed,delayed);err=np.sqrt(np.mean((a-fit*delayed)**2))/max(1,np.sqrt(np.mean(a*a)))
   return dict(peak=int(np.max(np.abs(y))),rms=float(np.sqrt(np.mean(a*a))),relative_nonlinear_residual=float(err),gain_ripple_q16=int(np.max(g[24000:])-np.min(g[24000:])),gain_recoveries=int(np.sum(np.diff(g[24000:])>0)))
  row=dict(kind=kind,voices=count,before=measure(ys[0],gs[0]),after_hold_5ms=measure(ys[1],gs[1]));rows.append(row)
  write_wav(out/f'{kind}_{count}_before.wav',ys[0]);write_wav(out/f'{kind}_{count}_after.wav',ys[1]);write_wav(out/f'{kind}_{count}_input.wav',raw)
  if count==1:assert np.array_equal(ys[0],ys[1]),'single-note samples must remain exact'
  print(kind,count,'residual',round(row['before']['relative_nonlinear_residual'],6),'->',round(row['after_hold_5ms']['relative_nonlinear_residual'],6),'gain recoveries',row['before']['gain_recoveries'],'->',row['after_hold_5ms']['gain_recoveries'],flush=True)
(out/'release_hold_analysis.json').write_text(json.dumps(dict(sample_rate=48000,window=64,pre_gain=24,hold_samples=240,rows=rows,scope='Controlled synthetic PCM isolates limiter-added distortion, not proof of physical noise cause'),indent=2),encoding='utf-8')
