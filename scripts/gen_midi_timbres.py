"""Generate added harmonic instruments and four-harmonic high-register banks.
Legacy ROM files are input only. No recorded samples or external sound fonts.
"""
from pathlib import Path
import math,json,hashlib
root=Path(__file__).resolve().parents[1];rom=root/'src/rom'
names=['sine','flute','reed','cello','piano','guitar','vibraphone','organ','bass','violin','strings','trumpet','sax','lead','pad','accordion']
partials={
 'organ':[1,.48,.28,.2,.12,.08,.06,.04], 'bass':[1,.38,.16,.07],
 'violin':[1,.85,.62,.43,.3,.2,.14,.1,.07,.05], 'strings':[1,.55,.35,.24,.15,.1],
 'trumpet':[1,.85,.65,.48,.32,.19,.12,.07], 'sax':[1,.65,.48,.24,.16,.08,.06],
 'lead':[1,.5,.33,.25,.2,.16,.14,.12], 'pad':[1,.16,.08,.04],
 'accordion':[1,.45,.32,.15,.12,.06,.04]}
def wave(a,n):
 v=[sum(g*math.sin(2*math.pi*(h+1)*i/n) for h,g in enumerate(a)) for i in range(n)]
 peak=max(map(abs,v)) or 1;return [round(x*32767/peak) for x in v]
def write(p,v):p.write_text(''.join(f'{x&65535:04x}\n' for x in v),encoding='ascii')
for name,a in partials.items():write(rom/(name+'4096.hex'),wave(a,4096))
for name in names:
 v=[int(x,16) for x in (rom/(name+'4096.hex')).read_text().split()];v=[x-65536 if x>=32768 else x for x in v]
 a=[sum(v[i]*math.sin(2*math.pi*h*i/4096) for i in range(4096))*2/4096 for h in range(1,5)]
 write(rom/(name+'_high1024.hex'),wave(a,1024))
(rom/'midi_manifest.json').write_text(json.dumps({'names':names,'high_register_start':99,'high_harmonics':4,'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in rom.glob('*.hex')}},indent=2),encoding='utf8')
