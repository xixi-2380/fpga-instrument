import argparse, pathlib, subprocess, os, json, time
p=argparse.ArgumentParser();p.add_argument('--test');p.add_argument('--vendor',action='store_true');p.add_argument('--out-dir',default='reports/sim');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];os.chdir(root)
bin=root/'tools/mingw64/bin';env=os.environ.copy();env['PATH']=str(bin)+os.pathsep+env['PATH']
out=pathlib.Path(a.out_dir)
if not out.is_absolute():out=root/out
out.mkdir(parents=True,exist_ok=True)
sources=sorted(root.glob('rtl/*.sv'))+sorted(root.glob('boards/mega138k_pro/*.sv'))
tests=sorted(root.glob('sim/tb_*.sv'))
if a.test:tests=[t for t in tests if t.stem==a.test]
elif not a.vendor:tests=[t for t in tests if t.stem not in ['tb_pll_pair','tb_tone_top','tb_bringup_digital','tb_tone_play','tb_keyboard_top']]
assert tests,'No matching testbench'
results=[]
for t in tests:
    name=t.stem;print('RUN',name,flush=True);start=time.monotonic()
    cmd=[str(bin/'iverilog.exe'),'-g2012','-Wall','-Iconfig','-Isim','-s',name,'-o',str(out/(name+'.vvp'))]+[str(s) for s in sources]+[str(t)]
    if name in ['tb_pll_pair','tb_tone_top','tb_bringup_digital','tb_tone_play','tb_keyboard_top']:cmd+=['C:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v']
    c=subprocess.run(cmd,capture_output=True,text=True,encoding='utf8',errors='replace',env=env)
    (out/(name+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf8')
    if c.returncode: print('compile exit',c.returncode,c.stdout+c.stderr);raise SystemExit(1)
    run=subprocess.run([str(bin/'vvp.exe'),str(out/(name+'.vvp'))],capture_output=True,text=True,encoding='utf8',errors='replace',env=env,timeout=600)
    (out/(name+'.log')).write_text(run.stdout+run.stderr,encoding='utf8')
    print(run.stdout,flush=True)
    ok=run.returncode==0 and 'PASS '+name in run.stdout
    results.append(dict(test=name,passed=ok,seconds=round(time.monotonic()-start,3)))
    if not ok: print(run.stderr);break
(out/('summary_'+(a.test or ('vendor' if a.vendor else 'rtl'))+'.json')).write_text(json.dumps(results,indent=2),encoding='utf8')
raise SystemExit(0 if all(x['passed'] for x in results) else 1)
