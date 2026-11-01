"""Filter bypass compatibility and final PCM/I2S/tag integration tests."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time

p=argparse.ArgumentParser();p.add_argument('--tool-bin',type=Path,required=True);p.add_argument('--out-dir',type=Path,required=True);p.add_argument('--suite',choices=['all','bypass','enabled','mute'],default='all');a=p.parse_args()
r=Path(__file__).resolve().parents[1];b=a.tool_bin.resolve();o=a.out_dir.resolve();o.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env['PATH']=str(b)+os.pathsep+env.get('PATH','')
names=['synth_core','audio_output_filter','dds_sine','instrument_envelope','adsr_envelope','sustain_envelope','envelope_precalc_bank','audio_timing','startup_envelope','voice_allocator','tone_gain','voice_mixer','audio_latency_meter','audio_limiter','master_volume','audio_effects','audio_delay','audio_reverb','audio_chorus','frame_buffer','i2s_tx']
sources=[r/'src'/(n+'.sv') for n in names]
results=[]
def run(name,top,tbs,parameters):
 files=sources+[r/'sim'/p for p in tbs]
 runtime=[r/'src/config/synth_config.svh',r/'src/config/sustain_curve.svh']
 for f in sources:
  runtime += [r/p for p in re.findall(r'\$readmemh\("([^"]+)"',f.read_text(encoding='utf-8'))]
 hashes={str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+runtime}
 command=[str(b/'iverilog.exe'),'-g2012','-Wall','-grelative-include','-I'+(r/'src').as_posix(),'-I'+(r/'sim').as_posix(),'-s',top,'-o',(o/(name+'.vvp')).as_posix()]
 command += ['-P'+top+'.'+key+'='+str(value) for key,value in parameters.items()]
 command += [p.as_posix() for p in files]
 start=time.monotonic();c=subprocess.run(command,cwd=r,env=env,capture_output=True,text=True,encoding='utf-8');(o/(name+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf-8');assert c.returncode==0,c.stderr
 v=subprocess.run([str(b/'vvp.exe'),(o/(name+'.vvp')).as_posix()],cwd=r,env=env,capture_output=True,text=True,encoding='utf-8',timeout=900)
 log=v.stdout+v.stderr;(o/(name+'.log')).write_text(log,encoding='utf-8');print(log,flush=True)
 assert v.returncode==0 and 'PASS '+top in log and 'FAIL' not in log,log
 assert all(hashlib.sha256((r/path).read_bytes()).hexdigest()==digest for path,digest in hashes.items()),'Inputs changed during simulation'
 results.append(dict(name=name,passed=True,parameters=parameters,checks=int(re.search(r'checks=(\d+)',log)[1]),seconds=round(time.monotonic()-start,3),source_sha256=hashes,output=log,command=command))
 (o/'validation.json').write_text(json.dumps(dict(tests=results,total_checks=sum(t['checks'] for t in results),hardware_programmed=False,gowin_run=False),indent=2)+'\n',encoding='utf-8')

if a.suite in ['all','bypass']:
 refs=['reference_adsr_envelope_57b3db2.sv','reference_instrument_envelope_57b3db2.sv','reference_synth_core_57b3db2.sv','structural/tb_synth_precalc_compare.sv']
 for enable in [0,1]:run('bypass_output'+str(enable),'tb_synth_precalc_compare',refs,dict(OUTPUT_ENABLE=enable))
if a.suite in ['all','enabled']:
 for enable,stereo in [(1,1),(0,1),(1,0)]:run('filtered_output'+str(enable)+'_stereo'+str(stereo),'tb_synth_output_filter',['tb_synth_output_filter.sv'],dict(OUTPUT_ENABLE=enable,STEREO=stereo))
if a.suite in ['all','mute']:
 for enable,stereo,voices in [(1,1,4),(0,1,4),(1,0,1)]:run('mute_output'+str(enable)+'_stereo'+str(stereo),'tb_synth_output_filter',['tb_synth_output_filter.sv'],dict(OUTPUT_ENABLE=enable,STEREO=stereo,MUTE_TEST=1,VOICES=voices))
