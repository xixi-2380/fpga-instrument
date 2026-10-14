"""No Flash operations. Reject unsigned hardware/build status before invoking CLI."""
raise SystemExit("Manual programming only: user instruction. Open Gowin Programmer yourself; see docs/bringup_D0.md. No device access performed.")
import json,pathlib,subprocess,hashlib
root=pathlib.Path(__file__).resolve().parents[1]
h=json.loads((root/'boards/mega138k_pro/hardware_status.json').read_text())
required=['speed_grade_verified','pin_mapping_verified_on_actual_board',
          'io_voltage_verified_on_actual_board','amplifier_polarity_verified',
          'external_audio_timing_signed']
missing=[k for k in required if h.get(k) is not True]
if not h.get('core_pcb_revision'):missing.append('core_pcb_revision')
if not h.get('dock_pcb_revision'):missing.append('dock_pcb_revision')
if missing:raise SystemExit('NOT PROGRAMMED: hardware verification incomplete: '+', '.join(missing))
release=root/'release';fs=release/'tone.fs';status=release/'status.json'
if not status.exists() or not fs.exists():raise SystemExit('NOT PROGRAMMED: no qualified release')
s=json.loads(status.read_text());digest=hashlib.sha256(fs.read_bytes()).hexdigest()
if not all(s.get(k) is True for k in ['rtl_sim_passed','vendor_sim_passed','pnr_passed','sta_passed']):
    raise SystemExit('NOT PROGRAMMED: release checks incomplete')
if digest!=s.get('sha256'):raise SystemExit('NOT PROGRAMMED: release hash mismatch')
cmd=['C:/Gowin/Gowin_V1.9.12.04_x64/Programmer/bin/programmer_cli.exe',
     '--device','GW5AST-138C','--cable-index','1','--frequency','2.5MHz',
     '--operation_index','4','--fsFile',str(fs)]
log=subprocess.run(cmd,capture_output=True,text=True,errors='replace')
(root/'reports/hardware/program_sram.log').write_text(log.stdout+log.stderr,encoding='utf8')
print(log.stdout+log.stderr)
raise SystemExit(log.returncode)
