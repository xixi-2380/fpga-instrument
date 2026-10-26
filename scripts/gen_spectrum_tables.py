from pathlib import Path
import numpy as np,json
R=Path(__file__).resolve().parents[1];N=2048
window=np.rint(np.hanning(N)*32767).astype(int)
tw=[((round(np.cos(-2*np.pi*k/N)*16384)&65535)<<16)|(round(np.sin(-2*np.pi*k/N)*16384)&65535) for k in range(N//2)]
edges=[0]
for i in range(1,65):edges.append(max(edges[-1]+1,round(2**(10*i/64))))
assert edges[-1]==1024
for name,vals,digits in [('fft_window',window,4),('fft_twiddle',tw,8),('fft_bands',edges,3)]:
 (R/'src/rom'/f'{name}.hex').write_text(''.join(f'{int(v):0{digits}x}\n' for v in vals))
(R/'assets/spectrum_config.json').write_text(json.dumps({'samples':N,'sample_rate':48000,'bin_hz':48000/N,'window':'symmetric Hann Q0.15','twiddle':'Q2.14','edges':edges,'edge_hz':[v*48000/N for v in edges],'display':'64 peak bands, relative log L1 magnitude, not calibrated dBFS'},indent=2)+'\n')
