"""Timing/audio/Flash copy: offline regression; no programmer or hardware access."""
import argparse, concurrent.futures, hashlib, json, pathlib, subprocess, sys, time
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--jobs',type=int,default=2);p.add_argument('--only',action='append',default=[])
p.add_argument('--out-dir',default='reports/timing_audio_flash_2026-10-27/regression_extra');a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];out=pathlib.Path(a.out_dir)
if not out.is_absolute():out=r/out
out.mkdir(parents=True,exist_ok=True)
configs=[('limiter_legacy','tb_audio_limiter',[],False),
 ('limiter_fixed','tb_audio_limiter',['FIXED=1'],False),
 ('limiter_hold','tb_audio_limiter',['FIXED=1','HOLD=240'],False),
 ('flash_driver','tb_spi_nor_flash',[],False),
 ('flash_permissions_fast','tb_flash_write_permissions',[],False),
 ('flash_permissions_1mhz','tb_flash_write_permissions',['HALF=25'],False),
 ('flash_library','tb_flash_song_library',[],False),
 ('flash_protocol','tb_score_library_protocol',[],False),
 ('flash_fullchain_locks','tb_bt_library_link',['REGISTER_LOCKS=1'],True),
 ('display_connector','tb_rgb_display',[],True),
 ('envelope_production','tb_adsr_production',[],False),
 ('envelopes_seven','tb_instrument_envelopes',[],False),
 ('audio_timing','tb_audio_timing',[],False),
 ('master_volume','tb_master_volume',[],False),
 ('audio_articulation','tb_bt_articulation',[],False),
 ('display_cdc','tb_rgb_status_cdc',[],False)]
configs += [('polyphony_stereo_'+str(i),'tb_bt_polyphony',['STEREO=1','EFFECT='+str(i)],False) for i in range(3)]
configs += [('identity_timbre_'+str(i),'tb_bt_identity',['TIMBRE='+str(i)],True) for i in range(7)]
configs += [('auto_manual_timbre_'+str(i),'tb_auto_manual_equivalence',['TIMBRE='+str(i)],False) for i in range(7)]
if a.only:configs=[c for c in configs if c[0] in a.only]
assert configs and a.jobs>0
source_hashes={str(f.relative_to(r)):hashlib.sha256(f.read_bytes()).hexdigest() for folder in ['src','sim'] for f in sorted((r/folder).rglob('*')) if f.is_file()}
(out/'source_manifest.json').write_text(json.dumps(source_hashes,indent=2),encoding='utf8')
def run(c):
 name,test,params,behavioral=c;d=out/name;d.mkdir(parents=True,exist_ok=True)
 cmd=[sys.executable,str(r/'scripts/run_sim.py'),'--test',test,'--out-dir',str(d)]
 if behavioral:cmd+=['--behavioral-pll']
 for x in params:cmd+=['--param',x]
 start=time.monotonic()
 result=subprocess.run(cmd,cwd=r,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=2600)
 log=result.stdout+result.stderr;(d/'runner.log').write_text(log,encoding='utf8')
 value=dict(configuration=name,test=test,params=params,behavioral_pll=behavioral,passed=result.returncode==0,seconds=round(time.monotonic()-start,3))
 (d/'result.json').write_text(json.dumps(value,indent=2),encoding='utf8')
 print(('PASS ' if value['passed'] else 'FAIL ')+name,flush=True)
 if not value['passed']:print(log[-2200:],flush=True)
 return value
with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(run,configs))
same=all(hashlib.sha256((r/f).read_bytes()).hexdigest()==h for f,h in source_hashes.items())
(out/'validation.json').write_text(json.dumps(dict(passed=all(x['passed'] for x in results) and same,sources_unchanged=same,results=results),indent=2),encoding='utf8')
print('RESULT',sum(x['passed'] for x in results),'/',len(results),'SOURCE_HASH_MATCH',same,flush=True)
raise SystemExit(0 if all(x['passed'] for x in results) and same else 1)
