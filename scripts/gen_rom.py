import math, pathlib, hashlib, json
root=pathlib.Path(__file__).resolve().parents[1]
values=[int(math.copysign(math.floor(abs(math.sin(2*math.pi*i/4096)*32767)+0.5),math.sin(2*math.pi*i/4096))) for i in range(4096)]
path=root/'rom/sine4096.hex'
path.parent.mkdir(exist_ok=True)
path.write_text(''.join(f'{v&65535:04x}\n' for v in values),encoding='ascii')
assert [values[i] for i in [0,1024,2048,3072]]==[0,32767,0,-32767]
(root/'rom/manifest.json').write_text(json.dumps(dict(depth=4096,width=16,format='signed Q1.15',rounding='nearest, ties away from zero',sha256=hashlib.sha256(path.read_bytes()).hexdigest()),indent=2),encoding='utf8')
print('ROM generated and cardinal samples verified')
