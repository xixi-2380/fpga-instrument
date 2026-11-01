"""Focused RTL dynamic checks for structural optimization. No EDA or programming.
Requires Icarus Verilog; pass --tool-bin explicitly if not on PATH.
The frozen reference modules are from commit94030a and are simulation-only.
"""
import argparse,hashlib,itertools,json,os,pathlib,re,shutil,subprocess,sys
p=argparse.ArgumentParser();p.add_argument('--root',type=pathlib.Path);p.add_argument('--tool-bin',type=pathlib.Path);p.add_argument('--out-dir',type=pathlib.Path,default=pathlib.Path('reports/structural_optimization/dynamic'));p.add_argument('--suite',choices=['all','cdc','visualizer','limiter','pcb','renderer','frame-visibility','sustain'],default='all');a=p.parse_args()
root=(a.root or pathlib.Path(__file__).resolve().parents[1]).resolve();out=a.out_dir
if not out.is_absolute():out=root/out
out.mkdir(parents=True,exist_ok=True)
env=os.environ.copy()
if a.tool_bin:env['PATH']=str(a.tool_bin.resolve())+os.pathsep+env['PATH']
iv=str((a.tool_bin/'iverilog.exe').resolve()) if a.tool_bin else shutil.which('iverilog');vv=str((a.tool_bin/'vvp.exe').resolve()) if a.tool_bin else shutil.which('vvp')
assert iv and vv,'Icarus Verilog and vvp required'
results=[]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def run(name,top,sources,tb,params=None,args=None,timeout=180):
 sources=[root/'src'/s for s in sources]+[root/'sim'/s for s in tb]
 binary=out/(name+'.vvp');cmd=[iv,'-g2012','-Wall','-grelative-include','-I'+(root/'sim').as_posix(),'-s',top,'-o',str(binary)]
 for key,value in (params or {}).items():cmd+=['-P'+top+'.'+key+'='+str(value)]
 cmd += [s.as_posix() for s in sources]
 before={str(s.relative_to(root)):sha(s) for s in sources}
 compile_result=subprocess.run(cmd,cwd=root,env=env,text=True,capture_output=True)
 (out/(name+'_compile.log')).write_text(compile_result.stdout+compile_result.stderr,encoding='utf-8')
 assert compile_result.returncode==0,compile_result.stderr
 run_cmd=[vv,str(binary),'+SIM_OUT_DIR='+out.as_posix()]+(args or [])
 result=subprocess.run(run_cmd,cwd=root,env=env,text=True,capture_output=True,timeout=timeout)
 text=result.stdout+result.stderr;(out/(name+'.log')).write_text(text,encoding='utf-8')
 assert result.returncode==0 and 'PASS '+top in text,text
 assert all(sha(root/s)==h for s,h in before.items()),'Source changed during simulation'
 match=re.search(r'checks=(\d+)',text)
 results.append(dict(name=name,top=top,checks=int(match[1]) if match else None,compile_command=cmd,run_command=run_cmd,source_sha256=before,output=text))
 print(text,flush=True)
try:
 if a.suite in ['all','cdc']:
  run('cdc_legacy','tb_rgb_status_cdc',['reset_sync.sv','rgb_status_cdc.sv'],['tb_rgb_status_cdc.sv'])
  for width,mode,(sh,ph) in itertools.product([20,1208,2592],[0,1],[(7,11),(13,3),(5,5)]):
   run(f'cdc_w{width}_r{mode}_s{sh}_p{ph}','tb_rgb_status_cdc_reset_payload',['reset_sync.sv','rgb_status_cdc.sv'],['reference_rgb_status_cdc_94030a.sv','structural/tb_rgb_status_cdc_reset_payload.sv'],dict(WIDTH=width,RESET_PAYLOAD=mode,SOURCE_HALF=sh,PIXEL_HALF=ph))
 if a.suite in ['all','visualizer']:
  run('visualizer_compare','tb_audio_visualizer_compare',['audio_visualizer.sv'],['reference_audio_visualizer_94030a.sv','structural/tb_audio_visualizer_compare.sv'])
 if a.suite in ['all','limiter']:
  for fixed,hold in [(0,0),(1,0),(1,240)]:
   vecdir=out/f'limiter_vectors_hold{hold}';vecdir.mkdir(exist_ok=True)
   subprocess.run([sys.executable,str(root/'scripts/reference_audio_limiter.py'),'--out-dir',str(vecdir),'--hold-samples',str(hold)],cwd=root,env=env,check=True)
   run(f'limiter_fixed{fixed}_hold{hold}','tb_audio_limiter',['audio_limiter.sv'],['tb_audio_limiter.sv'],dict(FIXED=fixed,HOLD=hold),['+LIMITER_VECTORS='+(vecdir/'limiter_vectors.hex').as_posix()])
 if a.suite in ['all','pcb']:
  for top in ['tb_pcb_readable','tb_pcb_debug_ui']:
   run(top,top,['pcb_debug_ui.sv'],[top+'.sv'])
 if a.suite in ['all','frame-visibility']:
  for mode in [0,1]:
   run(f'frame_visibility_{mode}','tb_rgb_display_frame_visibility',['rgb_display.sv','rgb_ui_renderer.sv','rgb_status_cdc.sv','reset_sync.sv','audio_visualizer.sv','rgb_scan_timing.sv'],['pixel_pll_behavioral.sv','io_behavioral.sv','structural/tb_rgb_display_frame_visibility.sv'],dict(FRAME_LOCKED=mode))
 if a.suite in ['all','sustain']:
  run('sustain_slew_equivalence','tb_sustain_slew_equivalence',['sustain_envelope.sv'],['reference_sustain_envelope_94030a.sv','structural/tb_sustain_slew_equivalence.sv'])
 if a.suite in ['all','renderer']:
  run('pcb_renderer','tb_pcb_renderer',['pcb_debug_ui.sv','rgb_ui_renderer.sv'],['tb_pcb_renderer.sv'],timeout=600)
  run('rgb_ui_renderer','tb_rgb_ui_renderer',['rgb_ui_renderer.sv'],['tb_rgb_ui_renderer.sv'],timeout=600)
finally:
 (out/'results.json').write_text(json.dumps(dict(tests=results,total_checks=sum(t['checks'] or 0 for t in results),tool=iv),indent=2),encoding='utf-8')
