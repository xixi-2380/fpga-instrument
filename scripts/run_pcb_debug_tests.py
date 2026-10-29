import argparse,concurrent.futures,hashlib,json,pathlib,subprocess,sys,time
p=argparse.ArgumentParser();p.add_argument('--out-dir',required=True);p.add_argument('--jobs',type=int,default=2);a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];out=r/a.out_dir;out.mkdir(parents=True,exist_ok=True)
manifest={str(f.relative_to(r)):hashlib.sha256(f.read_bytes()).hexdigest() for folder in ['src','sim'] for f in sorted((r/folder).rglob('*')) if f.is_file()}
(out/'source_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
tests=['tb_pcb_keyboard_runtime','tb_pcb_debug_ui','tb_pcb_touch','tb_pcb_config_deadline','tb_pcb_top','tb_pcb_renderer','tb_ui_more','tb_ui_inputs','tb_effect_cfg_replay']
def run(test):
 d=out/test;cmd=[sys.executable,'scripts/run_sim.py','--test',test,'--out-dir',str(d)]
 if test in ['tb_pcb_top','tb_pcb_config_deadline','tb_effect_cfg_replay']:cmd+=['--behavioral-pll']
 start=time.monotonic();v=subprocess.run(cmd,cwd=r,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=1800)
 (d/'runner.log').write_text(v.stdout+v.stderr,encoding='utf8');passed=v.returncode==0
 print(('PASS ' if passed else 'FAIL ')+test,flush=True)
 if not passed:print((v.stdout+v.stderr)[-2500:],flush=True)
 return dict(test=test,passed=passed,seconds=round(time.monotonic()-start,3))
with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(run,tests))
same=all(hashlib.sha256((r/f).read_bytes()).hexdigest()==h for f,h in manifest.items())
(out/'validation.json').write_text(json.dumps(dict(passed=all(v['passed'] for v in results) and same,sources_unchanged=same,results=results),indent=2),encoding='utf8')
raise SystemExit(0 if all(v['passed'] for v in results) and same else 1)
