"""Pure software/HDL checks for key mapping and recording. No EDA or hardware.
Requires JDK, Python and the simulator listed in tools/manifest.json.
Integration PLL/IO models are explicit behavioral substitutes, not STA evidence.
"""
from pathlib import Path
import subprocess,sys,argparse,json,time,hashlib
p=argparse.ArgumentParser();p.add_argument('--out-dir',required=True);p.add_argument('--quick',action='store_true',help='Feature tests only, omit the existing integration regression');a=p.parse_args()
r=Path(__file__).resolve().parents[1];out=Path(a.out_dir).resolve();out.mkdir(parents=True,exist_ok=True);results=[]
def run(name,args):
 start=time.monotonic();v=subprocess.run(args,cwd=r,capture_output=True,text=True,encoding='utf-8',errors='replace');(out/(name+'.log')).write_text(v.stdout+v.stderr,encoding='utf-8');item={'test':name,'passed':v.returncode==0,'seconds':round(time.monotonic()-start,3)};results.append(item);print(item,flush=True)
 if v.returncode:raise RuntimeError(v.stdout+v.stderr)
run('java',[sys.executable,'android/run_core_tests.py','--out-dir',str(out/'java')])
cases=[('tb_keymap_events',[]),('tb_performance',[]),('tb_keymap_flash',[]),('tb_keymap_wire',[]),('tb_keymap_wire',['HALF=4','VENDOR=1']),('tb_performance_top',[]),('tb_performance_menu',[])]
if not a.quick:
 cases += [(n,[]) for n in ['tb_key_note_events','tb_bluetooth_score_core','tb_midi_protocol','tb_midi_flash','tb_voice_allocator','tb_multitimbral','tb_synth_core','tb_ui_controls','tb_ui_inputs','tb_rgb_ui_renderer','tb_midi_menu','tb_pcb_top','tb_pcb_readable','tb_pcb_repeat','tb_bt_polyphony','tb_bt_player_production','tb_stereo_audio','tb_effect_cfg_replay','tb_bt_identity','tb_bt_tail_reuse','tb_touch_keyboard_router','tb_touch_ec11_top','tb_bt_event_cdc','tb_rgb_status_cdc','tb_sustain_envelope','tb_ui_more','tb_dds_sine','tb_timbres','tb_instrument_envelopes']]
 cases += [('tb_sustain_retrigger',['TIMBRE='+str(t)]) for t in [0,4,6,9,15]]
for name,params in cases:
 label=name+('_'+'_'.join(params).replace('=','') if params else '');cmd=[sys.executable,'scripts/run_sim.py','--test',name,'--behavioral-pll','--out-dir',str(out/label)]
 for param in params:cmd+=['--param',param]
 run(label,cmd)
manifest={f.relative_to(r).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for folder in ['src','android/app/src'] for f in (r/folder).rglob('*') if f.is_file()}
(out/'validation.json').write_text(json.dumps({'passed':True,'base_commit':'86711a306017598fa2f965e578fb04ca3bd9fe81','scope':'software/RTL only; no STA, phone/radio or hardware programming','results':results,'sha256':manifest},indent=2),encoding='utf-8')
