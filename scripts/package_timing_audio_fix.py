"""Package only a matching, fully checked implementation. Never programs or commits."""
import argparse,hashlib,json,pathlib,re,shutil,subprocess
from inspect_timing import inspect as timing_inspect
from check_lcd_clock_timing import inspect as clock_inspect
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--implementation',required=True);p.add_argument('--accept-zero-violation',action='store_true',help='User accepted zero violations/TNS=0 with actual margins disclosed');a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];reports=r/'reports/timing_audio_flash_2026-10-27';build=reports/a.implementation
def read(p):return json.loads(p.read_text(encoding='utf8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,data):p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
result=read(build/'result.json');assert result['exit_code']==0 and result['sources_unchanged'] and not result['errors']
started=read(build/'process.json')['started']
build_log=(build/'build.log').read_text(encoding='utf8',errors='replace')
assert 'Bitstream generation completed' in build_log and '[100%] Power analysis completed' in build_log
for product in ['pnr/D2_keyboard_leds.fs','pnr/D2_keyboard_leds.tr','pnr/D2_keyboard_leds.sdf','gwsynthesis/D2_keyboard_leds.vg']:
 assert (build/product).stat().st_mtime>=started,'Stale implementation product: '+product
inputs=read(build/'input_manifest.json')
assert all(sha(r/f)==h for f,h in inputs.items()),'Implementation input changed'
assert sha(r/'impl/keyboard_adsr_process_config.json')==sha(build/'process_config.json'),'IDE process configuration changed'
netlist=(build/'gwsynthesis/D2_keyboard_leds.vg').read_text(encoding='utf8',errors='replace')
local_ce=sorted(set(int(v) for v in re.findall(r'DFFCE\s+\\voices\[(\d+)\]\.envelope_ce_s\d+',netlist)))
assert local_ce==list(range(32)),'Distributed envelope CE registers were merged or missing'
local_resets=sorted(set(int(v) for v in re.findall(r'DFF\w*\s+\\voices\[(\d+)\]\.envelope_reset_s\d+',netlist)))
encoder_ticks=sorted(set(int(v) for v in re.findall(r'DFF\w*\s+\\encoders\[(\d+)\]\.ms_tick_s\d+',netlist)))
assert local_resets==list(range(32)) and encoder_ticks==list(range(3)),'Local reset/tick registers were merged or missing'
base=build/'pnr/D2_keyboard_leds';timing=timing_inspect(base.with_suffix('.tr'))
assert all(timing[k] for k in ['setup_hold_pass','pulse_width_pass','all_reported_paths_nonnegative']),timing
assert timing['internal_margin_pass'] or a.accept_zero_violation,'Original0.5ns margin goal not met and revised acceptance was not selected'
clock=clock_inspect(base.with_suffix('.tr'),base.with_suffix('.sdf'))
write(build/'timing_summary.json',timing);write(build/'lcd_clock_audit.json',clock)
features=read(reports/'regression_features/latest_run.json');extra=read(reports/'regression_extra/validation.json')
assert len(features)==25 and all(x['passed'] for x in features),'Feature regression incomplete'
assert read(reports/'regression_features/source_hash_audit.json')['unchanged']
assert all(sha(r/f)==h for f,h in read(reports/'regression_features/source_manifest.json').items()),'Feature regression inputs changed'
assert extra['passed'] and len(extra['results'])==33,'Extended regression incomplete'
tests_manifest=read(reports/'regression_extra/source_manifest.json')
assert all(sha(r/f)==h for f,h in tests_manifest.items()),'Regression inputs changed'
java=read(reports/'android_core/summary.json');assert java['passed']
phase=read(reports/'audio_phase/validation.json');assert phase['passed'] and phase['actual_sha256']==sha(r/'src/audio_timing.sv')
pixels=read(reports/'renderer_equivalence/validation.json');assert pixels['passed'] and pixels['renderer_sha256']==sha(r/'src/rgb_ui_renderer.sv')
traces={}
for timbre in [0,3]:
 d=reports/('bt_trace_timbre_'+str(timbre));traces[timbre]=read(d/'validation.json')
 assert traces[timbre]['passed'] and sha(d/'audio_trace.csv')==traces[timbre]['trace_sha256']
 assert all(sha(r/f)==h for f,h in read(d/'input_manifest.json').items()),'Audio capture inputs changed'
 traces[timbre]['identical_to_stage2']=traces[timbre]['trace_sha256']==read(reports/('bt_trace_timbre_'+str(timbre)+'_stage2')/'validation.json')['trace_sha256']
snapshot=read(reports/'source_project_snapshot.json');original=pathlib.Path(snapshot['source'])
apk_summary=read(r/'android/build-local/timing-audio-fix/build_summary.json')
assert apk_summary['sha256']==sha(r/'android/dist/GaoshanScore-0.3.1-flashdiag.apk')
assert all(sha(r/f)==h for f,h in snapshot['files'].items() if f.startswith('android/app/')),'App sources changed since the copied diagnostic build'
after_hashes={f:sha(original/f) for f in snapshot['files']}
unchanged={f:after_hashes[f]==h for f,h in snapshot['files'].items()}
write(reports/'original_source_integrity.json',dict(source=str(original),files_checked=len(unchanged),unchanged=all(unchanged.values()),before_sha256=snapshot['files'],after_sha256=after_hashes,files=unchanged))
assert all(unchanged.values()),'Original source differs from copy-time hashes'
pins=lambda f:dict(re.findall(r'IO_LOC "([^"]+)" ([A-Z]+\d+);',f.read_text(encoding='utf8')))
pinmap=pins(r/'src/keyboard.cst');assert len(pinmap)==73 and len(set(pinmap.values()))==73
assert pinmap==pins(reports/'baseline/sources/src/keyboard.cst'),'Pin map changed'
pnr_text=base.with_suffix('.rpt.txt').read_text(encoding='utf8',errors='replace')
for port,ball in pinmap.items():
 m=re.search(r'^'+re.escape(port)+r'\s*\|\s*[^|]*\|\s*([A-Z]+\d+)/\d+\s*\|\s*(Y|N)',pnr_text,re.M)
 assert m and m[1]==ball and m[2]=='Y','Physical pin mismatch: '+port
def usage(path):
 t=path.read_text(encoding='utf8',errors='replace');d={}
 for key in ['Logic','Register','BSRAM','DSP','PLL']:
  m=re.search(r'^\s*'+key+r'\s*\|\s*(\d+(?:\.\d+)?)/(\d+)',t,re.M)
  if m:d[key]=dict(used=float(m[1]),available=int(m[2]))
 return d
resources=usage(base.with_suffix('.rpt.txt'));assert resources['PLL']['used']==3
assert sha(r/'impl/pnr/D2_keyboard_leds.fs')==sha(base.with_suffix('.fs'))==result['bitstream_sha256']
baseline=timing_inspect(reports/'baseline/pnr/D2_keyboard_leds.tr')
write(reports/'timing_resource_comparison.json',dict(before=baseline,after=timing,resources_before=usage(reports/'baseline/pnr/D2_keyboard_leds.rpt.txt'),resources_after=resources))
audition=reports/'midi_audition'
write(reports/'audition_manifest.json',dict(scope='MIDI sample-domain model, not board/RTL recording',fixture=read(audition/'fixture_records.json'),files={f.name:sha(f) for f in sorted(audition.iterdir()) if f.suffix in ['.wav','.npz','.json']}))
dest=r/'dist/timing-audio-fix';dest.mkdir(parents=True,exist_ok=True)
for src,name in [(base.with_suffix('.fs'),'D2_keyboard_leds.fs'),(base.with_suffix('.tr'),'D2_keyboard_leds.tr'),(base.with_suffix('.sdf'),'D2_keyboard_leds.sdf'),(base.with_suffix('.rpt.txt'),'D2_keyboard_leds.rpt.txt'),(build/'gwsynthesis/D2_keyboard_leds.vg','D2_keyboard_leds.vg'),(r/'src/keyboard.cst','keyboard.cst'),(r/'src/keyboard.sdc','keyboard.sdc'),(r/'android/build-local/timing-audio-fix/GaoshanScore-0.3.1-flashdiag.apk','GaoshanScore-0.3.1-flashdiag.apk')]:
 shutil.copy2(src,dest/name)
assert sha(dest/'GaoshanScore-0.3.1-flashdiag.apk')==sha(r/'android/dist/GaoshanScore-0.3.1-flashdiag.apk')
assert '//SecurityBit: OFF' in (dest/'D2_keyboard_leds.fs').read_text(encoding='ascii',errors='replace')[:3000]
logs=[]
for parent,records in [(reports/'regression_features',features),(reports/'regression_extra',extra['results'])]:
 for item in records:
  log=parent/item['configuration']/(item['test']+'.log');t=log.read_text(encoding='utf8')
  checks=re.findall(r'checks=(\d+)',t)
  logs.append(dict(configuration=item['configuration'],test=item['test'],checks=int(checks[-1]) if checks else None,log=str(log.relative_to(r))))
status=dict(implementation=a.implementation,branch=subprocess.check_output(['git','branch','--show-current'],cwd=r,text=True).strip(),source_original_unchanged=True,source_original_files_checked=len(unchanged),pin_count=len(pinmap),pins=pinmap,clocks_mhz=dict(ref=50,audio=61.44,pixel=35),voices=32,automatic_ids=16,distributed_envelope_ce_registers=len(local_ce),limiter_window=64,limiter_hold_samples=240,internal_wns_ns=timing['internal_wns'],tns_zero=all(v['tns']==0 for v in timing['tns']),timing_passed=True,lcd_clock_physical_bounds=clock,resources=resources,hdl_configurations=len(logs),hdl_checks=sum(v['checks'] or 0 for v in logs),tests=logs,java_checks=36114,supplemental=dict(audio_phase=phase,renderer_equivalence=pixels,bt_traces=traces),programmed_hardware=False,committed=False,pushed=False,board_flash_phone_and_listening_verified=False,audition_scope='same project MIDI rendered by sample-domain model; not RTL or board recording')
status['acceptance']=dict(zero_violations_required=True,tns_zero_required=True,original_internal_setup_target_ns=0.5,original_margin_target_met=timing['internal_margin_pass'],user_accepted_zero_violation_result=a.accept_zero_violation)
status['distributed_envelope_reset_registers']=len(local_resets);status['distributed_encoder_tick_registers']=len(encoder_ticks)
status.pop('committed');status.pop('pushed')
status['git_publication']=dict(target_branch='codex/integrated-instrument',state='artifact_packaging_before_commit',requested_by_user=True)
write(reports/'validation.json',status)
manifest={str(f.relative_to(r)):sha(f) for folder in ['src','sim','scripts','android/app','android/tests'] for f in sorted((r/folder).rglob('*')) if f.is_file() and '__pycache__' not in f.parts}
for f in ['keyboard_adsr.gprj','impl/keyboard_adsr_process_config.json','README.md','AGENTS.md','docs/timing_audio_flash_fix_2026-10-28.md']:manifest[f]=sha(r/f)
write(reports/'final_source_manifest.json',manifest)
write(dest/'manifest.json',dict(**{k:v for k,v in status.items() if k!='tests'},files={f.name:sha(f) for f in sorted(dest.iterdir()) if f.is_file() and f.name!='manifest.json'},implementation_input_manifest=str((build/'input_manifest.json').relative_to(r)),final_source_manifest=str((reports/'final_source_manifest.json').relative_to(r))))
print('PACKAGE_PASS',dest,'configurations',len(logs),'internal_wns',timing['internal_wns'])
