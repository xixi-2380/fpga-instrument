"""Run the selected two-project merge regression. Pure HDL/software, no EDA."""
import argparse, concurrent.futures, json, pathlib, subprocess, sys, time

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--only',action='append',default=[])
parser.add_argument('--jobs',type=int,default=3)
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'reports/integration_2026-10-26/tests'
units=['tb_adsr_envelope','tb_adsr_production','tb_instrument_envelopes','tb_audio_timing',
 'tb_bt_articulation','tb_rgb_status_cdc','tb_ultrasonic_range','tb_ultrasonic_volume',
 'tb_ui_controls','tb_ui_inputs','tb_ui_more','tb_master_volume','tb_audio_limiter','tb_latency_bcd',
 'tb_audio_latency','tb_output_gain','tb_spi_nor_flash','tb_flash_song_library',
 'tb_score_library_protocol','tb_bt_counter','tb_bluetooth_score_core','tb_bluetooth_score_link',
 'tb_synth_core','tb_effects_integration']
integrations=['tb_bt_short_audio','tb_bluetooth_top','tb_bt_library_link','tb_bt_identity',
 'tb_rgb_display','tb_ultrasonic_top','tb_keyboard_top']
configs=[(t,t,[],False) for t in units]+[(t,t,[],True) for t in integrations]
configs += [(f'polyphony_effect_{i}','tb_bt_polyphony',[f'EFFECT={i}'],False) for i in range(3)]
# Full renderer is relatively expensive; it includes both library and ultrasound pages.
configs += [('tb_rgb_ui_renderer','tb_rgb_ui_renderer',[],False)]
if args.only:configs=[c for c in configs if c[0] in args.only]
assert configs and args.jobs>0

def run(config):
 name,test,params,behavioral=config;directory=out/name;directory.mkdir(parents=True,exist_ok=True)
 cmd=[sys.executable,str(root/'scripts/run_sim.py'),'--test',test,'--out-dir',str(directory)]
 if behavioral:cmd+=['--behavioral-pll']
 for parameter in params:cmd+=['--param',parameter]
 start=time.monotonic()
 result=subprocess.run(cmd,cwd=root,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=900)
 (directory/'runner.log').write_text(result.stdout+result.stderr,encoding='utf8')
 value={'configuration':name,'test':test,'params':params,'behavioral_pll':behavioral,
        'passed':result.returncode==0,'seconds':round(time.monotonic()-start,3)}
 (directory/'integration_result.json').write_text(json.dumps(value,indent=2),encoding='utf8')
 print(('PASS ' if value['passed'] else 'FAIL ')+name+' '+str(value['seconds'])+'s',flush=True)
 if not value['passed']:print((result.stdout+result.stderr)[-2200:],flush=True)
 return value

with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
 results=list(pool.map(run,configs))
(out.parent/'regression_latest.json').write_text(json.dumps(results,indent=2),encoding='utf8')
print('RESULT',sum(x['passed'] for x in results),'/',len(results),flush=True)
raise SystemExit(0 if all(x['passed'] for x in results) else 1)
