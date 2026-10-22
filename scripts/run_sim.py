import sys, argparse, pathlib, subprocess, os, json, time, xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--test');p.add_argument('--param',action='append',default=[]);p.add_argument('--vendor',action='store_true');p.add_argument('--behavioral-pll',action='store_true',help='Test-only clock substitute; not official PLL or STA validation');p.add_argument('--out-dir',default='reports/sim/current');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];os.chdir(root)
bin=root/'tools/mingw64/bin';env=os.environ.copy();env['PATH']=str(bin)+os.pathsep+env['PATH']
out=pathlib.Path(a.out_dir)
if not out.is_absolute():out=root/out
out.mkdir(parents=True,exist_ok=True)
sources=[root/f.get('path') for f in ET.parse(root/'keyboard_adsr.gprj').getroot().findall('./FileList/File') if f.get('type')=='file.verilog' and f.get('enable')=='1']
assert sources and all(s.is_file() for s in sources),'Missing enabled project source'
tests=sorted(root.glob('sim/tb_*.sv'))
if a.test:tests=[t for t in tests if t.stem==a.test]
elif not a.vendor:tests=[t for t in tests if t.stem not in ['tb_pll_pair','tb_keyboard_top','tb_score_audio','tb_score_effects','tb_effect_button_path']]
assert tests,'No matching testbench'
assert not a.param or a.test,'--param requires --test'
for override in a.param:
    key,sep,value=override.partition('=')
    assert sep and key.isidentifier() and value.lstrip('-').isdigit(),'Use --param NAME=INTEGER'
assert not (a.vendor and a.behavioral_pll),'Choose official vendor or behavioral PLL, not both'
if a.behavioral_pll:
    assert a.test and a.test!='tb_pll_pair','Behavioral substitute requires one integration test, not a PLL test'
    sources=[s for s in sources if s.name!='pll_pair.sv']+[root/'sim/pll_pair_behavioral.sv']
results=[]
for t in tests:
    name=t.stem
    extra_args=[]
    if name=='tb_audio_effects':
        vector_file=out/'effects_vectors.hex'
        generator=[sys.executable,str(root/'scripts/reference_effects.py'),'--output',str(vector_file)]
        if any(x.startswith('PROD=') and int(x.split('=',1)[1])!=0 for x in a.param):generator+=['--production']
        subprocess.run(generator,check=True,env=env)
        extra_args=['+EFFECT_VECTORS='+vector_file.as_posix()]
    print('RUN',name,flush=True);start=time.monotonic()
    cmd=[str(bin/'iverilog.exe'),'-g2012','-Wall','-grelative-include','-Isim','-s',name,'-o',str(out/(name+'.vvp'))]+[s.as_posix() for s in sources]+[t.as_posix()]
    for override in a.param:cmd[1:1]=['-P',name+'.'+override]
    if not a.behavioral_pll and name in ['tb_pll_pair','tb_keyboard_top','tb_score_audio','tb_score_effects','tb_effect_button_path']:cmd+=['C:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v']
    c=subprocess.run(cmd,capture_output=True,text=True,encoding='utf8',errors='replace',env=env)
    (out/(name+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf8')
    if c.returncode: print('compile exit',c.returncode,c.stdout+c.stderr);raise SystemExit(1)
    run=subprocess.run([str(bin/'vvp.exe'),str(out/(name+'.vvp')),'+SIM_OUT_DIR='+out.as_posix()]+extra_args,capture_output=True,text=True,encoding='utf8',errors='replace',env=env,timeout=600)
    (out/(name+'.log')).write_text(run.stdout+run.stderr,encoding='utf8')
    print(run.stdout,flush=True)
    ok=run.returncode==0 and 'PASS '+name in run.stdout
    results.append(dict(test=name,passed=ok,pll_model=('behavioral substitute' if a.behavioral_pll else 'project/vendor when required'),seconds=round(time.monotonic()-start,3)))
    if not ok: print(run.stderr);break
(out/('summary_'+(a.test or ('vendor' if a.vendor else 'rtl'))+'.json')).write_text(json.dumps(results,indent=2),encoding='utf8')
raise SystemExit(0 if all(x['passed'] for x in results) else 1)
