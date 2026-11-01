"""Package only a matching, fully checked implementation. Never programs hardware."""
import argparse,gzip,hashlib,json,pathlib,re,shutil,time
from inspect_timing import inspect
from check_lcd_clock_timing import inspect as inspect_clock
p=argparse.ArgumentParser();p.add_argument('--implementation',required=True)
p.add_argument('--features',required=True);p.add_argument('--extra',required=True);p.add_argument('--pcb',required=True)
a=p.parse_args();r=pathlib.Path(__file__).resolve().parents[1];report=r/'reports/pcb_flash_debug_2026-10-28';build=report/a.implementation
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
read=lambda f:json.loads(f.read_text(encoding='utf8'))
def write(f,data):f.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
def verify_manifest(path):
 m=read(path);assert all(sha(r/f)==v for f,v in m.items()),'Inputs changed: '+str(path)
 return m
result=read(build/'result.json');assert result['exit_code']==0 and result['sources_unchanged'] and not result['errors']
verify_manifest(build/'input_manifest.json')
log=(build/'build.log').read_text(encoding='utf8',errors='replace');assert 'Bitstream generation completed' in log
base=build/'pnr/D2_keyboard_leds'
started=read(build/'process.json')['started']
for product in [base.with_suffix('.fs'),base.with_suffix('.tr'),base.with_suffix('.sdf'),build/'gwsynthesis/D2_keyboard_leds.vg']:
 assert product.stat().st_mtime>=started-2,'Stale product: '+str(product)
timing=inspect(base.with_suffix('.tr'))
assert timing['setup_hold_pass'] and timing['all_reported_paths_nonnegative'] and timing['pulse_width_pass'],timing
assert all(timing['fmax'][c]['target']==v for c,v in [('ref_clk',50),('audio_clk',61.44),('pixel_clk',35)])
clock=inspect_clock(base.with_suffix('.tr'),base.with_suffix('.sdf'))
write(build/'timing_summary.json',timing);write(build/'lcd_clock_audit.json',clock)
features=read(r/a.features/'latest_run.json');extra=read(r/a.extra/'validation.json');pcb=read(r/a.pcb/'validation.json')
assert len(features)==25 and all(x['passed'] for x in features)
assert extra['passed'] and len(extra['results'])>=30 and pcb['passed'] and len(pcb['results'])==9
for d in [a.features,a.extra,a.pcb]:verify_manifest(r/d/'source_manifest.json')
assert read(r/a.features/'source_hash_audit.json')['unchanged']
assert extra['sources_unchanged'] and pcb['sources_unchanged']
full=report/'flash_production_1mhz_final';assert read(full/'result.json')['passed']
assert all(sha(r/f)==v for f,v in read(full/'dependency_manifest.json')['files'].items())
assert 'PASS tb_flash_production' in (full/'tb_flash_production.log').read_text(encoding='utf8')
assert read(report/'android_core/summary.json')['passed']
apk_dir=r/'android/build-local/pcb-flash-debug';apk=apk_dir/'GaoshanScore-0.3.3-pcb-flash-debug.apk'
assert sha(apk)==read(apk_dir/'build_summary.json')['sha256']
assert '5ea59e70b900f2bedb9fbc0bf071d74d111f69ad18d29c9fa6a26f27fb6b8f8f' in (apk_dir/'verify.log').read_text(encoding='utf8')
assert all(f.stat().st_mtime<=apk.stat().st_mtime for f in (r/'android/app/src/main').rglob('*') if f.is_file())
phase=read(report/'audio_phase/validation.json');assert phase['passed'] and phase['actual_sha256']==sha(r/'src/audio_timing.sv')
for t in [0,3]:
 d=report/f'bt_trace_timbre_{t}_final';v=read(d/'validation.json');assert v['passed']
 assert all(sha(r/f)==h for f,h in read(d/'input_manifest.json').items())
 assert sha(d/'audio_trace.csv')==v['trace_sha256']
snapshot=read(report/'source_snapshot.json');source=pathlib.Path(snapshot['source'])
source_after={f:sha(source/f) for f in snapshot['files']};assert source_after==snapshot['files'],'Original directory changed'
write(report/'source_integrity.json',dict(source=str(source),files_checked=len(source_after),unchanged=True))
for f in ['src/timbre_control.sv','src/keyboard.cst','src/config/keyboard_notes.svh']:assert sha(r/f)==snapshot['files'][f]
pins=dict(re.findall(r'IO_LOC "([^"]+)" ([A-Z]+\d+);',(r/'src/keyboard.cst').read_text(encoding='utf8')))
assert len(pins)==len(set(pins.values()))==73
pnr=base.with_suffix('.rpt.txt').read_text(encoding='utf8')
for port,ball in pins.items():
 m=re.search(r'^'+re.escape(port)+r'\s*\|\s*[^|]*\|\s*([A-Z]+\d+)/\d+\s*\|\s*(Y|N)',pnr,re.M)
 assert m and m[1]==ball and m[2]=='Y',(port,ball)
