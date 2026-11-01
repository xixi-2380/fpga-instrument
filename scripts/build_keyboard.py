"""Offline keyboard/ADSR build; all device programming is owned by the user."""
import argparse,pathlib,xml.etree.ElementTree as ET,subprocess,json,re,hashlib,shutil,stat
p=argparse.ArgumentParser();p.add_argument('--stage',choices=['all','build','package','syn','pnr'],default='all');p.add_argument('--sim-dir',default='reports/sim/current');p.add_argument('--out-dir',default='reports/keyboard/current');p.add_argument('--synthesis-inputs');p.add_argument('--pnr-snapshot');p.add_argument('--pnr-profile',choices=['default','routability'],default='default');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
voice_count=int(re.search(r'^`define VOICE_COUNT (\d+)',(root/'src/config/synth_config.svh').read_text(encoding='utf8'),re.M)[1])
lcd_enabled=int(re.search(r'LCD_ENABLE=(\d+)',(root/'src/keyboard_top.sv').read_text(encoding='utf8'))[1])!=0
bt_enabled=int(re.search(r'BT_ENABLE=(\d+)',(root/'src/keyboard_top.sv').read_text(encoding='utf8'))[1])!=0
touch_enabled=int(re.search(r'TOUCH_ENABLE=(\d+)',(root/'src/keyboard_top.sv').read_text(encoding='utf8'))[1])!=0
out=pathlib.Path(a.out_dir)
if not out.is_absolute():out=root/out
out.mkdir(parents=True,exist_ok=True)
sim_dir=pathlib.Path(a.sim_dir)
if not sim_dir.is_absolute():sim_dir=root/sim_dir
tests=['tb_touch_ec11_top','tb_key_note_events','tb_touch_keyboard_router','tb_ec11_encoder','tb_ec11_controls','tb_stacked_effects','tb_stereo_audio','tb_output_gain','tb_audio_latency','tb_bt_identity','tb_bt_short_audio','tb_bt_library_link','tb_max98357_startup','tb_bluetooth_top','tb_ultrasonic_top','tb_british_top','tb_rgb_ui_renderer','tb_gt9110_touch','tb_i2c_register_master','tb_voice_allocator','tb_flash_write_permissions','tb_spi_nor_flash','tb_flash_song_library','tb_score_library_protocol']
if a.stage not in ['build','syn','pnr']:
    for name in tests:
        log=(sim_dir/(name+'.log')).read_text(encoding='utf8')
        assert 'PASS '+name in log and 'FAIL' not in log,'Simulation failed/missing: '+name
tree=ET.parse(root/'keyboard_adsr.gprj')
files=[f for f in tree.find('./FileList') if f.get('enable')=='1']
assert files and all((root/f.get('path')).is_file() for f in files),'Missing enabled project dependency'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
paths=[root/f.get('path') for f in files]+list((root/'src/config').glob('*'))+[root/'src/rom/sine4096.hex',root/'scripts/build_keyboard.py',root/'scripts/build_keyboard.tcl']+[root/'sim'/(name+'.sv') for name in tests]+[root/'sim/touch_keyboard_fixture.svh',root/'sim/poly_audio_reference.svh',root/'sim/check.svh']
inputs={str(p.relative_to(root)):sha(p) for p in paths if p.is_file()}
record=out/'build_inputs.json'
if a.stage!='package':
    if a.stage=='pnr':
        assert a.synthesis_inputs,'PNR requires the manifest from a successful --stage syn'
        previous=json.loads(pathlib.Path(a.synthesis_inputs).read_text(encoding='utf8'))
        assert all(sha(root/n)==h for n,h in previous['source_files'].items()),'HDL/ROM/project changed after synthesis'
        assert sha(root/'impl/gwsynthesis/D2_keyboard_leds.vg')==previous['netlist_sha256'],'Netlist changed after synthesis'
    command=['C:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe',str(root/'scripts/build_keyboard.tcl')]
    if a.stage in ['syn','pnr']:command.append(a.stage)
    if a.pnr_snapshot:
        snapshot=pathlib.Path(a.pnr_snapshot).resolve()
        assert a.stage=='pnr' and snapshot.is_file() and snapshot.suffix=='.p','Incremental PNR requires a saved .p file'
        (out/'pnr_snapshot.json').write_text(json.dumps(dict(path=str(snapshot),sha256=sha(snapshot)),indent=2),encoding='utf8')
        command.append(str(snapshot))
    if a.pnr_profile!='default':
        assert a.stage=='pnr','--pnr-profile requires --stage pnr'
        command.append('--routability')
    run=subprocess.run(command,cwd=root,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=7200)
    log=run.stdout+run.stderr;(out/'build.log').write_text(log,encoding='utf8')
    if run.returncode or re.search(r'^.*ERROR.*$',log,re.M):print(log[-7000:]);raise SystemExit('Keyboard build failed')
    record.write_text(json.dumps(inputs,indent=2),encoding='utf8')
    if a.stage=='syn':
        source_files=list((root/'src').rglob('*.sv'))+list((root/'src').rglob('*.svh'))+list((root/'src').rglob('*.hex'))+[root/'keyboard_adsr.gprj']
        (out/'netlist_manifest.json').write_text(json.dumps(dict(source_files={str(p.relative_to(root)):sha(p) for p in source_files},netlist_sha256=sha(root/'impl/gwsynthesis/D2_keyboard_leds.vg')),indent=2),encoding='utf8')
        print('SYNTHESIS_COMPLETED; physical timing and bitstream not generated');raise SystemExit(0)
else:
    assert json.loads(record.read_text(encoding='utf8'))==inputs,'Source changed after build'
    log=(out/'build.log').read_text(encoding='utf8')
