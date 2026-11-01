"""Focused arithmetic equivalence, invalid-payload isolation and actual-top compile.
Display tests use behavioral PLL/IO models; no physical timing or programming.
"""
from pathlib import Path
import argparse,subprocess,os,json,re,hashlib,xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--tool-bin',type=Path,required=True);p.add_argument('--out-dir',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parents[1];b=a.tool_bin.resolve();o=a.out_dir.resolve();o.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env['PATH']=str(b)+os.pathsep+env['PATH'];results=[]
def run(name,top,files,execute=True):
 files=[r/f for f in files];hashes={str(f.relative_to(r)) if f.is_relative_to(r) else str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
 cmd=[str(b/'iverilog.exe'),'-g2012','-Wall','-grelative-include','-I'+(r/'sim').as_posix(),'-s',top,'-o',(o/(name+'.vvp')).as_posix()]+[f.as_posix() for f in files]
 c=subprocess.run(cmd,capture_output=True,text=True,encoding='utf-8',env=env,cwd=r);(o/(name+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf-8');assert c.returncode==0,c.stderr
 log='compile-only';checks=0
 if execute:
  v=subprocess.run([str(b/'vvp.exe'),(o/(name+'.vvp')).as_posix(),'+SIM_OUT_DIR='+o.as_posix()],capture_output=True,text=True,encoding='utf-8',env=env,cwd=r,timeout=600);log=v.stdout+v.stderr
  (o/(name+'.log')).write_text(log,encoding='utf-8');assert v.returncode==0 and 'PASS' in log and 'FAIL' not in log,log
  match=re.search(r'checks=(\d+)',log);checks=int(match[1]) if match else None
 assert all(hashlib.sha256(f.read_bytes()).hexdigest()==hashes[str(f.relative_to(r)) if f.is_relative_to(r) else str(f)] for f in files),'Inputs changed'
 results.append(dict(name=name,passed=True,checks=checks,executed=execute,source_sha256=hashes,compile_command=cmd,output=log));print(name,log.splitlines()[0],flush=True)
try:
 run('bend_exhaustive','tb_bend_width_exhaustive',['sim/structural/tb_bend_width_exhaustive.sv'])
 run('bend_equivalence','tb_bend_width_equivalence',['src/performance_control.sv','sim/reference_performance_control_57b3db2.sv','sim/structural/tb_bend_width_equivalence.sv'])
 run('performance_legacy','tb_performance_control',['src/performance_control.sv','sim/tb_performance_control.sv'])
 common=['src/rgb_status_cdc.sv','src/rgb_display.sv','src/rgb_ui_renderer.sv','src/reset_sync.sv','src/rgb_scan_timing.sv','src/audio_visualizer.sv','sim/pixel_pll_behavioral.sv','sim/io_behavioral.sv']
 run('invalid_payload_mask','tb_rgb_display_frame_mask',common+['sim/structural/tb_rgb_display_frame_mask.sv'])
 for mode in ['legacy','locked']:run('display_'+mode,'tb_rgb_display',common+['sim/structural/tb_rgb_display_frame_'+mode+'.sv'])
 sources=[f.get('path') for f in ET.parse(r/'keyboard_adsr.gprj').getroot().findall('./FileList/File') if f.get('type')=='file.verilog' and f.get('enable')=='1']
 run('actual_top_vendor_compile','keyboard_top',sources+['C:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v'],execute=False)
finally:
 (o/'validation.json').write_text(json.dumps(dict(tests=results,total_checks=sum(t['checks'] or 0 for t in results),hardware_programmed=False,sta_passed=False),indent=2),encoding='utf-8')
