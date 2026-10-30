"""Independent integer model of the production48kHz fractional stereo chorus.
No RTL introspection; generates deterministic corner/random/impulse/sine vectors.
"""
from pathlib import Path
import argparse, math, random

class Chorus:
    def __init__(self, offset=0):
        self.offset=offset
        self.reset()
    def reset(self):
        self.mem=[0]*2048; self.ptr=0; self.filled=0
        self.phase=0; self.amount=0; self.span=72*256
    def step(self, sample, enabled, wet, depth, rate):
        phase=(self.phase+self.offset)&0xffffffff
        triangle=(phase>>15)&65535
        if phase&0x80000000: triangle=65535-triangle
        delay=960*256+((triangle-32768)*self.span>>15)
        integer,frac=divmod(delay,256)
        a=self.mem[(self.ptr-integer)%2048] if self.filled>=integer else 0
        b=self.mem[(self.ptr-integer-1)%2048] if self.filled>integer else 0
        history=a+((b-a)*frac>>8)
        result=sample+((history-sample)*self.amount>>8)
        assert -32768<=result<=32767
        self.mem[self.ptr]=sample; self.ptr=(self.ptr+1)%2048
        self.filled=min(2048,self.filled+1)
        target=min(wet,128) if enabled else 0
        self.amount+=1 if self.amount<target else -1 if self.amount>target else 0
        target=(24,72,144)[min(depth,2)]*256
        self.span+=max(-16,min(16,target-self.span))
        self.phase=(self.phase+(26844,53687,107374)[min(rate,2)])&0xffffffff
        return result

def generate(out):
    rng=random.Random(20261030);left=Chorus();right=Chorus(0x40000000)
    rows=[]; different=0
    for n in range(24000):
        reset=n in (8300,17111)
        if reset:left.reset();right.reset()
        enabled=not (n<1200 or 7000<=n<8000 or 15000<=n<17000)
        wet=(32,64,96,128,511)[(n//2200)%5]
        depth=(n//3000)%3;rate=(n//4000)%3
        if n<1500: sample=32767 if n==1 else 0
        elif n<6500:sample=round(24000*math.sin(2*math.pi*440*n/48000))
        elif n<10000:sample=32767 if n%2 else -32768
        elif n<18000:sample=rng.randrange(-32768,32768)
        else:sample=0
        l=left.step(sample,enabled,wet,depth,rate);r=right.step(sample,enabled,wet,depth,rate)
        different+=l!=r;rows.append(f'{int(reset)} {int(enabled)} {wet} {depth} {rate} {sample} {l} {r}\n')
    out.write_text(''.join(rows));return {'frames':len(rows),'different_stereo_frames':different,'resets':2}

def check_chain(path):
    left=Chorus();right=Chorus(0x40000000);checks=0;nonzero=0
    for n,line in enumerate(path.read_text().splitlines()):
        reset,en,wet,depth,rate,il,ir,ol,orr=map(int,line.split())
        if reset:left.reset();right.reset()
        el=left.step(il,en,wet,depth,rate);er=right.step(ir,en,wet,depth,rate)
        assert (ol,orr)==(el,er),(n,(ol,orr),(el,er))
        checks+=2;nonzero+=bool(il or ir)
    assert checks>3000 and nonzero>1000
    return {'passed':True,'checks':checks,'nonzero_frames':nonzero,'scope':'independent production32voice dry-mix to post-chorus stereo values'}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();print(generate(a.output))
