"""Independent NumPy FFT and Pillow XY reference vectors for pure HDL checks."""
from pathlib import Path
import numpy as np,json,argparse
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out-dir',type=Path,required=True);p=ap.parse_args().out_dir;p.mkdir(parents=True,exist_ok=True)
 n=np.arange(2048)
 frames=[np.zeros(2048),16000*np.sin(2*np.pi*11*n/2048),16000*np.sin(2*np.pi*12*n/2048),12000*np.sin(2*np.pi*16*n/2048)+8000*np.sin(2*np.pi*64*n/2048),sum(650*np.sin(2*np.pi*k*n/2048) for k in range(8,136,4)),np.full(2048,-32768),np.where(n==1024,32767,0),4000*np.sin(2*np.pi*32*n/2048)]
 frames=[np.rint(f).astype(np.int16) for f in frames];hann=np.rint(np.hanning(2048)*32767).astype(np.int64)
 (p/'pcm.hex').write_text(''.join(f'{int(v)&65535:04x}\n' for f in frames for v in f))
 refs=[]
 for f in frames:
  z=np.fft.fft((f.astype(np.int64)*hann)>>15)/2048;refs.append([[float(v.real),float(v.imag)] for v in z[:1024]])
 (p/'fft_reference.json').write_text(json.dumps(refs))
 waves=[np.zeros(128,dtype=int),np.repeat([0,64,0,-64],32),np.tile([-128,127],64)]
 (p/'xy_input.hex').write_text(''.join(f'{int(v)&255:02x}\n' for w in waves for v in w))
 maps=[]
 for wave in waves:
  im=Image.new('1',(64,64));ImageDraw.Draw(im).line([(32+(int(wave[k])>>2),31-(int(wave[k-4])>>2)) for k in range(4,128)],fill=1,width=1);maps.append(np.array(im,dtype=np.uint8))
 (p/'xy_reference.hex').write_text(''.join(f'{int(v):x}\n' for im in maps for v in im.flat))
 (p/'display_wave.hex').write_text(''.join(f'{int(v)&255:02x}\n' for v in np.clip(frames[7][:512][3::4].astype(int)>>5,-128,127)))
 if (R/'sim/analysis_spectrum.hex').exists():(p/'display_spectrum.hex').write_bytes((R/'sim/analysis_spectrum.hex').read_bytes())
 print('Prepared8 FFT frames and3 independent XY maps')
if __name__=='__main__':main()
