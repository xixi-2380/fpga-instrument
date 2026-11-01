"""Selected regression for 8f10059 merged with limiter, LAT and ultrasound."""
import argparse,concurrent.futures,json,pathlib,subprocess,sys,time
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--only',action='append',default=[]);p.add_argument('--jobs',type=int,default=2);a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];out=r/'reports/stereo_integration_2026-10-27'
configs=[('allocator','tb_voice_allocator',[],False),('articulation','tb_bt_articulation',[],False),
 ('tail_mono','tb_bt_tail_reuse',['STEREO=0'],False),('tail_stereo','tb_bt_tail_reuse',['STEREO=1'],False),
 ('mono_math','tb_synth_core',[],False),('numeric_stereo','tb_stereo_audio',[],False),
 ('output_stereo','tb_output_gain',['STEREO=1'],False),('latency_stereo','tb_audio_latency',['STEREO=1'],False),
 ('protocol_stereo','tb_bt_score_audio',[],True),('bluetooth_stereo','tb_bluetooth_top',[],True),
 ('short_stereo','tb_bt_short_audio',[],True),('identity_stereo','tb_bt_identity',[],True),
 ('ultrasonic_stereo','tb_ultrasonic_top',[],True),('library_stereo','tb_bt_library_link',[],True),
 ('startup_stereo','tb_max98357_startup',[],True),('british_stereo','tb_british_top',[],True),
 ('keyboard_mono','tb_keyboard_top',[],True),('manual_stereo','tb_playback_regression',[],True)]
configs += [(f'poly_stereo_{i}','tb_bt_polyphony',['STEREO=1',f'EFFECT={i}'],False) for i in range(3)]
configs += [('limiter_variable','tb_audio_limiter',['FIXED=0'],False),('limiter_fixed','tb_audio_limiter',['FIXED=1'],False)]
if a.only:configs=[x for x in configs if x[0] in a.only]
assert configs and a.jobs>0
def run(c):
 name,test,params,behavioral=c;d=out/name;d.mkdir(parents=True,exist_ok=True)
 cmd=[sys.executable,str(r/'scripts/run_sim.py'),'--test',test,'--out-dir',str(d)]
 if behavioral:cmd+=['--behavioral-pll']
 for x in params:cmd+=['--param',x]
 start=time.monotonic();x=subprocess.run(cmd,cwd=r,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=1200)
 (d/'runner.log').write_text(x.stdout+x.stderr,encoding='utf8')
 v=dict(configuration=name,test=test,params=params,behavioral_pll=behavioral,passed=x.returncode==0,seconds=round(time.monotonic()-start,3))
 (d/'merge_result.json').write_text(json.dumps(v,indent=2),encoding='utf8')
 print(('PASS ' if v['passed'] else 'FAIL ')+name,flush=True)
 if not v['passed']:print((x.stdout+x.stderr)[-2000:],flush=True)
 return v
with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(run,configs))
(out/'latest_run.json').write_text(json.dumps(results,indent=2),encoding='utf8')
print('RESULT',sum(v['passed'] for v in results),'/',len(results),flush=True)
raise SystemExit(0 if all(v['passed'] for v in results) else 1)
