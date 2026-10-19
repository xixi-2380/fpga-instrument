from pathlib import Path
import math
root=Path(__file__).resolve().parents[1]
PRESETS={'flute':[(1,1.0),(2,0.20),(3,0.08)],
         'reed':[(1,1.0),(3,0.60),(5,0.30),(7,0.15)]}
for name,partials in PRESETS.items():
    wave=[sum(a*math.sin(2*math.pi*h*n/4096) for h,a in partials) for n in range(4096)]
    peak=max(abs(x) for x in wave)
    values=[round(x/peak*32767) for x in wave]
    (root/'src/rom'/f'{name}4096.hex').write_text(''.join(f'{v&65535:04x}\n' for v in values))
