"""Compare left/right production PCM with independent limiter histories."""
import collections,json,pathlib,sys
from reference_audio_limiter import Limiter
p=pathlib.Path(sys.argv[1]); target=256
lanes={k:dict(model=Limiter(),limited=collections.deque(),final=collections.deque(),gain=256,checks=0,frames=0,maximum=0) for k in ['L','R']}
for line in p.read_text().splitlines():
 parts=line.split(); kind=parts[0]
 if kind=='P': target=round(int(parts[1])*256/100);continue
 if kind=='C':
  for lane in lanes.values():lane['model']=Limiter();lane['limited'].clear();lane['final'].clear()
  continue
 lane=lanes['R' if kind.endswith('R') else 'L'];op=kind[0]
 if op=='F':lane['limited'].append(lane['model'].step(int(parts[1])));lane['frames']+=1
 elif op=='L':
  expected,expected_gain=lane['limited'].popleft()
  assert (int(parts[1]),int(parts[2]))==(expected,expected_gain),line
  lane['final'].append((expected*lane['gain'])//256)
  lane['gain']+=1 if lane['gain']<target else -1 if lane['gain']>target else 0;lane['checks']+=1
 elif op=='O':
  actual=int(parts[1]);expected=lane['final'].popleft();assert actual==expected,(actual,expected,line)
  lane['maximum']=max(lane['maximum'],abs(actual));lane['checks']+=1
assert all(len(x['limited'])<=1 and not x['final'] for x in lanes.values())
result=dict(passed=True,checks=sum(x['checks'] for x in lanes.values()),frames=lanes['L']['frames'],
 maximum_final_code=max(x['maximum'] for x in lanes.values()),final_inflight_frames=len(lanes['L']['limited']),
 channels={k:{f:v[f] for f in ['checks','frames','maximum']} for k,v in lanes.items() if v['frames']},
 scope='production32-voice/48kHz PCM checked with independent Python model per channel')
p.with_suffix('.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print('PASS production output model',result['checks'],'checks;',len(result['channels']),'channels;',result['frames'],'frames')