for name,digest in inputs.items():assert sha(root/name)==digest,'Source changed during build: '+name
base=root/'impl/pnr/D2_keyboard_leds'
tr=base.with_suffix('.tr').read_text(errors='replace');rpt=base.with_suffix('.rpt.txt').read_text(errors='replace')
counts={key:int(m[1]) if (m:=re.search(r'<Numbers of '+key+r' Violated Endpoints>:(\d+)',tr)) else None for key in ['Setup','Hold']}
from inspect_timing import inspect
timing=inspect(base.with_suffix('.tr'))
assert timing['setup_hold_pass'] and timing['all_reported_paths_nonnegative'] and timing['pulse_width_pass'] and timing['internal_margin_pass'],'Timing closure/margin criteria not met: '+str(timing['internal_wns'])
expected={'clk':'P16','rst':'U4','HP_BCK':'E22','HP_WS':'F24','HP_DIN':'G24','PA_EN':'H17',
 'keypad_int_n[2]':'U22'}
if bt_enabled:expected.update({'bt_rx':'P24','bt_tx':'P23'})
expected.update({'ultrasonic_trig':'P21','ultrasonic_echo':'U17'})
expected.update({'MAX_BCLK':'V22','MAX_LRCLK':'W19','MAX_DIN':'Y20','MAX_SD_MODE':'V26'})
for name,balls in {'keypad_sda':['AB25','L22','W20'],'keypad_scl':['AA25','W26','V19'],'keypad_int_n':['Y26','U26','U22'],'ec11_a':['V16','U16','T23'],'ec11_b':['Y21','U15','R25'],'ec11_sw_n':['V17','W21','W23']}.items():
    expected.update({name+'['+str(i)+']':ball for i,ball in enumerate(balls)})
expected.update({'led_n['+str(i)+']':v for i,v in enumerate(['R26','J14','L20','M25','N23'])})
expected.update({'flash_cs_n':'L25','flash_sck':'P20','flash_mosi':'R21','flash_miso':'T22','flash_wp_n':'R22','flash_hold_n':'R20'})
expected.update({'board_buttons_n['+str(i)+']':v for i,v in enumerate(['K16','F15','G15','G16'])})
if lcd_enabled:
    expected.update({'lcd_clk':'H21','lcd_hs':'H22','lcd_vs':'A23','lcd_en':'A24'})
    for color,balls in [('r',['K17','J18','H18','G25','J19','H19']),('g',['G20','G21','G22','F22','K15','J16']),('b',['M16','M17','F18','F19','G19','F20'])]:
        expected.update({'lcd_'+color+'['+str(i)+']':v for i,v in enumerate(balls)})
if touch_enabled:
    expected.update({'touch_scl':'AB26','touch_sda':'U25','touch_int':'V23','touch_rst_n':'R23'})
for port,ball in expected.items():
    m=re.search(r'^'+re.escape(port)+r'\s*\|\s*[^|]*\|\s*([A-Z]+\d+)/\d+\s*\|\s*(Y|N)',rpt,re.M)
    assert m and m[1]==ball and m[2]=='Y','Pin mismatch: '+port
usage={}
for key in ['Logic','Register','BSRAM','DSP','PLL']:
    m=re.search(r'^\s*'+key+r'\s*\|\s*(\d+(?:\.\d+)?)/(\d+)',rpt,re.M)
    if m:
        value=float(m[1]);usage[key]=dict(used=int(value) if value.is_integer() else value,available=int(m[2]))
if lcd_enabled:
    assert 'pixel_clk' in tr and usage.get('PLL',{}).get('used',0)>=3,'LCD pixel clock/PLL missing from implementation report'
with base.with_suffix('.fs').open(encoding='ascii',errors='replace') as f:header=f.read(3000)
assert '//SecurityBit: OFF' in header
assert usage.get('BSRAM',{}).get('used',0)>0 and usage.get('DSP',{}).get('used',0)>0
if a.stage in ['build','pnr']:print('OFFLINE_BUILD_PASS',counts,usage);raise SystemExit(0)
def copy(src,dst):
    if dst.exists():dst.chmod(stat.S_IWRITE|stat.S_IREAD)
    shutil.copyfile(src,dst)
fs=root/'bringup/D2_keyboard_leds.fs';fs.parent.mkdir(parents=True,exist_ok=True);copy(base.with_suffix('.fs'),fs)
status=dict(profile='D2_keyboard_leds',pins=expected,resources=usage,setup_hold_violations=counts,
    part='GW5AST-LV138FPG676AC1/I0',device_version='C',source_files_sha256=inputs,
    bitstream_sha256=sha(fs),simulation_tests=tests,simulation_passed=True,pnr_passed=True,
    programming_owner='user',automatic_programming_authorized=False,programmed_by_assistant=False,
    hardware_measurements_passed=False,full_sta_signed=False,per_key_diodes=False,
    rollover_policy='36 touch keys, 32 physical voice allocation slots',
    voice_count=voice_count,voice_bits=24,mix_bits=40,
    scheduler='shared ROM/gain, 16 cycles per voice',render_budget_cycles=32+16*voice_count,
    allocation_policy='same identity retrigger; inactive slot, oldest released, then oldest held; no automatic resurrection of stolen held keys',
    note_range='MIDI 60..95',gain_divisor=32,
    keyboard_source='three independent AiP5916 buses',
    attack_frames=480,decay_frames=4800,sustain_q16=45875,release_frames=9600,
    warnings=re.findall(r'^.*WARN.*$',log,re.M))
(root/'bringup/D2_keyboard_leds_status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
for ext in ['.tr','.rpt.txt','.pin.html']:copy(base.with_suffix(ext),out/('D2'+ext))
print('D2_PACKAGED_PASS',counts,usage,'SHA256='+status['bitstream_sha256'])
