"""Touch-keyboard + EC11 integration: logic simulation only, no EDA or programming."""
import argparse,concurrent.futures,hashlib,json,pathlib,subprocess,sys,time
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--only',action='append',default=[]);p.add_argument('--jobs',type=int,default=2);p.add_argument('--out-dir',default='reports/touch_ec11_2026-10-27');a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];out=pathlib.Path(a.out_dir)
if not out.is_absolute():out=r/out
out.mkdir(parents=True,exist_ok=True)
configs=[('aip_fast','tb_aip5916_keyboard',[],False),('aip_100k','tb_aip5916_keyboard',['HALF=250'],False),
 ('encoder','tb_ec11_encoder',[],False),('ec11_controls','tb_ec11_controls',[],False),
 ('events36','tb_key_note_events',['NUM_KEYS=36'],False),('router','tb_touch_keyboard_router',[],False),
 ('stacked_small','tb_stacked_effects',[],False),('stacked_production','tb_stacked_effects',['PROD=1'],False),
 ('top','tb_touch_ec11_top',[],True),('stereo_math','tb_stereo_audio',[],False),
 ('latency','tb_audio_latency',['STEREO=1'],False),('output_stereo','tb_output_gain',['STEREO=1'],False),
 ('bluetooth','tb_bluetooth_top',[],True),('identity','tb_bt_identity',[],True),
 ('short','tb_bt_short_audio',[],True),('library','tb_bt_library_link',[],True),
 ('startup','tb_max98357_startup',[],True),('ultrasonic','tb_ultrasonic_top',[],True),
 ('british_top','tb_british_top',[],True),('ui','tb_rgb_ui_renderer',[],False),
 ('touch_panel','tb_gt9110_touch',[],False),('i2c_legacy','tb_i2c_register_master',[],False),
 ('board_controls','tb_timbre_control',[],False),('allocator','tb_voice_allocator',[],False),('tail_stereo','tb_bt_tail_reuse',['STEREO=1'],False)]
if a.only:configs=[x for x in configs if x[0] in a.only]
assert configs and a.jobs>0
inputs={str(f.relative_to(r)):hashlib.sha256(f.read_bytes()).hexdigest() for folder in ['src','sim'] for f in sorted((r/folder).rglob('*')) if f.is_file()}
(out/'source_manifest.json').write_text(json.dumps(inputs,indent=2),encoding='utf8')

def run(c):
 name,test,params,behavioral=c;d=out/name;d.mkdir(parents=True,exist_ok=True)
 cmd=[sys.executable,str(r/'scripts/run_sim.py'),'--test',test,'--out-dir',str(d)]
 if behavioral:cmd+=['--behavioral-pll']
 for x in params:cmd+=['--param',x]
 start=time.monotonic();x=subprocess.run(cmd,cwd=r,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=2600)
 (d/'runner.log').write_text(x.stdout+x.stderr,encoding='utf8')
 v=dict(configuration=name,test=test,params=params,behavioral_pll=behavioral,passed=x.returncode==0,seconds=round(time.monotonic()-start,3))
 (d/'result.json').write_text(json.dumps(v,indent=2),encoding='utf8')
 print(('PASS ' if v['passed'] else 'FAIL ')+name,flush=True)
 if not v['passed']:print((x.stdout+x.stderr)[-1500:],flush=True)
 return v
with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(run,configs))
(out/'latest_run.json').write_text(json.dumps(results,indent=2),encoding='utf8')
print('RESULT',sum(v['passed'] for v in results),'/',len(results),flush=True)
same=all(hashlib.sha256((r/f).read_bytes()).hexdigest()==h for f,h in inputs.items())
(out/'source_hash_audit.json').write_text(json.dumps(dict(unchanged=same),indent=2),encoding='utf8')
raise SystemExit(0 if all(v['passed'] for v in results) and same else 1)
