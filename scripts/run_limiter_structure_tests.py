"""Limiter structure: frozen RTL comparisons, no hardware or EDA side effects."""
from pathlib import Path
import argparse,subprocess,os,json,re,hashlib,time
p=argparse.ArgumentParser();p.add_argument('--tool-bin',type=Path,required=True);p.add_argument('--out-dir',type=Path,required=True);p.add_argument('--suite',choices=['all','output','stream','release'],default='all');a=p.parse_args()
r=Path(__file__).resolve().parents[1];b=a.tool_bin.resolve();o=a.out_dir.resolve();o.mkdir(parents=True,exist_ok=True)
env=os.environ.copy();env['PATH']=str(b)+os.pathsep+env['PATH'];results=[];tests=[]
if a.suite in ['all','output']:
 for c in [1,29204,32767]:tests.append(('tb_limiter_output_equivalence',dict(CEILING=c)))
if a.suite in ['all','stream']:
 for conf in [(0,0,1,2),(0,48,24,6),(1,0,32,6),(1,48,24,6)]:tests.append(('tb_limiter_stream_equivalence',dict(zip(['FIXED','HOLD','PRE_GAIN','WINDOW_LOG2'],conf))))
if a.suite in ['all','release']:tests.append(('tb_limiter_release_bounds',{}))
for name,params in tests:
 stem=name+'_'+'_'.join(str(v) for v in params.values());names=['src/audio_limiter.sv','sim/reference_audio_limiter_c6352fa.sv','sim/structural/'+name+'.sv'];files=[r/n for n in names]
 hashes={n:hashlib.sha256((r/n).read_bytes()).hexdigest() for n in names};start=time.monotonic()
 cmd=[str(b/'iverilog.exe'),'-g2012','-s',name,'-o',str(o/(stem+'.vvp'))]+['-P'+name+'.'+k+'='+str(v) for k,v in params.items()]+[str(f) for f in files]
 cc=subprocess.run(cmd,cwd=r,env=env,capture_output=True,text=True,encoding='utf-8');(o/(stem+'_compile.log')).write_text(cc.stdout+cc.stderr,encoding='utf-8');assert cc.returncode==0,cc.stderr
 v=subprocess.run([str(b/'vvp.exe'),str(o/(stem+'.vvp'))],cwd=r,env=env,capture_output=True,text=True,encoding='utf-8',timeout=300)
 log=v.stdout+v.stderr;(o/(stem+'.log')).write_text(log,encoding='utf-8');assert v.returncode==0 and 'PASS '+name in log,log
 assert all(hashlib.sha256((r/n).read_bytes()).hexdigest()==h for n,h in hashes.items()),'Inputs changed during simulation'
 results.append(dict(name=name,parameters=params,checks=int(re.search(r'checks=(\d+)',log)[1]),passed=True,seconds=round(time.monotonic()-start,3),source_sha256=hashes,command=cmd,output=log))
 (o/'validation.json').write_text(json.dumps(dict(tests=results,total_checks=sum(t['checks'] for t in results),hardware_programmed=False,sta_passed=False),indent=2),encoding='utf-8')
 print(log.splitlines()[0],flush=True)
