"""Deterministic runtime-control vectors using independent integer queues."""
import argparse
from pathlib import Path
import random
from reference_effects import EffectsReference


def generate(production=False):
    rows=[]
    model=EffectsReference(production)
    rng=random.Random(20261023)
    def emit(x=0, en=1, mode=0, cfg=None, after=False):
        op=2 if cfg and after else 1 if cfg else 0
        values=cfg or (0,0,0,0)
        if cfg and not after:model.configure(*cfg)
        expected=model.sample(x,en,mode)
        if cfg and after:model.configure(*cfg)
        rows.append((op,*values,mode,int(en),x,expected))
        return expected
    def reset():
        nonlocal model
        model=EffectsReference(production)
        rows.append((3,0,0,0,0,0,0,0,0))
    reset()
    # Corners, clamping, minimum/full depth, two command timing positions.
    for mode in (0,1,2):
        for cfg in [(0,0,0,1),(256,256,256,10),(511,300,400,15),(64,64,128,5),(256,0,0,0)]:
            emit(-32768,mode=mode,cfg=cfg,after=(cfg[0]%2==1))
            for n in range(600):emit((-32768,32767,0,16384)[n%4],mode=mode)
    # Frequent updates while processing: no partially applied sample or torn tuple.
    for n in range(2400):
        cfg=tuple(rng.randrange(512) for _ in range(3))+(rng.randrange(16),) if n%7==0 else None
        emit(rng.randrange(-32768,32768),n%31<20,(n//83)%4,cfg,n%2==0)
    # Full 1-Hz LFO period and live speed changes without phase restart.
    emit(16384,mode=2,cfg=(64,64,256,1))
    for _ in range(600):emit(16384,mode=2)
    values=[emit(16384,mode=2) for _ in range(48010 if production else 1024)]
    if production:assert max(values)>16000 and min(values)<100
    for hz in range(1,11):
        emit(32767,mode=2,cfg=(64,64,128,hz),after=True)
        for _ in range(300):emit(32767,mode=2)
    # Exact depth-zero and wet-zero identities, not just model agreement.
    emit(12345,mode=2,cfg=(0,0,0,5))
    for _ in range(600):emit(12345,mode=2)
    for mode in (0,1,2):
        for n in range(600):
            x=rng.randrange(-32768,32768)
            assert emit(x,mode=mode)==x
    # Reset during in-flight work with non-default targets and dirty RAM.
    emit(-10000,mode=1,cfg=(256,256,256,10))
    reset()
    for n in range(600):assert emit(0,mode=1)==0
    # Bypass remains exact even with fast-changing parameter requests.
    for n in range(800):
        x=rng.randrange(-32768,32768)
        got=emit(x,0,2,(n%257,(n*3)%257,(n*7)%257,1+n%10),True)
        if n>256:assert got==x
    return rows


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--production',action='store_true');a=p.parse_args()
    rows=generate(a.production);a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(''.join(' '.join(map(str,r))+'\n' for r in rows))
    print(f'Runtime vectors {len(rows)} production={a.production}')
if __name__=='__main__':main()
