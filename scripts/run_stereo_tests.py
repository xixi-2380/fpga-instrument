"""Pure HDL regression for stereo routing and reused automatic note IDs.
No Gowin tool, Programmer, generated bitstream, or hardware access.
"""
from pathlib import Path
import argparse,subprocess,xml.etree.ElementTree as ET,json,re,time,shutil
ap=argparse.ArgumentParser();ap.add_argument('--out-dir',required=True);ap.add_argument('--iverilog',default='iverilog');ap.add_argument('--vvp',default='vvp');ap.add_argument('--ivl-base');ap.add_argument('--test');a=ap.parse_args()
root=Path(__file__).resolve().parents[1];out=Path(a.out_dir).resolve();out.mkdir(parents=True,exist_ok=True)
sources=[root/x.get('path') for x in ET.parse(root/'keyboard_adsr.gprj').getroot().findall('./FileList/File') if x.get('type')=='file.verilog' and x.get('enable')=='1']
assert all(p.exists() for p in sources),'Missing GPRJ source'
sources=[x for x in sources if x.name!='pll_pair.sv']+[root/'sim/pll_pair_behavioral.sv',root/'sim/pixel_pll_behavioral.sv']
configs=[('allocator','tb_voice_allocator',{}),('tail_mono','tb_bt_tail_reuse',{'STEREO':0}),('tail_stereo','tb_bt_tail_reuse',{'STEREO':1}),('mono_math','tb_synth_core',{}),('i2s_words','tb_i2s_tx',{}),('numeric_stereo','tb_stereo_audio',{}),('event_cdc','tb_bt_event_cdc',{}),('player_production','tb_bt_player_production',{}),('bluetooth_protocol_audio','tb_bt_score_audio',{}),('bluetooth_uart_top','tb_bluetooth_top',{}),('manual_volume_release','tb_playback_regression',{}),('british_ui_stereo','tb_british_top',{}),('startup_stereo','tb_max98357_startup',{})]+[(f'stereo_effect_{e}','tb_bt_polyphony',{'STEREO':1,'EFFECT':e}) for e in range(3)]
if a.test:configs=[c for c in configs if c[0]==a.test or c[1]==a.test]
assert configs,'Unknown --test'
results=[]
for tag,top,params in configs:
 d=out/tag;d.mkdir(exist_ok=True);cmd=[a.iverilog]
 if a.ivl_base:cmd+=['-B',a.ivl_base]
 cmd+=['-g2012','-grelative-include','-Isim','-s',top,'-o',str(d/'test.vvp')]+[f'-P{top}.{k}={v}' for k,v in params.items()]+[str(x) for x in sources]+[str(root/f'sim/{top}.sv')]
 t=time.monotonic();c=subprocess.run(cmd,cwd=root,capture_output=True,text=True);(d/'compile.log').write_text(c.stdout+c.stderr)
 if c.returncode:raise SystemExit(c.stderr)
 with (d/'test.log').open('w') as f:r=subprocess.run([a.vvp,str(d/'test.vvp'),'+SIM_OUT_DIR='+str(d)],cwd=root,stdout=f,stderr=subprocess.STDOUT,timeout=900)
 s=(d/'test.log').read_text();m=re.search('PASS '+top+r' checks=(\d+)',s);ok=r.returncode==0 and bool(m)
 result={'test':top,'tag':tag,'parameters':params,'passed':ok,'checks':int(m[1]) if m else 0,'seconds':round(time.monotonic()-t,3),'pll':'explicit behavioral models, not vendor/STA'}
 (d/'result.json').write_text(json.dumps(result,indent=2)+'\n');results.append(result);print(s,flush=True)
 if not ok:break
summary={'passed':len(results)==len(configs) and all(x['passed'] for x in results),'tests':results,'checks':sum(x['checks'] for x in results),'not_run':['Gowin synthesis','P&R','STA','Programmer','hardware']}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');raise SystemExit(0 if summary['passed'] else 1)
