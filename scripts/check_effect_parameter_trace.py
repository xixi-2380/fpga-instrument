"""Verify live synth effects against the independent sample-domain queue model."""
import argparse
from pathlib import Path
from reference_effects import EffectsReference

def verify(path):
    model=EffectsReference(False)
    model.step=447392  # Actual synth uses production LFO, shortened delay lines only.
    pending=[];samples=configs=outputs=0
    for line in path.read_text().splitlines():
        kind,*values=line.split();values=list(map(int,values))
        if kind=='C':model.configure(*values);configs+=1
        elif kind=='S':pending.append(model.sample(*values));samples+=1
        elif kind=='O':
            assert pending, 'Output without input'
            expected=pending.pop(0)
            assert values[0]==expected, (outputs, values[0],expected)
            outputs+=1
        else:raise AssertionError(kind)
    assert outputs==samples and configs>=30 and not pending
    return dict(samples=samples,outputs=outputs,configurations=configs)
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('trace',type=Path);a=p.parse_args()
    print('PASS independent runtime synth trace',verify(a.trace))
