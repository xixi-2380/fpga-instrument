"""Independent retained Bluetooth/Flash tests; behavioral PLL is not STA evidence."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BIN = Path('C:/Users/10939/Documents/Codex/2026-10-30/qin-2/work/sim-tools/mingw64/bin')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--tool-bin', type=Path, default=DEFAULT_BIN)
    ap.add_argument('--suite', choices=['all', 'unit', 'top'], default='all')
    ap.add_argument('--case', action='append', default=[])
    ap.add_argument('--out-dir', type=Path, default=ROOT/'reports/integration_20261101/bluetooth')
    args = ap.parse_args()
    out = args.out_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env['PATH'] = str(args.tool_bin)+os.pathsep+env.get('PATH', '')
    # The exact enabled production project list, with explicit simulation clocks/IO.
    sources = [ROOT/f.get('path') for f in ET.parse(ROOT/'keyboard_adsr.gprj').getroot().findall('./FileList/File')
               if f.get('type') == 'file.verilog' and f.get('enable') == '1' and Path(f.get('path')).name != 'pll_pair.sv']
    sources += [ROOT/'sim/pll_pair_behavioral.sv', ROOT/'sim/pixel_pll_behavioral.sv', ROOT/'sim/io_behavioral.sv']
    cases = [
        ('midi_protocol_4', 'tb_midi_protocol', {'VOICES': 4}, []),
        ('midi_protocol_16', 'tb_midi_protocol', {'VOICES': 16}, []),
        ('event_cdc', 'tb_bt_event_cdc', {}, []),
        ('wire_9600', 'tb_bluetooth_score_link', {}, []),
        ('wire_115200', 'tb_bluetooth_score_link', {'CLOCK_HZ': 5000000, 'BAUD': 115200}, []),
        ('midi_flash', 'tb_midi_flash', {}, ['buffered_nor_model.sv']),
        ('library_transactions_32', 'tb_flash_song_library', {}, ['buffered_nor_model.sv']),
        ('flash_production_1MHz', 'tb_midi_flash_production', {'COUNT': 24, 'HALF': 25, 'PROGRAM_BUSY': 100, 'ERASE_BUSY': 200}, ['spi_nor_model.sv']),
        ('tail_reuse_stereo', 'tb_bt_tail_reuse', {'STEREO': 1}, []),
        ('top_uart', 'tb_bluetooth_integration_uart', {}, ['spi_nor_model.sv']),
    ]
    if args.suite != 'all':
        cases = [c for c in cases if c[0].startswith('top_') == (args.suite == 'top')]
    if args.case:
        cases = [c for c in cases if c[0] in args.case]
    assert cases, 'No selected case'
    results = []
    for name, module, params, models in cases:
        d = out/name
        d.mkdir(exist_ok=True)
        tb = ROOT/('sim/integration' if module.startswith('tb_bluetooth_integration') else 'sim')/(module+'.sv')
        inputs = sources+[ROOT/'sim'/m for m in models]+[tb]
        # Includes/memory tables also affect execution even when omitted from CLI.
        tracked = sorted(set(inputs+list((ROOT/'src').rglob('*.svh'))+list((ROOT/'src').rglob('*.hex'))+
                             [ROOT/'sim/touch_keyboard_fixture.svh', ROOT/'sim/aip5916_model.svh', Path(__file__).resolve()]))
        before = {p.relative_to(ROOT).as_posix(): sha(p) for p in tracked}
        (d/'source_hashes.json').write_text(json.dumps(before, indent=2), encoding='utf8')
        cmd = [(args.tool_bin/'iverilog.exe').as_posix(), '-g2012', '-grelative-include', '-I', (ROOT/'src').as_posix(),
               '-I', (ROOT/'sim').as_posix(), '-s', module, '-o', (d/'test.vvp').as_posix()]
        for key, value in params.items():
            cmd += ['-P', f'{module}.{key}={value}']
        cmd += [p.as_posix() for p in inputs]
        (d/'commands.json').write_text(json.dumps({'compile': cmd, 'parameters': params}, indent=2), encoding='utf8')
        print('RUN', name, flush=True)
        start = time.monotonic()
        c = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, encoding='utf8', errors='replace', timeout=120)
        (d/'compile.log').write_text(c.stdout+c.stderr, encoding='utf8')
        run_stdout = ''
        returncode = c.returncode
        if not returncode:
            try:
                r = subprocess.run([(args.tool_bin/'vvp.exe').as_posix(), (d/'test.vvp').as_posix(), '+SIM_OUT_DIR='+d.as_posix()],
                                   cwd=ROOT, env=env, capture_output=True, text=True, encoding='utf8', errors='replace', timeout=900)
                run_stdout = r.stdout+r.stderr
                returncode = r.returncode
            except subprocess.TimeoutExpired as exc:
                run_stdout = str(exc.stdout or '')+str(exc.stderr or '')+'\nTIMEOUT after 900s\n'
                returncode = 124
        else:
            run_stdout = c.stdout+c.stderr
        (d/'run.log').write_text(run_stdout, encoding='utf8')
        after = {p.relative_to(ROOT).as_posix(): sha(p) for p in tracked}
        changed = [p for p in before if before[p] != after[p]]
        m = re.search(r'PASS '+module+r' checks=(\d+)', run_stdout)
        passed = returncode == 0 and m is not None
        result = {'case': name, 'module': module, 'parameters': params, 'passed': passed,
                  'checks': int(m.group(1)) if m else None, 'seconds': round(time.monotonic()-start, 3),
                  'inputs_changed_during_run': changed, 'source_manifest_sha256': sha(d/'source_hashes.json'),
                  'run_log_sha256': sha(d/'run.log'), 'pll': 'explicit behavioral substitute; not PLL/STA/hardware validation'}
        results.append(result)
        print(run_stdout[-2500:], flush=True)
        print(json.dumps(result), flush=True)
        (out/('summary_'+args.suite+'.json')).write_text(json.dumps(results, indent=2), encoding='utf8')
        if not passed:
            raise SystemExit(1)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
