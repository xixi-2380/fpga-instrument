"""Java-only checks; no Android SDK, radio, or FPGA required."""
from pathlib import Path
import argparse,subprocess,shutil,json
p=argparse.ArgumentParser();p.add_argument('--out-dir',required=True);a=p.parse_args()
root=Path(__file__).resolve().parent;out=Path(a.out_dir).resolve();out.mkdir(parents=True,exist_ok=True)
classes=out/'classes';classes.mkdir(exist_ok=True)
sources=sorted((root/'app/src/main/java/cn/whu/gaoshan/core').glob('*.java'))+sorted((root/'tests').rglob('*.java'))
javac=shutil.which('javac');compiler=[javac] if javac else ['java','-m','jdk.compiler/com.sun.tools.javac.Main']
cmd=compiler+['-encoding','UTF-8','-d',str(classes)]+[str(s) for s in sources]
c=subprocess.run(cmd,capture_output=True,text=True);(out/'compile.log').write_text(c.stdout+c.stderr)
if c.returncode:raise SystemExit(c.stderr)
results=[]
for name in ['CoreTests','ConnectionTests','LibraryTests']:
 r=subprocess.run(['java','-cp',str(classes),'cn.whu.gaoshan.core.'+name,str(root/'examples')],capture_output=True,text=True,timeout=120)
 (out/(name+'.log')).write_text(r.stdout+r.stderr,encoding='utf-8');print(r.stdout+r.stderr)
 results.append({'test':name,'passed':r.returncode==0,'output':r.stdout})
(out/'summary.json').write_text(json.dumps({'passed':all(r['passed'] for r in results),'scope':'Java core and fake connection lifecycle; not Android/BT/FPGA','results':results},indent=2),encoding='utf-8')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
