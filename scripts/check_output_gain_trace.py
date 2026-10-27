"""Check production synth output against the separate mathematical limiter."""
import collections, json, pathlib, sys
from reference_audio_limiter import Limiter

p = pathlib.Path(sys.argv[1]); model = Limiter()
limited = collections.deque(); final = collections.deque()
gain = target = 256; checks = frames = 0; maximum = 0
for line in p.read_text().splitlines():
    parts = line.split()
    if parts[0] == 'P': target = round(int(parts[1])*256/100)
    elif parts[0] == 'C':
        model = Limiter(); limited.clear(); final.clear()
    elif parts[0] == 'F':
        limited.append(model.step(int(parts[1]))); frames += 1
    elif parts[0] == 'L':
        expected, expected_gain = limited.popleft()
        assert (int(parts[1]),int(parts[2])) == (expected,expected_gain), line
        final.append((expected*gain)//256)
        gain += 1 if gain < target else -1 if gain > target else 0
        checks += 1
    elif parts[0] == 'O':
        actual = int(parts[1]); expected = final.popleft()
        assert actual == expected, (actual,expected,line)
        maximum = max(maximum,abs(actual)); checks += 1
# The capture ends just after a sample boundary; at most the last accepted
# frame can still be in flight. All completed outputs must have been checked.
assert len(limited) <= 1 and not final
result = dict(passed=True,checks=checks,frames=frames,maximum_final_code=maximum,
              final_inflight_frames=len(limited),
              scope='production32-voice/48kHz final PCM checked with independent Python model')
p.with_suffix('.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print('PASS production output model',checks,'checks,',frames,'frames; peak',maximum)
