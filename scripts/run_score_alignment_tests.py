"""Exhaustive length predicate and both legacy/extended command regressions."""
from pathlib import Path
import argparse,subprocess,os,json,xml.etree.ElementTree as ET,hashlib,re
p=argparse.ArgumentParser();p.add_argument('--tool-bin',type=Path,required=True);p.add_argument('--out-dir',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parents[1];o=a.out_dir.resolve();o.mkdir(parents=True,exist_ok=True);b=a.tool_bin.resolve();env=os.environ.copy();env['PATH']=str(b)+os.pathsep+env['PATH'];results=[]
sources=[r/f.get('path') for f in ET.parse(r/'keyboard_adsr.gprj').getroot().findall('./FileList/File') if f.get('type')=='file.verilog' and f.get('enable')=='1']
try:
 for top,tb in [('tb_score_length_alignment','structural/tb_score_length_alignment.sv'),('tb_bluetooth_score_core','tb_bluetooth_score_core.sv'),('tb_midi_protocol','tb_midi_protocol.sv')]:
  files=sources+[r/'sim'/tb];hashes={str(f.relative_to(r)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
  cmd=[str(b/'iverilog.exe'),'-g2012','-Wall','-grelative-include','-I'+(r/'sim').as_posix(),'-s',top,'-o',(o/(top+'.vvp')).as_posix()]+[f.as_posix() for f in files]
  c=subprocess.run(cmd,cwd=r,env=env,capture_output=True,text=True,encoding='utf-8');(o/(top+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf-8');assert c.returncode==0,c.stderr
  v=subprocess.run([str(b/'vvp.exe'),(o/(top+'.vvp')).as_posix()],cwd=r,env=env,capture_output=True,text=True,encoding='utf-8',timeout=600);log=v.stdout+v.stderr;(o/(top+'.log')).write_text(log,encoding='utf-8');assert v.returncode==0 and 'PASS '+top in log,log
  assert all(hashlib.sha256((r/n).read_bytes()).hexdigest()==h for n,h in hashes.items()),'source changed'
  count=re.search(r'checks=(\d+)',log);results.append(dict(name=top,passed=True,checks=int(count[1]) if count else None,command=cmd,source_sha256=hashes,output=log));print(log.splitlines()[0],flush=True)
finally:(o/'validation.json').write_text(json.dumps(dict(tests=results,total_checks=sum(t['checks'] or 0 for t in results)),indent=2),encoding='utf-8')
