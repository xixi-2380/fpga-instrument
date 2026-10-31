"""Portable Icarus regression for frame-locked display snapshots.
Use --project to point at the production checkout containing src/ and ROMs.
No files under the project are modified. --skip-display runs only bridge tests.
"""
from pathlib import Path
import argparse,subprocess,os,json,re
p=argparse.ArgumentParser();p.add_argument('--project',type=Path,required=True);p.add_argument('--iverilog-dir',type=Path,required=True);p.add_argument('--out-dir',type=Path,required=True);p.add_argument('--skip-display',action='store_true');a=p.parse_args()
r=a.project.resolve();b=a.iverilog_dir.resolve();o=a.out_dir.resolve();o.mkdir(parents=True,exist_ok=True);here=Path(__file__).resolve().parent
env=os.environ.copy();env['PATH']=str(b)+os.pathsep+env['PATH'];results=[]
def run(name,top,files,params=()):
 vvp=o/(name+'.vvp');cmd=[str(b/'iverilog.exe'),'-g2012','-grelative-include','-I'+(r/'sim').as_posix(),'-s',top,'-o',vvp.as_posix()]
 for key,value in params:cmd+=['-P',f'{top}.{key}={value}']
 cmd += [f.as_posix() for f in files]
 c=subprocess.run(cmd,capture_output=True,text=True,env=env,cwd=r);(o/(name+'_compile.log')).write_text(c.stdout+c.stderr)
 assert c.returncode==0,(name,c.stdout,c.stderr)
 v=subprocess.run([str(b/'vvp.exe'),vvp.as_posix()],capture_output=True,text=True,env=env,cwd=r,timeout=600);log=v.stdout+v.stderr;(o/(name+'.log')).write_text(log)
 assert v.returncode==0 and 'PASS' in log and 'FAIL' not in log,(name,log)
 count=re.search(r'checks=(\d+)',log)
 results.append(dict(name=name,checks=int(count[1]) if count else None,passed=True));print(log.splitlines()[0],flush=True)
for reset,width,sc,pc in [(0,20,3,11),(1,20,3,11),(0,1208,17,5),(1,1208,17,5),(0,2592,7,11),(1,2592,7,11)]:
 run(f'frame_r{reset}_w{width}_s{sc}_p{pc}','tb_rgb_frame_status_cdc',[r/'src/rgb_status_cdc.sv',r/'src/reset_sync.sv',r/'sim/tb_rgb_frame_status_cdc.sv'],[('RESET_PAYLOAD',reset),('WIDTH',width),('SOURCE_HALF',sc),('PIXEL_HALF',pc)])
if not a.skip_display:
 for locked in [0,1]:
  run(f'display_locked{locked}','tb_rgb_display',[r/'src/rgb_status_cdc.sv',r/'src/rgb_display.sv',r/'src/rgb_ui_renderer.sv',r/'src/reset_sync.sv',r/'src/rgb_scan_timing.sv',r/'src/audio_visualizer.sv',r/'sim/pixel_pll_behavioral.sv',r/'sim/io_behavioral.sv',r/'sim'/('tb_rgb_display_frame_locked.sv' if locked else 'tb_rgb_display_frame_legacy.sv')])
(o/'validation.json').write_text(json.dumps(dict(tests=results,behavioral_pll=True,hardware_validation=False,gowin_sta=False),indent=2))