assert sha(r/'impl/pnr/D2_keyboard_leds.fs')==sha(base.with_suffix('.fs'))==result['bitstream_sha256']
def usage(text):
 return {m[1]:dict(used=float(m[2]),available=int(m[3])) for m in re.finditer(r'^\s*(Logic|Register|BSRAM|DSP|PLL)\s*\|\s*(\d+(?:\.\d+)?)/(\d+)',text,re.M)}
resources=usage(pnr);assert resources['PLL']['used']==3
baseline=inspect(report/'tested_baseline_impl/pnr/D2_keyboard_leds.tr')
write(report/'timing_resources.json',dict(before=baseline,after=timing,resources_after=resources))
dest=r/'dist/pcb-flash-debug';dest.mkdir(parents=True,exist_ok=True)
for src,name in [(base.with_suffix('.fs'),'D2_keyboard_leds.fs'),(base.with_suffix('.tr'),'D2_keyboard_leds.tr'),(base.with_suffix('.rpt.txt'),'D2_keyboard_leds.rpt.txt'),(build/'gwsynthesis/D2_keyboard_leds.vg','D2_keyboard_leds.vg'),(r/'src/keyboard.cst','keyboard.cst'),(r/'src/keyboard.sdc','keyboard.sdc'),(apk,apk.name)]:shutil.copy2(src,dest/name)
# Raw local SDF is retained; gzip is what is published to avoid GitHub file size limits.
shutil.copy2(base.with_suffix('.sdf'),dest/'D2_keyboard_leds.sdf')
with base.with_suffix('.sdf').open('rb') as src,gzip.open(dest/'D2_keyboard_leds.sdf.gz','wb') as out:shutil.copyfileobj(src,out)
assert '//SecurityBit: OFF' in (dest/'D2_keyboard_leds.fs').read_text(encoding='ascii',errors='replace')[:3000]
audition=report/'midi_audition';assert len(list(audition.glob('*_after.wav')))==7
shutil.copytree(audition,dest/'audio',dirs_exist_ok=True)
figures=dest/'screenshots';figures.mkdir(exist_ok=True)
from PIL import Image
for img in (r/a.pcb/'tb_pcb_renderer').glob('*.ppm'):Image.open(img).save(figures/(img.stem+'.png'))
for f in ['PCB与Flash修复_2026-10-28.md','keyboard_knob_issues_2026-10-28.md']:shutil.copy2(r/'docs'/f,dest/f)
source_manifest={str(f.relative_to(r)):sha(f) for folder in ['src','sim','scripts','android/app','android/tests'] for f in sorted((r/folder).rglob('*')) if f.is_file() and '__pycache__' not in f.parts}
source_manifest['keyboard_adsr.gprj']=sha(r/'keyboard_adsr.gprj');source_manifest['impl/keyboard_adsr_process_config.json']=sha(r/'impl/keyboard_adsr_process_config.json')
write(report/'final_source_manifest.json',source_manifest)
validation=dict(passed=True,implementation=a.implementation,build_id='26102801',source_original_unchanged=True,board_button_source_unchanged=True,pins=pins,clocks_mhz=dict(ref=50,audio=61.44,pixel=35),voices=32,automatic_ids=16,limiter_hold_samples=240,internal_setup_slack_ns=timing['internal_wns'],tns_zero=True,resources=resources,features=len(features),extra=len(extra['results']),pcb=len(pcb['results']),flash_4096_production_passed=True,lcd_clock=clock,hardware_programmed=False,hardware_phone_listening_verified=False,git_target='codex/integrated-instrument')
write(report/'validation.json',validation)
files={str(f.relative_to(dest)):sha(f) for f in sorted(dest.rglob('*')) if f.is_file() and f.name not in ['manifest.json','D2_keyboard_leds.sdf']}
validation['sdf_storage']={'published':'D2_keyboard_leds.sdf.gz','raw_local_file':'D2_keyboard_leds.sdf','raw_sha256':sha(dest/'D2_keyboard_leds.sdf'),'decode':'gzip -d or any archive tool'}
write(dest/'manifest.json',dict(**validation,files=files,implementation_inputs=str((build/'input_manifest.json').relative_to(r)),source_manifest=str((report/'final_source_manifest.json').relative_to(r))))
print('PACKAGE_PASS',dest,timing['internal_wns'])
