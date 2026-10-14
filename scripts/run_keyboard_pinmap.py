"""Simulate physical switch connections using CST pad mapping; no EDA build."""
from pathlib import Path
import subprocess,os,re,json,argparse
r=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--out-dir',default='reports/keyboard/pinmap_correction');args=parser.parse_args()
out=Path(args.out_dir)
if not out.is_absolute():out=r/out
out.mkdir(parents=True,exist_ok=True)
pad_names=['W26','L22','Y26','AA25','W25','M24','Y25','AA24']
bin=r/'tools/mingw64/bin';env=os.environ.copy();env['PATH']=str(bin)+os.pathsep+env['PATH']
results=[]
for variant,cst,transposed in [('corrected',r/'boards/mega138k_pro/keyboard.cst',0),('previous',r/'reports/keyboard/pinmap_correction/previous_keyboard.cst',1)]:
 text=cst.read_text(encoding='utf8')
 mapping={port:ball for port,ball in re.findall(r'IO_LOC "([^"]+)" ([A-Z]+\d+);',text)}
 folder=out/variant;folder.mkdir(exist_ok=True)
 header=[f'`define PINMAP_TRANSPOSED {transposed}']
 for i in range(4):
  row=mapping[f'key_row[{i}]'];col=mapping[f'key_col[{i}]']
  assert re.search(r'IO_PORT "key_row\['+str(i)+r'\]"[^;]*PULL_MODE=UP',text)
  header += [f'tran row_pad_{i}(port_rows[{i}],pads[{pad_names.index(row)}]);',
             f'pullup row_pullup_{i}(port_rows[{i}]);',
             f'tran col_pad_{i}(port_cols[{i}],pads[{pad_names.index(col)}]);']
 (folder/'keypad_pad_wiring.svh').write_text('\n'.join(header)+'\n',encoding='utf8')
 sources=sorted(r.glob('rtl/*.sv'))+sorted(r.glob('boards/mega138k_pro/*.sv'))
 cmd=[str(bin/'iverilog.exe'),'-g2012','-Iconfig','-I'+str(folder),'-s','tb_keyboard_pinmap','-o',str(folder/'test.vvp')]+[str(p) for p in sources]+[
   'C:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v',str(r/'sim/pinmap_keyboard_tb.v')]
 c=subprocess.run(cmd,cwd=r,env=env,capture_output=True,text=True,encoding='utf8',errors='replace')
 (folder/'compile.log').write_text(c.stdout+c.stderr,encoding='utf8')
 if c.returncode:print(c.stdout+c.stderr);raise SystemExit(1)
 p=subprocess.run([str(bin/'vvp.exe'),str(folder/'test.vvp')],cwd=r,env=env,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=120)
 log=p.stdout+p.stderr;(folder/'result.log').write_text(log,encoding='utf8');print(variant,log,flush=True)
 ok=p.returncode==0 and 'PASS tb_keyboard_pinmap' in log
 results.append(dict(variant=variant,passed=ok,transposed=bool(transposed)))
 if not ok:raise SystemExit(1)
(out/'status.json').write_text(json.dumps(dict(tests=results,clock_reset_bypassed=True,hardware_verified=False),indent=2)+'\n',encoding='utf8')
