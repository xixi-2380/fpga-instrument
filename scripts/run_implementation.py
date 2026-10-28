"""Fresh Gowin implementation with immutable input hashes; never programs hardware."""
import argparse,hashlib,json,os,pathlib,re,shutil,subprocess,time,xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--name',required=True);a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];out=r/'reports/timing_audio_flash_2026-10-27'/a.name
assert not out.exists(), 'Use a new implementation name to preserve evidence'
out.mkdir(parents=True)
files=[f.get('path') for f in ET.parse(r/'keyboard_adsr.gprj').getroot().findall('./FileList/File') if f.get('enable')=='1']
files+=['keyboard_adsr.gprj','scripts/build_keyboard.tcl'];files=sorted(set(files))
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
manifest={f:digest(r/f) for f in files};(out/'input_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
for f in files:
 dst=out/'sources'/f;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(r/f,dst)
shutil.copy2(r/'impl/keyboard_adsr_process_config.json',out/'process_config.json')
start=time.monotonic();log=out/'build.log';print('BUILD_START',a.name,flush=True)
with log.open('w',encoding='utf-8') as h:
 proc=subprocess.Popen(['C:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe',str(r/'scripts/build_keyboard.tcl'),'build'],cwd=r,stdout=h,stderr=subprocess.STDOUT)
 (out/'process.json').write_text(json.dumps({'pid':proc.pid,'started':time.time()}))
 code=proc.wait()
text=log.read_text(encoding='utf-8',errors='replace');same=all(digest(r/f)==v for f,v in manifest.items())
result={'name':a.name,'exit_code':code,'seconds':round(time.monotonic()-start,2),'sources_unchanged':same}
for folder in ['gwsynthesis','pnr']:
 src=r/'impl'/folder
 if src.exists():
  for f in src.iterdir():
   if f.is_file() and f.suffix in ['.vg','.tr','.html','.txt','.fs','.sdf','.log','.tcl','.do']:
    dst=out/folder/f.name;dst.parent.mkdir(exist_ok=True);shutil.copy2(f,dst)
tr=r/'impl/pnr/D2_keyboard_leds.tr'
if code==0 and tr.exists():
 t=tr.read_text(encoding='utf-8',errors='replace')
 result['setup_hold_violations']={k:int(m[1]) if (m:=re.search(r'<Numbers of '+k+r' Violated Endpoints>:(\d+)',t)) else None for k in ['Setup','Hold']}
 part=t.split('2.3 Max Frequency Summary')[-1].split('2.4 Total Negative Slack Summary')[0]
 result['fmax_mhz']={m[1]:{'target':float(m[2]),'actual':float(m[3])} for m in re.finditer(r'\d+\s+(\w+)\s+([\d.]+)\(MHz\)\s+([\d.]+)\(MHz\)',part)}
 result['bitstream_sha256']=digest(r/'impl/pnr/D2_keyboard_leds.fs') if (r/'impl/pnr/D2_keyboard_leds.fs').exists() else None
result['warnings']=re.findall(r'^.*WARN.*$',text,re.M);result['errors']=re.findall(r'^.*ERROR.*$',text,re.M)
(out/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('BUILD_RESULT',json.dumps(result),flush=True)
raise SystemExit(0 if code==0 and same and not result['errors'] else 1)
