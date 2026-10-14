"""Load ONLY the hard-muted D0 diagnostic into SRAM. Never writes Flash."""
raise SystemExit("Manual programming only: user instruction. Open Gowin Programmer yourself; see docs/bringup_D0.md. No device access performed.")
import pathlib,json,hashlib,subprocess,datetime,re
root=pathlib.Path(__file__).resolve().parents[1];folder=root/'bringup'
s=json.loads((folder/'D0_status.json').read_text());fs=folder/'D0_muted.fs'
assert s['profile']=='D0_muted' and s['device']=='GW5AST-138C'
assert all(s[k] is True for k in ['simulation_passed','pnr_passed','documentary_mapping_checked','PA_EN_hard_zero','DIN_hard_zero','readback_protection_disabled'])
assert s['setup_hold_violations']=={'Setup':0,'Hold':0}
assert hashlib.sha256(fs.read_bytes()).hexdigest()==s['bitstream_sha256']
for path,digest in s['source_files_sha256'].items():
    assert hashlib.sha256((root/path).read_bytes()).hexdigest()==digest,'Source changed after build: '+path
hw=json.loads((root/'boards/mega138k_pro/hardware_status.json').read_text())
assert hw['device_version']=='C' and hw['dock_pcb_revision']=='4071f3'
exe='C:/Gowin/Gowin_V1.9.12.04_x64/Programmer/bin/programmer_cli.exe'
scan=subprocess.run([exe,'--scan','--cable-index','1','--frequency','2.5MHz'],capture_output=True,text=True,errors='replace')
out=root/'reports/hardware';out.mkdir(exist_ok=True)
(out/'D0_jtag_scan.log').write_text(scan.stdout+scan.stderr,encoding='utf8')
if scan.returncode or '0x0001081B' not in scan.stdout or '1 device(s) found' not in scan.stdout:raise SystemExit('Unexpected JTAG chain; not programmed')
cmd=[exe,'--device','GW5AST-138C','--cable-index','1','--frequency','2.5MHz','--operation_index','4','--fsFile',str(fs)]
r=subprocess.run(cmd,capture_output=True,text=True,errors='replace',timeout=180)
log=r.stdout+r.stderr;(out/'D0_program_sram.log').write_text(log,encoding='utf8')
print('\n'.join(line for line in log.splitlines() if line.strip() and '%' not in line)[-4500:])
verified=r.returncode==0 and bool(re.search(r'(?:Verify|Program).*Success|Success.*(?:Verify|Program)',log,re.I)) and not bool(re.search(r'\b(?:FAILED|ERROR)\b',log,re.I))
record=dict(returncode=r.returncode,sram_program_verified=verified,profile=s['profile'],bitstream_sha256=s['bitstream_sha256'],
    command=cmd,operation='SRAM Program and Verify',flash_written=False,measurement_status='pending',
    requested_frequency='2.5MHz',sdk_frequency_updates=re.findall(r'Frequency Updated:\s*"([^"]+)"',log))
(out/'D0_program_result.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
if not verified:raise SystemExit('Programming success not established; inspect saved raw log')
hw['programmed']=True;hw['programmed_profile']='D0_muted';hw['sram_program_verified']=True
hw['hardware_measurements_passed']=False
(root/'boards/mega138k_pro/hardware_status.json').write_text(json.dumps(hw,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
