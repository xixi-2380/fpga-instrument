"""Offline keyboard/ADSR build; all device programming is owned by the user."""
import argparse,pathlib,xml.etree.ElementTree as ET,subprocess,json,re,hashlib,shutil,stat
p=argparse.ArgumentParser();p.add_argument('--stage',choices=['all','build','package'],default='all');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'reports/keyboard';out.mkdir(exist_ok=True)
tests=['tb_matrix_keypad','tb_mono_note_control','tb_adsr_envelope','tb_adsr_production','tb_keyboard_core','tb_keyboard_top','tb_keyboard_latency','tb_run_leds']
if a.stage!='build':
    for name in tests:
        log=(root/'reports/sim'/(name+'.log')).read_text(encoding='utf8')
        assert 'PASS '+name in log and 'FAIL' not in log,'Simulation failed/missing: '+name
tree=ET.parse(root/'tone_feasibility.gprj');files=tree.find('./FileList')
for f in list(files):
    if f.get('type') in ['file.cst','file.sdc']:files.remove(f)
for name in ['matrix_keypad','mono_note_control','adsr_envelope','keyboard_core','run_leds']:
    ET.SubElement(files,'File',dict(path='rtl/'+name+'.sv',type='file.verilog',enable='1'))
for name,kind in [('boards/mega138k_pro/keyboard_top.sv','file.verilog'),('boards/mega138k_pro/keyboard.cst','file.cst'),('boards/mega138k_pro/keyboard.sdc','file.sdc')]:
    ET.SubElement(files,'File',dict(path=name,type=kind,enable='1'))
tree.write(root/'keyboard_adsr.gprj',encoding='UTF-8',xml_declaration=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
paths=[root/f.get('path') for f in files]+list((root/'config').glob('*'))+[root/'rom/sine4096.hex',root/'scripts/build_keyboard.py',root/'scripts/build_keyboard.tcl']+[root/'sim'/(name+'.sv') for name in tests]+[root/'sim/passive_matrix_model.svh']
inputs={str(p.relative_to(root)):sha(p) for p in paths if p.is_file()}
record=out/'build_inputs.json'
if a.stage!='package':
    run=subprocess.run(['C:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe',str(root/'scripts/build_keyboard.tcl')],cwd=root,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=600)
    log=run.stdout+run.stderr;(out/'build.log').write_text(log,encoding='utf8')
    if run.returncode or re.search(r'^.*ERROR.*$',log,re.M):print(log[-7000:]);raise SystemExit('Keyboard build failed')
    record.write_text(json.dumps(inputs,indent=2),encoding='utf8')
else:
    assert json.loads(record.read_text(encoding='utf8'))==inputs,'Source changed after build'
    log=(out/'build.log').read_text(encoding='utf8')
for name,digest in inputs.items():assert sha(root/name)==digest,'Source changed during build: '+name
base=root/'impl/pnr/D2_keyboard_leds'
tr=base.with_suffix('.tr').read_text(errors='replace');rpt=base.with_suffix('.rpt.txt').read_text(errors='replace')
counts={key:int(m[1]) if (m:=re.search(r'<Numbers of '+key+r' Violated Endpoints>:(\d+)',tr)) else None for key in ['Setup','Hold']}
assert counts=={'Setup':0,'Hold':0},'Timing violations: '+str(counts)
expected={'clk':'P16','rst':'U4','HP_BCK':'E22','HP_WS':'F24','HP_DIN':'G24','PA_EN':'H17',
 'DBG_BCK':'U22','DBG_WS':'V19','DBG_DIN':'W20','DBG_PA_EN':'U26'}
expected.update({'key_col['+str(i)+']':v for i,v in enumerate(['W25','M24','Y25','AA24'])})
expected.update({'key_row['+str(i)+']':v for i,v in enumerate(['W26','L22','Y26','AA25'])})
expected.update({'led_n['+str(i)+']':v for i,v in enumerate(['J14','R26','L20','M25','N21','N23'])})
for port,ball in expected.items():
    m=re.search(r'^'+re.escape(port)+r'\s*\|\s*[^|]*\|\s*([A-Z]+\d+)/\d+\s*\|\s*(Y|N)',rpt,re.M)
    assert m and m[1]==ball and m[2]=='Y','Pin mismatch: '+port
usage={}
for key in ['Logic','Register','BSRAM','DSP','PLL']:
    m=re.search(r'^\s*'+key+r'\s*\|\s*(\d+)/(\d+)',rpt,re.M)
    if m:usage[key]=dict(used=int(m[1]),available=int(m[2]))
with base.with_suffix('.fs').open(encoding='ascii',errors='replace') as f:header=f.read(3000)
assert '//SecurityBit: OFF' in header
assert usage.get('BSRAM',{}).get('used',0)>0 and usage.get('DSP',{}).get('used',0)>0
if a.stage=='build':print('OFFLINE_BUILD_PASS',counts,usage);raise SystemExit(0)
def copy(src,dst):
    if dst.exists():dst.chmod(stat.S_IWRITE|stat.S_IREAD)
    shutil.copyfile(src,dst)
fs=root/'bringup/D2_keyboard_leds.fs';copy(base.with_suffix('.fs'),fs)
status=dict(profile='D2_keyboard_leds',pins=expected,resources=usage,setup_hold_violations=counts,
    part='GW5AST-LV138FPG676AC1/I0',device_version='C',source_files_sha256=inputs,
    bitstream_sha256=sha(fs),simulation_tests=tests,simulation_passed=True,pnr_passed=True,
    programming_owner='user',automatic_programming_authorized=False,programmed_by_assistant=False,
    hardware_measurements_passed=False,full_sta_signed=False,per_key_diodes=False,
    rollover_policy='ambiguous rectangles clear accepted keys; no arbitrary-key rollover claim',
    voice_count=1,note_range='MIDI 60..75',gain_divisor=32,
    scan_column_us=50,scan_frame_us=200,debounce_scans=15,
    attack_frames=480,decay_frames=4800,sustain_q16=45875,release_frames=9600,
    warnings=re.findall(r'^.*WARN.*$',log,re.M))
(root/'bringup/D2_keyboard_leds_status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
for ext in ['.tr','.rpt.txt','.pin.html']:copy(base.with_suffix(ext),out/('D2'+ext))
print('D2_PACKAGED_PASS',counts,usage,'SHA256='+status['bitstream_sha256'])
