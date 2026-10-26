from pathlib import Path
import numpy as np,json,math,argparse
R=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('directory',type=Path);p=ap.parse_args().directory
 ref=np.array(json.loads((p/'fft_reference.json').read_text()));actual=np.zeros_like(ref);bars=np.zeros((len(ref),64),dtype=int)
 for line in (p/'fft_actual.txt').read_text().splitlines():
  t=line.split()
  if t[0]=='B':bars[int(t[1]),int(t[2])]=int(t[3])
  else:actual[int(t[0]),int(t[1])]=[int(t[2]),int(t[3])]
 worst=float(np.abs(actual-ref).max());assert worst<=16,('FFT error',worst)
 edges=json.loads((R/'assets/spectrum_config.json').read_text())['edges'];checks=actual.size
 for f in range(len(ref)):
  for b in range(64):
   mag=int(np.abs(actual[f,edges[b]:edges[b+1]]).sum(axis=1).max());exp=mag.bit_length()-1;expected=0 if mag==0 else min(127,8*exp+((mag<<3)>>exp)%8)
   assert bars[f,b]==expected,(f,b,bars[f,b],expected);checks+=1
 for f,k in [(1,11),(2,12)]:assert np.argmax(np.hypot(actual[f,:,0],actual[f,:,1]))==k and bars[f,:32].argmax()==k;checks+=2
 for k in [16,64]:assert np.hypot(*actual[3,k])>1800;checks+=1
 for k in range(8,136,4):assert np.hypot(*actual[4,k])>100;checks+=1
 assert not actual[0].any() and not bars[0].any() and actual[5,0,0]<-16000;checks+=2
 result={'passed':True,'checks':checks,'frames':len(ref),'fft_component_max_error_lsb':worst,'resolution_hz':23.4375,'polyphony_fft_peaks_verified':32,'limits':'Grouped high-frequency bands can merge peaks; relative L1 magnitude, not calibrated dBFS.'}
 (p/'fft_numeric_check.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
if __name__=='__main__':main()
