"""Pure HDL only: byte protocol/player plus actual 8N1 link. No Gowin tools."""
import argparse,json,pathlib,subprocess,re
p=argparse.ArgumentParser();p.add_argument('--iverilog',default='iverilog');p.add_argument('--vvp',default='vvp');p.add_argument('--ivl-base');p.add_argument('--out-dir',required=True);a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];out=pathlib.Path(a.out_dir).resolve();out.mkdir(parents=True,exist_ok=True)
sources=['uart_rx','uart_tx','bt_frame_rx','bt_frame_tx','bt_score_player','score_validator','bluetooth_score_core','bluetooth_score_link']
configs=[('core_2','tb_bluetooth_score_core',{'VOICES':2}),('core_4','tb_bluetooth_score_core',{'VOICES':4}),('core_8','tb_bluetooth_score_core',{'VOICES':8}),('core_16','tb_bluetooth_score_core',{'VOICES':16}),('link_9600','tb_bluetooth_score_link',{'BAUD':9600}),('link_115200','tb_bluetooth_score_link',{'BAUD':115200,'CLOCK_HZ':5000000})]
results=[]
for name,top,params in configs:
 binary=out/(name+'.vvp');cmd=[a.iverilog,'-g2012','-Wall','-s',top,'-o',str(binary)]
 if a.ivl_base:cmd+=['-B',a.ivl_base]
 cmd += [f'-P{top}.{k}={v}' for k,v in params.items()]+[str(r/'src'/f'{s}.sv') for s in sources]+[str(r/'sim'/f'{top}.sv')]
 c=subprocess.run(cmd,text=True,capture_output=True);(out/(name+'_compile.log')).write_text(c.stdout+c.stderr)
 if c.returncode:raise SystemExit(c.stderr)
 run=subprocess.run([a.vvp,str(binary)],text=True,capture_output=True,timeout=180);(out/(name+'.log')).write_text(run.stdout+run.stderr)
 match=re.search(r'PASS '+top+r' checks=(\d+)',run.stdout);ok=run.returncode==0 and bool(match)
 results.append(dict(name=name,top=top,parameters=params,passed=ok,checks=int(match[1]) if match else 0,output=run.stdout));print(run.stdout+run.stderr,flush=True)
 if not ok:break
(out/'summary.json').write_text(json.dumps({'results':results,'all_passed':len(results)==len(configs) and all(x['passed'] for x in results),'total_checks':sum(x['checks'] for x in results),'scope':'HDL simulation only; no Gowin synthesis, timing, board, phone or audio verification'},indent=2))
raise SystemExit(0 if len(results)==len(configs) and all(x['passed'] for x in results) else 1)
