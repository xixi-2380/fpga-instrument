"""Pure HDL/software tests. Explicit clock/IO models; never Gowin/Programmer.
Portable runner using the real GPRJ. Save logs and frozen source hashes.
"""
from pathlib import Path
import argparse,subprocess,xml.etree.ElementTree as ET,json,time,hashlib,re
from reference_chorus import generate
p=argparse.ArgumentParser();p.add_argument('--out-dir',required=True,type=Path)
p.add_argument('--iverilog',default='iverilog');p.add_argument('--vvp',default='vvp');p.add_argument('--ivl-base');p.add_argument('--test',action='append');a=p.parse_args()
root=Path(__file__).resolve().parents[1];out=a.out_dir.resolve();out.mkdir(parents=True,exist_ok=True)
sources=[root/f.get('path') for f in ET.parse(root/'keyboard_adsr.gprj').getroot().findall('./FileList/File') if f.get('type')=='file.verilog' and f.get('enable')=='1']
assert all(f.is_file() for f in sources),'GPRJ dependency missing'
sources=[s for s in sources if s.name!='pll_pair.sv']+[root/'sim'/f for f in ('pll_pair_behavioral.sv','pixel_pll_behavioral.sv','io_behavioral.sv')]
configs=[('tb_performance_control',{}),('tb_manual_event_arbiter',{}),('tb_audio_chorus',{}),
 ('tb_performance_audio',{}),('tb_performance_top',{}),('tb_performance_ui',{}),
 ('tb_gt9110_touch',{}),('tb_i2c_register_master',{}),('tb_midi_protocol',{}),('tb_midi_audio',{}),('tb_midi_menu',{}),('tb_touch_keyboard_router',{}),
 ('tb_sustain_retrigger',{'TIMBRE':5}),('tb_bt_tail_reuse',{'STEREO':1}),('tb_stereo_audio',{}),
 ('tb_effect_cfg_replay',{}),('tb_pcb_readable',{}),('tb_ui_controls',{}),('tb_bt_polyphony',{'STEREO':1,'EFFECT':2})]
if a.test:configs=[c for c in configs if c[0] in a.test]
assert configs,'No matching test'
frozen_manifest={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for f in list((root/'src').rglob('*'))+[root/'keyboard_adsr.gprj'] if f.is_file()}
results=[]
for top,params in configs:
    d=out/top;d.mkdir(exist_ok=True);extra=[];model={}
    if top=='tb_audio_chorus':
        model=generate(d/'vectors.txt');extra=['+VECTORS='+str(d/'vectors.txt')]
    cmd=[a.iverilog]+(['-B',a.ivl_base] if a.ivl_base else [])+['-g2012','-grelative-include','-Isim','-s',top,'-o',str(d/'test.vvp')]
    cmd += [f'-P{top}.{k}={v}' for k,v in params.items()]+[str(f) for f in sources]+[str(root/'sim'/f'{top}.sv')]
    start=time.monotonic();c=subprocess.run(cmd,cwd=root,capture_output=True,text=True)
    (d/'compile.log').write_text(c.stdout+c.stderr)
    if c.returncode:
        result={'test':top,'passed':False,'stage':'compile'};results.append(result);print(c.stderr,flush=True);break
    try:
        with (d/'test.log').open('w') as f:v=subprocess.run([a.vvp,str(d/'test.vvp'),'+SIM_OUT_DIR='+str(d)]+extra,cwd=root,stdout=f,stderr=subprocess.STDOUT,timeout=900)
        s=(d/'test.log').read_text();m=re.search('PASS '+top+r' checks=(\d+)',s)
        ok=v.returncode==0 and bool(m)
        if ok and top=='tb_performance_audio':
            from reference_chorus import check_chain
            model=check_chain(d/'chorus_chain.txt');(d/'independent_chain.json').write_text(json.dumps(model,indent=2))
        result={'test':top,'parameters':params,'passed':ok,'checks':int(m[1]) if m else 0,'seconds':round(time.monotonic()-start,3),'independent_model':model}
        print(s[-2500:],flush=True)
    except subprocess.TimeoutExpired:
        result={'test':top,'passed':False,'stage':'timeout'}
    results.append(result);(d/'result.json').write_text(json.dumps(result,indent=2))
    if not result['passed']:break
manifest={str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for f in list((root/'src').rglob('*'))+[root/'keyboard_adsr.gprj'] if f.is_file()}
assert manifest==frozen_manifest,'Source changed during test run; results are not a frozen-source validation'
summary={'base_commit':'86711a306017598fa2f965e578fb04ca3bd9fe81','passed':len(results)==len(configs) and all(x['passed'] for x in results),'results':results,'source_sha256':manifest,'not_run':['Gowin synthesis','P&R','STA','hardware','touch-to-sound physical latency']}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');raise SystemExit(0 if summary['passed'] else 1)
