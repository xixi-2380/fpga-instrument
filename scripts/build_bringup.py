import pathlib,xml.etree.ElementTree as ET,subprocess,json,re,hashlib,time,shutil,stat,argparse
parser=argparse.ArgumentParser()
parser.add_argument("--package-only", action="store_true", help="Package existing completed offline build; never access hardware")
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
tree=ET.parse(root/'tone_feasibility.gprj');files=tree.find('./FileList')
for f in list(files):
    if f.get('type') in ['file.sdc','file.cst']:files.remove(f)
for path,kind in [('boards/mega138k_pro/bringup_digital.sv','file.verilog'),('boards/mega138k_pro/bringup.cst','file.cst'),('boards/mega138k_pro/bringup_digital.sdc','file.sdc')]:
    ET.SubElement(files,'File',dict(path=path,type=kind,enable='1'))
tree.write(root/'bringup_digital.gprj',encoding='UTF-8',xml_declaration=True)
out=root/'reports/bringup';out.mkdir(exist_ok=True)
if not args.package_only:
    cmd=['C:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe',str(root/'scripts/build_bringup.tcl')]
    r=subprocess.run(cmd,cwd=root,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=600)
    log=r.stdout+r.stderr;(out/'D0_header_build.log').write_text(log,encoding='utf8')
    print('\n'.join(log.splitlines()[-45:]))
    if r.returncode or 'ERROR ' in log:raise SystemExit('Bringup build failed')
base=root/'impl/pnr/bringup_D0_header_mirror';tr=base.with_suffix('.tr').read_text(errors='replace');rpt=base.with_suffix('.rpt.txt').read_text(errors='replace')
counts={k:int(m[1]) if (m:=re.search(r'<Numbers of '+k+r' Violated Endpoints>:(\d+)',tr)) else None for k in ['Setup','Hold']}
expected={'clk':'P16','rst':'U4','HP_BCK':'E22','HP_WS':'F24','HP_DIN':'G24','PA_EN':'H17','DBG_BCK':'U22','DBG_WS':'V19','DBG_DIN':'W20','DBG_PA_EN':'U26'}
actual={}
for port,ball in expected.items():
    m=re.search(r'^'+re.escape(port)+r'\s*\|\s*[^|]*\|\s*([A-Z]+\d+)/\d+\s*\|\s*(Y|N)',rpt,re.M)
    if not m or m[1]!=ball or m[2]!='Y':raise SystemExit('Physical pin mismatch: '+port)
    actual[port]=m[1]
if any(v!=0 for v in counts.values()):raise SystemExit('Setup/hold checks failed: '+str(counts))
sim=(root/'reports/sim/tb_bringup_digital.log').read_text()
if 'PASS tb_bringup_digital' not in sim or 'FAIL' in sim:raise SystemExit('Diagnostic simulation not passed')
def copy_generated(src, dst):
    # Gowin marks generated files read-only. Replace only this project's packaged outputs.
    if dst.exists(): dst.chmod(stat.S_IREAD | stat.S_IWRITE)
    shutil.copyfile(src, dst)
dest=root/'bringup';dest.mkdir(exist_ok=True);fs=dest/'D0_header_mirror.fs'
source_fs=base.with_suffix('.fs')
with source_fs.open(encoding='ascii',errors='replace') as f: source_header=f.read(2000)
if '//SecurityBit: OFF' not in source_header: raise SystemExit('Source bitstream readback protection still enabled')
copy_generated(source_fs,fs)
header=fs.read_text(encoding='ascii',errors='replace')[:2000]
if '//SecurityBit: OFF' not in header:raise SystemExit('Readback protection still enabled')
status=dict(profile='D0_header_mirror',programming_owner='user',automatic_programming_authorized=False,purpose='SRAM muted diagnostic: original DAC pins plus four user-selected J23 GPIO mirrors',
    device='GW5AST-138C',part='GW5AST-LV138FPG676AC1/I0',
    source_files_sha256={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in list((root/'rtl').glob('*.sv'))+list((root/'boards/mega138k_pro').glob('*.sv'))+list((root/'config').glob('*'))+[root/'boards/mega138k_pro/bringup.cst',root/'boards/mega138k_pro/bringup_digital.sdc',root/'rom/sine4096.hex']},
    bitstream_sha256=hashlib.sha256(fs.read_bytes()).hexdigest(),pins=actual,setup_hold_violations=counts,
    simulation_passed=True,gpio_mirror_simulation_passed=True,pnr_passed=True,documentary_mapping_checked=True,readback_protection_disabled=True,
    PA_EN_hard_zero=True,DIN_hard_zero=True,gpio_mirrors={'DBG_BCK':'HP_BCK','DBG_WS':'HP_WS','DBG_DIN':'HP_DIN','DBG_PA_EN':'PA_EN'},header_connector='J23',header_pin_numbers={'DBG_BCK':39,'DBG_WS':37,'DBG_DIN':35,'DBG_PA_EN':33},hardware_measurements_passed=False,
    full_audio_release_qualified=False,device_speed_basis='Sipeed official IDE installation device table; chip marking hidden',
    core_compatibility_basis='4071 and 4072 schematics agree for P16/U4; actual core PCB revision remains unreadable')
(dest/'D0_header_mirror_status.json').write_text(json.dumps(status,ensure_ascii=False,indent=2),encoding='utf8')
for ext in ['.tr','.rpt.txt','.pin.html']:copy_generated(base.with_suffix(ext),out/('D0_header'+ext))
print('D0 ready:',json.dumps(dict(pins=actual,violations=counts,sha256=status['bitstream_sha256']),indent=2))
