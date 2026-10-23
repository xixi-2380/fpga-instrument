from pathlib import Path
import math
root=Path(__file__).resolve().parents[1]
PRESETS={'flute':[(1,1.0),(2,0.20),(3,0.08)],
         'reed':[(1,1.0),(3,0.60),(5,0.30),(7,0.15)],
         # Harmonic approximations, not recorded samples or physical-model claims.
         'cello':[(1,1.0),(2,.70),(3,.48),(4,.30),(5,.19),(6,.13),(7,.08),(8,.05)],
         'piano':[(1,1.0),(2,.46),(3,.22),(4,.12),(5,.07),(6,.035)],
         'guitar':[(1,1.0),(2,.31),(3,.48),(4,.06),(5,.20),(6,.03),(7,.09)],
         'vibraphone':[(1,1.0),(4,.27),(10,.075)]}
for name,partials in PRESETS.items():
    wave=[sum(a*math.sin(2*math.pi*h*n/4096) for h,a in partials) for n in range(4096)]
    peak=max(abs(x) for x in wave)
    values=[round(x/peak*32767) for x in wave]
    (root/'src/rom'/f'{name}4096.hex').write_text(''.join(f'{v&65535:04x}\n' for v in values))
