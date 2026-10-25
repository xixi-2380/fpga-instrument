"""Pure HDL suite; reads the production GPRJ. Never invokes Gowin/EDA/JTAG."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TESTS = ['tb_ultrasonic_range', 'tb_ultrasonic_volume', 'tb_audio_master_gain',
                 'tb_ultrasonic_top', 'tb_synth_core', 'tb_score_audio',
                 'tb_audio_restart', 'tb_theme_top', 'tb_max98357_startup',
                 'tb_rgb_status_cdc', 'tb_frame_buffer', 'tb_i2s_tx']
INTEGRATED = {'tb_ultrasonic_top', 'tb_score_audio', 'tb_audio_restart',
              'tb_theme_top', 'tb_max98357_startup'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', action='append', help='Test module, repeatable')
    parser.add_argument('--param', action='append', default=[], help='NAME=INTEGER; one test only')
    parser.add_argument('--timeout', type=float, default=600, help='Runtime limit per simulation in seconds')
    parser.add_argument('--out-dir', default='reports/ultrasonic/2026-10-25')
    parser.add_argument('--make-arg', action='append', default=[], help='Optional Verilator make argument')
    parser.add_argument('--simulator', choices=['iverilog', 'verilator'], default='iverilog')
    args = parser.parse_args()
    tests = args.test or DEFAULT_TESTS
    if args.param and len(tests) != 1:
        parser.error('--param needs exactly one test')
    for item in args.param:
        name, sep, value = item.partition('=')
        if not sep or not name.isidentifier() or not value.lstrip('-').isdigit():
            parser.error('Use --param NAME=INTEGER')
    out = Path(args.out_dir).resolve()
    out.mkdir(parents=True, exist_ok=True)
    project = ET.parse(ROOT / 'keyboard_adsr.gprj')
    sources = [f.get('path') for f in project.findall('./FileList/File')
               if f.get('type') == 'file.verilog' and f.get('enable') == '1']
    if not sources or not all((ROOT / p).is_file() for p in sources):
        raise RuntimeError('Missing enabled project source')
    # Replace only PLLs in test elaboration. These files never enter the GPRJ.
    sources = [s for s in sources if s != 'src/pll_pair.sv']
    sources += ['sim/pll_pair_behavioral.sv', 'sim/pixel_pll_behavioral.sv']
    exe = shutil.which(args.simulator)
    if not exe and args.simulator == 'verilator':
        exe = shutil.which('verilator-cli')
    if not exe:
        raise RuntimeError('Install selected HDL simulator and add it to PATH')
    results = []
    for test in tests:
        if not test.isidentifier() or not (ROOT / 'sim' / (test + '.sv')).is_file():
            raise RuntimeError('Unknown test: ' + test)
        start = time.monotonic()
        if args.simulator == 'verilator':
            build = out / ('build_' + test)
            build.mkdir(exist_ok=True)
            cmd = [exe, '--binary', '--timing', '--relative-includes', '-Isim',
                   '-Wno-fatal', '--top-module', test, '--Mdir', str(build), '-j', '2']
            for make_arg in args.make_arg:
                cmd += ['-MAKEFLAGS', make_arg]
            cmd += ['-G' + p for p in args.param] + sources + ['sim/' + test + '.sv']
            run_cmd = [str(build / ('V' + test))]
        else:
            target = out / (test + '.vvp')
            cmd = [exe, '-g2012', '-Wall', '-grelative-include', '-Isim', '-s', test, '-o', str(target)]
            for p in args.param:
                cmd += ['-P', test + '.' + p]
            cmd += sources + ['sim/' + test + '.sv']
            run_cmd = [shutil.which('vvp') or 'vvp', str(target)]
        print('RUN', test, flush=True)
        compile_result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        (out / (test + '_compile.log')).write_text(compile_result.stdout + compile_result.stderr)
        if compile_result.returncode:
            print(compile_result.stderr[-5000:], flush=True)
            raise SystemExit(compile_result.returncode)
        run = subprocess.run(run_cmd + ['+SIM_OUT_DIR=' + str(out)], cwd=ROOT,
                             capture_output=True, text=True, timeout=args.timeout)
        (out / (test + '.log')).write_text(run.stdout + run.stderr)
        passed = run.returncode == 0 and ('PASS ' + test) in run.stdout
        results.append(dict(test=test, parameters=args.param, passed=passed,
                            simulator=args.simulator, pll_model='behavioral substitute' if test in INTEGRATED else 'not exercised',
                            seconds=round(time.monotonic() - start, 3)))
        (out / 'summary.json').write_text(json.dumps(results, indent=2))
        print(run.stdout[-1800:] + run.stderr[-1000:], flush=True)
        if not passed:
            raise SystemExit(1)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
