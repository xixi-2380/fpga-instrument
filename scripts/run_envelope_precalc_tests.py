"""Shared envelope preparation: exhaustive arithmetic and frozen-baseline comparison.
No EDA or programming. Production input clocks and audio sample timing are retained.
"""
from pathlib import Path
import argparse,subprocess,os,json,re,hashlib,xml.etree.ElementTree as ET,time
p=argparse.ArgumentParser();p.add_argument('--tool-bin',type=Path,required=True);p.add_argument('--out-dir',type=Path,required=True);p.add_argument('--suite',choices=['all','arithmetic','envelopes','core','legacy','compile','sustain'],default='all');a=p.parse_args()
r=Path(__file__).resolve().parents[1];b=a.tool_bin.resolve();o=a.out_dir.resolve();o.mkdir(parents=True,exist_ok=True);env=os.environ.copy();env['PATH']=str(b)+os.pathsep+env['PATH'];results=[]
def run(name,top,files,parameters=None,execute=True):
 files=[r/f for f in files];hashes={str(f.relative_to(r)) if f.is_relative_to(r) else str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in files};start=time.monotonic()
 cmd=[str(b/'iverilog.exe'),'-g2012','-Wall','-grelative-include','-I'+(r/'sim').as_posix(),'-s',top,'-o',(o/(name+'.vvp')).as_posix()]
 for key,value in (parameters or {}).items():cmd+=['-P',top+'.'+key+'='+str(value)]
 cmd += [f.as_posix() for f in files]
 c=subprocess.run(cmd,cwd=r,env=env,capture_output=True,text=True,encoding='utf-8');(o/(name+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf-8');assert c.returncode==0,c.stderr
 log='compile-only';checks=0
 if execute:
  v=subprocess.run([str(b/'vvp.exe'),(o/(name+'.vvp')).as_posix(),'+SIM_OUT_DIR='+o.as_posix()],cwd=r,env=env,capture_output=True,text=True,encoding='utf-8',timeout=900);log=v.stdout+v.stderr;(o/(name+'.log')).write_text(log,encoding='utf-8');assert v.returncode==0 and 'PASS '+top in log and 'FAIL' not in log,log
  m=re.search(r'checks=(\d+)',log);checks=int(m[1]) if m else None
 assert all(hashlib.sha256(f.read_bytes()).hexdigest()==hashes[str(f.relative_to(r)) if f.is_relative_to(r) else str(f)] for f in files),'Inputs changed'
 results.append(dict(name=name,passed=True,checks=checks,parameters=parameters or {},executed=execute,seconds=round(time.monotonic()-start,3),compile_command=cmd,source_sha256=hashes,output=log));print(log.splitlines()[0] if execute else name+' compiled',flush=True)
try:
 if a.suite in ['all','sustain']:
  run('sustain_carry','tb_sustain_carry_equivalence',['src/sustain_envelope.sv','sim/reference_sustain_envelope_57b3db2.sv','sim/structural/tb_sustain_carry_equivalence.sv'])
 if a.suite in ['all','arithmetic']:
  run('bank_arithmetic','tb_precalc_bank_arithmetic',['src/envelope_precalc_bank.sv','sim/structural/tb_precalc_bank_arithmetic.sv'])
 if a.suite in ['all','envelopes']:
  common=['src/adsr_envelope.sv','src/instrument_envelope.sv','src/envelope_precalc_bank.sv','sim/reference_adsr_envelope_57b3db2.sv','sim/reference_instrument_envelope_57b3db2.sv','sim/structural/tb_shared_envelope_precalc.sv']
  for name,params in [('default',{}),('small',dict(ATTACK=7,DECAY=11,RELEASE=13)),('single',dict(VOICES=1,INTERVAL=6,FRAMES=3000)),('production_interval',dict(INTERVAL=1280,FRAMES=200))]:run(name,'tb_shared_envelope_precalc',common,params)
 sources=[f.get('path') for f in ET.parse(r/'keyboard_adsr.gprj').getroot().findall('./FileList/File') if f.get('type')=='file.verilog' and f.get('enable')=='1']
 if a.suite in ['all','core']:
  common=sources+['sim/reference_adsr_envelope_57b3db2.sv','sim/reference_instrument_envelope_57b3db2.sv','sim/reference_synth_core_57b3db2.sv','sim/structural/tb_synth_precalc_compare.sv']
  for enable in [0,1]:run('core_output'+str(enable),'tb_synth_precalc_compare',common,dict(OUTPUT_ENABLE=enable))
 if a.suite in ['all','legacy']:
  for name in ['tb_adsr_envelope','tb_adsr_production','tb_instrument_envelopes','tb_score_articulation']:run(name,name,sources+['sim/'+name+'.sv'])
 if a.suite in ['all','compile']:
  run('actual_top_vendor_compile','keyboard_top',sources+['C:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v'],execute=False)
finally:
 (o/'validation.json').write_text(json.dumps(dict(tests=results,total_checks=sum(t['checks'] or 0 for t in results),hardware_programmed=False,sta_passed=False),indent=2),encoding='utf-8')
