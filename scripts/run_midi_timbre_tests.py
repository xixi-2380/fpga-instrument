"""Pure Java/HDL verification. No EDA, hardware programming or Flash writes.
Requires bundled tools/mingw64 simulator and JDK. Behavioral clock/IO models
are explicitly selected for integration tests and do not establish STA.
"""
from pathlib import Path
import argparse,subprocess,sys,json,time,hashlib
p=argparse.ArgumentParser();p.add_argument('--out-dir',required=True);p.add_argument('--production-full-flash',action='store_true',help='Also run slow 4096-record production1MHz configuration (may take hours)');a=p.parse_args()
r=Path(__file__).resolve().parents[1];out=Path(a.out_dir).resolve();out.mkdir(parents=True,exist_ok=True);results=[]
def run(name,cmd):
 start=time.monotonic();v=subprocess.run(cmd,cwd=r,capture_output=True,text=True,encoding='utf8',errors='replace');(out/(name+'.log')).write_text(v.stdout+v.stderr,encoding='utf8');results.append({'test':name,'passed':v.returncode==0,'seconds':round(time.monotonic()-start,2)});print(results[-1],flush=True)
 if v.returncode:raise SystemExit(v.stdout+v.stderr)
run('android',[sys.executable,'android/run_core_tests.py','--out-dir',str(out/'android')])
for name in ['tb_midi_protocol','tb_midi_flash','tb_midi_top','tb_dds_sine','tb_timbres','tb_instrument_envelopes','tb_midi_audio','tb_voice_allocator','tb_synth_core','tb_multitimbral','tb_ui_controls','tb_ui_inputs','tb_rgb_ui_renderer','tb_midi_menu','tb_pcb_top','tb_pcb_readable','tb_pcb_repeat','tb_bt_polyphony','tb_bt_player_production','tb_stereo_audio','tb_effect_cfg_replay','tb_bt_identity','tb_bt_tail_reuse','tb_touch_keyboard_router','tb_touch_ec11_top','tb_bt_event_cdc','tb_rgb_status_cdc','tb_sustain_envelope']:
 run(name,[sys.executable,'scripts/run_sim.py','--test',name,'--behavioral-pll','--out-dir',str(out/name)])
for tone in [0,4,6,7,8,9,10,11,12,13,14,15]:
 name='retrigger_'+str(tone);run(name,[sys.executable,'scripts/run_sim.py','--test','tb_sustain_retrigger','--param','TIMBRE='+str(tone),'--out-dir',str(out/name)])
for name,params in [('flash_full4096',['COUNT=4096','HALF=4','PROGRAM_BUSY=100','ERASE_BUSY=200']),('flash_production_1mhz',['COUNT=24','HALF=25'])]+([('flash_production_full',['COUNT=4096','HALF=25'])] if a.production_full_flash else []):
 cmd=[sys.executable,'scripts/run_sim.py','--test','tb_midi_flash_production','--out-dir',str(out/name)]
 for item in params:cmd+=['--param',item]
 run(name,cmd)
manifest={f.relative_to(r).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in list((r/'src').rglob('*'))+[r/'keyboard_adsr.gprj'] if f.is_file()}
(out/'summary.json').write_text(json.dumps({'passed':True,'scope':'software/RTL only; no STA or hardware','results':results,'source_sha256':manifest},indent=2),encoding='utf8')
