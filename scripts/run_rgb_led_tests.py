"""Fixed keyboard + RGB regression. Custom mapping and recording excluded."""
import argparse,concurrent.futures,hashlib,json,os,pathlib,re,subprocess,sys,time
p=argparse.ArgumentParser();p.add_argument('--out-dir',required=True);p.add_argument('--jobs',type=int,default=3);p.add_argument('--timeout',type=int,default=300);a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];out=pathlib.Path(a.out_dir).resolve();out.mkdir(parents=True,exist_ok=True)
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
manifest={f.relative_to(r).as_posix():sha(f) for folder in ['src','sim','android/app/src/main','android/tests'] for f in sorted((r/folder).rglob('*')) if f.is_file()}
manifest['keyboard_adsr.gprj']=sha(r/'keyboard_adsr.gprj')
(out/'source_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
# Assert the old73 pads are unchanged and the sole addition is P25.
def pins(s):return dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+)\s*;',s))
old=pins(subprocess.check_output(['git','show','815b56a:src/keyboard.cst'],cwd=r).decode('utf8'));new=pins((r/'src/keyboard.cst').read_text(encoding='utf8'))
assert len(old)==73 and len(new)==74 and all(new[k]==v for k,v in old.items()) and new['rgb_led_data']=='P25' and len(set(new.values()))==74
assert sha(r/'src/ws2812_driver.v')==sha(pathlib.Path('E:/gowin/rgb led/ws2812_driver.v'))
# The latest instruction excludes both complete features, including the App.
for name in ['src/instrument_features.sv','src/flash_keymap.sv',
 'android/app/src/main/java/cn/whu/gaoshan/core/KeyMap.java',
 'android/app/src/main/java/cn/whu/gaoshan/core/PerformanceRecording.java']:
 assert not (r/name).exists(), name
for name in ['src/key_note_events.sv','src/score_services.sv','src/bluetooth_score_link.sv']:
 assert (r/name).read_bytes()==subprocess.check_output(['git','show','815b56a:'+name],cwd=r), name
assert not subprocess.check_output(['git','diff','--name-only','815b56a','--','android'],cwd=r).strip()

tests=[('packet_math','tb_bt_packet_math',[],False),('tail_arbitration','tb_rgb_tail_arbitration',[],True),('driver','tb_rgb_led_driver',[],False),('control','tb_rgb_led_control',[],False),('notes','tb_rgb_led_notes',[],False),('rgb_page','tb_rgb_led_ui',[],False),
 ('ui_inputs','tb_ui_inputs',[],False),('ui_controls','tb_ui_controls',[],False),('ui_more','tb_ui_more',[],False),
 ('pcb_touch','tb_pcb_touch',[],False),('pcb_repeat','tb_pcb_repeat',[],False),('pcb_readable','tb_pcb_readable',[],False),('pcb_top','tb_pcb_top',[],True),
 ('sustain_envelope','tb_sustain_envelope',[],False),('sustain_controls','tb_sustain_controls',[],False),('sustain_retrigger32','tb_sustain_retrigger',['VOICES=32'],False),
 ('tail_legacy','tb_bt_natural_sustain',[],False),('tail_midi','tb_bt_natural_sustain',['TIMBRE=14','LEGACY=0'],False),('tail_drum','tb_bt_natural_sustain',['TIMBRE=19','LEGACY=0'],False),
 ('midi_protocol','tb_midi_protocol',[],False),('midi_flash','tb_midi_flash',[],False),('display_connector','tb_rgb_display',[],True),('cdc','tb_rgb_status_cdc',[],False),('latency_stereo','tb_audio_latency',['STEREO=1'],False)]
env=os.environ.copy();jdk=r/'android/build-local/jdk17/jdk-17.0.21.0.2+1/bin';env['PATH']=str(jdk)+os.pathsep+env['PATH']
def bounded(label,cmd,d):
 d.mkdir(parents=True,exist_ok=True);start=time.monotonic();proc=subprocess.Popen(cmd,cwd=r,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8',errors='replace');timeout=False
 try:log=proc.communicate(timeout=a.timeout)[0]
 except subprocess.TimeoutExpired:
  timeout=True
  if os.name=='nt':subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  else:proc.kill()
  log=proc.communicate()[0]
 (d/'runner.log').write_text(log,encoding='utf8')
 result=dict(name=label,passed=proc.returncode==0 and not timeout,timed_out=timeout,seconds=round(time.monotonic()-start,3))
 (d/'result.json').write_text(json.dumps(result,indent=2),encoding='utf8');print(('PASS ' if result['passed'] else 'FAIL ')+label+(' TIMEOUT' if timeout else '')+' '+str(result['seconds'])+'s',flush=True)
 if not result['passed']:print(log[-1600:],flush=True)
 return result
android=bounded('android_core',[sys.executable,'android/run_core_tests.py','--out-dir',str(out/'android')],out/'android')
def run(c):
 label,test,params,pll=c;cmd=[sys.executable,'scripts/run_sim.py','--test',test,'--out-dir',str(out/label)]
 if pll:cmd+=['--behavioral-pll']
 for v in params:cmd+=['--param',v]
 return bounded(label,cmd,out/label)
with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(run,tests))
same=all(sha(r/f)==h for f,h in manifest.items())
summary=dict(build_id='26103005',custom_keymap=False,performance_recording=False,passed=android['passed'] and all(v['passed'] for v in results) and same,sources_unchanged=same,old_pins=73,new_pins=74,din='P25',android=android,results=results,scope='Software/RTL only. No EDA, STA, bitstream or hardware test; no4096/1MHz full-library claim.')
(out/'validation.json').write_text(json.dumps(summary,indent=2),encoding='utf8')
raise SystemExit(0 if summary['passed'] else 1)
