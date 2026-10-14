"""Offline synthesis, P&R and packaging only. Never invokes a programmer."""
import argparse, pathlib, xml.etree.ElementTree as ET, subprocess, os, json, re, hashlib, stat, shutil
parser=argparse.ArgumentParser()
parser.add_argument('--profile',choices=['stereo','left','right','all'],default='all')
parser.add_argument('--stage',choices=['all','build','package'],default='all',help='build is offline only; package requires passed simulation')
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'reports/tone_play';out.mkdir(exist_ok=True)
dest=root/'bringup';dest.mkdir(exist_ok=True)
if args.stage!='build':
    sim=(root/'reports/sim/tb_tone_play.log').read_text(encoding='utf8')
    assert 'PASS tb_tone_play' in sim and 'FAIL' not in sim,'Board-level tone simulation must pass before packaging'
expected={'clk':'P16','rst':'U4','HP_BCK':'E22','HP_WS':'F24','HP_DIN':'G24','PA_EN':'H17',
          'DBG_BCK':'U22','DBG_WS':'V19','DBG_DIN':'W20','DBG_PA_EN':'U26'}
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def copy_generated(src,dst):
    if dst.exists():dst.chmod(stat.S_IREAD|stat.S_IWRITE)
    shutil.copyfile(src,dst)
for profile in (['stereo','left','right'] if args.profile=='all' else [args.profile]):
    print('BUILD',profile,flush=True)
    tree=ET.parse(root/'tone_feasibility.gprj');files=tree.find('./FileList')
    for f in list(files):
        if f.get('type') in ['file.cst','file.sdc']:files.remove(f)
    for name,kind in [('boards/mega138k_pro/tone_play.sv','file.verilog'),('boards/mega138k_pro/tone_play.cst','file.cst'),('boards/mega138k_pro/tone_play.sdc','file.sdc')]:
        ET.SubElement(files,'File',dict(path=name,type=kind,enable='1'))
    tree.write(root/('tone_play_'+profile+'.gprj'),encoding='UTF-8',xml_declaration=True)
    source_paths=[root/f.get('path') for f in files]+list((root/'config').glob('*'))+[
        root/'rom/sine4096.hex',root/'sim/tb_tone_play.sv',root/'scripts/build_tone_play.tcl',root/'scripts/build_tone_play.py']
    before={str(p.relative_to(root)):digest(p) for p in source_paths if p.is_file()}
    build_record=out/(profile+'_build_inputs.json')
    if args.stage!='package':
        env=os.environ.copy();env['TONE_PROFILE']=profile
        cmd=['C:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe',str(root/'scripts/build_tone_play.tcl')]
        result=subprocess.run(cmd,cwd=root,env=env,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=600)
        log=result.stdout+result.stderr
        (out/(profile+'_build.log')).write_text(log,encoding='utf8')
        errors=re.findall(r'^.*ERROR.*$',log,re.M)
        if result.returncode or errors:print(log[-6500:]);raise SystemExit('Offline tone build failed: '+profile)
        build_record.write_text(json.dumps(before,indent=2),encoding='utf8')
    else:
        assert json.loads(build_record.read_text(encoding='utf8'))==before,'Sources changed since offline build'
        log=(out/(profile+'_build.log')).read_text(encoding='utf8')
    for name,sha in before.items():assert digest(root/name)==sha,'Source changed during build: '+name
    base=root/'impl/pnr'/('D1_'+profile+'_440')
    tr=base.with_suffix('.tr').read_text(errors='replace')
    rpt=base.with_suffix('.rpt.txt').read_text(errors='replace')
    counts={key:int(m[1]) if (m:=re.search(r'<Numbers of '+key+r' Violated Endpoints>:(\d+)',tr)) else None for key in ['Setup','Hold']}
    assert counts=={'Setup':0,'Hold':0},'Timing not passed: '+str(counts)
    actual={}
    for port,ball in expected.items():
        m=re.search(r'^'+re.escape(port)+r'\s*\|\s*[^|]*\|\s*([A-Z]+\d+)/\d+\s*\|\s*(Y|N)',rpt,re.M)
        assert m and m[1]==ball and m[2]=='Y','Physical pin mismatch: '+port
        actual[port]=m[1]
    usage={}
    for key in ['Logic','Register','BSRAM','DSP','PLL']:
        m=re.search(r'^\s*'+key+r'\s*\|\s*(\d+)/(\d+)',rpt,re.M)
        if m:usage[key]=dict(used=int(m[1]),available=int(m[2]))
    assert usage.get('BSRAM',{}).get('used',0)>0 and usage.get('DSP',{}).get('used',0)>0,'DDS/ROM path unexpectedly removed'
    assert '480' in (root/'config/synth_config.svh').read_text() and '240' in (root/'config/synth_config.svh').read_text()
    with base.with_suffix('.fs').open(encoding='ascii',errors='replace') as f:header=f.read(3000)
    assert '//SecurityBit: OFF' in header,'SRAM readback protection still enabled'
    if args.stage=='build':
        print('OFFLINE_BUILD_PASS',profile,'pins=10',counts,flush=True)
        continue
    fs=dest/('D1_'+profile+'_440.fs');copy_generated(base.with_suffix('.fs'),fs)
    warnings=re.findall(r'^.*WARN.*$',log,re.M)
    record=dict(profile='D1_'+profile+'_440',channel_mode=['stereo','left','right'].index(profile),
        part='GW5AST-LV138FPG676AC1/I0',device_version='C',programming_owner='user',automatic_programming_authorized=False,
        bitstream=str(fs.relative_to(root)),bitstream_sha256=digest(fs),source_files_sha256=before,
        pins=actual,resources=usage,setup_hold_violations=counts,pnr_passed=True,simulation_passed=True,
        simulation_log='reports/sim/tb_tone_play.log',frame_rate_hz=48000,bck_hz=1536000,fcw_hex='0258BF26',
        tone_hz=39370534*48000/2**32,gain_divisor=32,mute_frames=480,fade_frames=240,
        readback_protection_disabled=True,rom_initialization_requested=True,warnings=warnings,
        programmed_by_assistant=False,hardware_measurements_passed=False,full_sta_signed=False,
        limitations=['PR1014 reference clock route warning; physical lock and frequencies await measurement',
                     'Output path budget 0..30 ns is implementation bound; DAC-pad timing not electrically measured',
                     'Core revision/speed marking unreadable; build grade uses official Sipeed documentation'])
    (dest/('D1_'+profile+'_440_status.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    for ext in ['.tr','.rpt.txt','.pin.html']:copy_generated(base.with_suffix(ext),out/(profile+ext))
    print('PASS',profile,'pins=10',counts,'resources='+str(usage),'SHA256='+record['bitstream_sha256'],flush=True)
