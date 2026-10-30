"""Sustain, repeat ownership, decoded UI and production interface regression."""
import argparse, concurrent.futures, hashlib, json, pathlib, subprocess, sys, time
p=argparse.ArgumentParser();p.add_argument('--out-dir',required=True);p.add_argument('--jobs',type=int,default=3);a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];out=r/a.out_dir;out.mkdir(parents=True,exist_ok=True)
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
inputs={str(f.relative_to(r)):sha(f) for folder in ['src','sim'] for f in sorted((r/folder).rglob('*')) if f.is_file()}
(out/'source_manifest.json').write_text(json.dumps(inputs,indent=2),encoding='utf8')
tests=[('natural_tail','tb_bt_natural_sustain',[],False),('silence_decay','tb_effects_silence',[],False),('sustain_envelope','tb_sustain_envelope',[],False),('sustain_controls','tb_sustain_controls',[],False),
 ('sustain_direct','tb_sustain_direct',[],False),('retrigger32','tb_sustain_retrigger',['VOICES=32'],False),
 ('pcb_readable','tb_pcb_readable',[],False),('pcb_repeat','tb_pcb_repeat',[],False),
 ('allocator','tb_voice_allocator',[],False),('native_envelopes','tb_instrument_envelopes',[],False),
 ('latency_mono','tb_audio_latency',[],False),('latency_stereo','tb_audio_latency',['STEREO=1'],False),
 ('display_connector','tb_rgb_display',[],True)]
tests += [('retrigger_timbre_'+str(t),'tb_sustain_retrigger',['TIMBRE='+str(t)],False) for t in range(7)]
def run(c):
 name,test,params,pll=c;d=out/name;d.mkdir(exist_ok=True);cmd=[sys.executable,'scripts/run_sim.py','--test',test,'--out-dir',str(d)]
 if pll:cmd+=['--behavioral-pll']
 for param in params:cmd+=['--param',param]
 start=time.monotonic();v=subprocess.run(cmd,cwd=r,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=1800)
 (d/'runner.log').write_text(v.stdout+v.stderr,encoding='utf8')
 result=dict(name=name,test=test,parameters=params,passed=v.returncode==0,seconds=round(time.monotonic()-start,3))
 (d/'result.json').write_text(json.dumps(result,indent=2),encoding='utf8');print(('PASS ' if result['passed'] else 'FAIL ')+name,flush=True)
 if not result['passed']:print((v.stdout+v.stderr)[-1800:],flush=True)
 return result
with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(run,tests))
same=all(sha(r/f)==h for f,h in inputs.items())
(out/'validation.json').write_text(json.dumps(dict(passed=all(v['passed'] for v in results) and same,sources_unchanged=same,results=results),indent=2),encoding='utf8')
raise SystemExit(0 if all(v['passed'] for v in results) and same else 1)
