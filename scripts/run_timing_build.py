"""Isolated Gowin implementation and phase measurements; never programs a device."""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--name', required=True)
p.add_argument('--out-root', default='reports/timing_fixed_rgb_2026-10-30')
p.add_argument('--option', action='append', default=[], help='Documented Tcl option NAME=VALUE')
p.add_argument('--reuse-syn-from', help='Completed immutable build directory; rerun P&R without repeating synthesis')
a = p.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
out = (root / a.out_root / a.name).resolve()
assert not out.exists(), 'Preserve previous builds: use a new name'
project = out / 'project'
project.mkdir(parents=True)
sha = lambda f: hashlib.sha256(f.read_bytes()).hexdigest()
source_root = root
reuse = None
if a.reuse_syn_from:
    reuse = (root / a.reuse_syn_from).resolve()
    source_root = reuse / 'project'
    previous = json.loads((reuse / 'snapshot_manifest.json').read_text(encoding='utf8'))
    assert all(sha(source_root / f) == h for f, h in previous.items()
               if f not in ['impl/keyboard_adsr_process_config.json','keyboard_adsr.gprj.user']), 'Reused source snapshot changed'
    prior_log = (reuse / 'build.log').read_text(encoding='utf8', errors='replace')
    assert 'PHASE_DONE syn ' in prior_log, 'Synthesis did not finish; do not reuse a partial netlist'
    assert (source_root / 'impl/gwsynthesis/D2_keyboard_leds.vg').is_file()
    assert (source_root / 'keyboard_adsr.gprj.user').is_file(), 'Gowin flow-state metadata is required to reuse synthesis'
files = [f for f in (source_root / 'src').rglob('*') if f.is_file()]
files += [source_root / 'keyboard_adsr.gprj', source_root / 'impl/keyboard_adsr_process_config.json']
manifest = {f.relative_to(source_root).as_posix(): sha(f) for f in files}
for f in files:
    dst = project / f.relative_to(source_root)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, dst)
(out / 'input_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf8')
cfg = project / 'impl/keyboard_adsr_process_config.json'
options = json.loads(cfg.read_text(encoding='utf8'))
options['IncludePath'] = [(project / 'src').as_posix(), (project / 'src/config').as_posix()]
cfg.write_text(json.dumps(options, indent=4), encoding='utf8')
overrides = []
for item in a.option:
    key, sep, value = item.partition('=')
    assert sep and re.fullmatch(r'[a-zA-Z0-9_]+', key) and re.fullmatch(r'[a-zA-Z0-9_.-]+', value)
    overrides.append(f'set_option -{key} {value}')
tcl = '''set root [file normalize [file dirname [info script]]]
cd $root
open_project [file join $root keyboard_adsr.gprj]
set_device -device_version C GW5AST-LV138FPG676AC1/I0
set_option -top_module keyboard_top
set_option -include_path "[file join $root src];[file join $root src config]"
set_option -verilog_std sysv2017
set_option -output_base_name D2_keyboard_leds
set_option -bit_security 0
set_option -bit_incl_bsram_init 1
set_option -oreg_in_iob 1
set_option -inc_pnr 0
set_option -gen_sdf 1
'''
if reuse:
    # A new project without its successful flow state causes `run pnr` to
    # invoke synthesis implicitly. Preserve that state and avoid reissuing
    # synthesis options (which invalidate it), after the source hash checks.
    shutil.copy2(source_root / 'keyboard_adsr.gprj.user', project / 'keyboard_adsr.gprj.user')
    assert all(item.split('=', 1)[0] in ['place_option', 'route_option', 'timing_driven', 'route_maxfan']
               for item in a.option), 'Synthesis-changing overrides cannot reuse a mapped netlist'
    tcl = '''set root [file normalize [file dirname [info script]]]
cd $root
open_project [file join $root keyboard_adsr.gprj]
'''
tcl += '\n'.join(overrides) + '\n'
tcl += 'foreach stage {' + ('pnr' if reuse else 'syn pnr') + '} {\n'
tcl += '''
 puts "PHASE_START $stage [clock seconds]"
 set start [clock milliseconds]
 run $stage
 puts "PHASE_DONE $stage [expr {([clock milliseconds]-$start)/1000.0}]"
}
exit
'''
(project / 'build.tcl').write_text(tcl, encoding='utf8')
snapshot = {f.relative_to(project).as_posix(): sha(f) for f in project.rglob('*') if f.is_file()}
(out / 'snapshot_manifest.json').write_text(json.dumps(snapshot, indent=2), encoding='utf8')
reused_netlist = None
if reuse:
    shutil.copytree(source_root / 'impl/gwsynthesis', project / 'impl/gwsynthesis')
    reused_netlist = dict(from_build=str(reuse), sha256=sha(project / 'impl/gwsynthesis/D2_keyboard_leds.vg'))
started = time.time()
with (out / 'build.log').open('w', encoding='utf8') as log:
    proc = subprocess.Popen(['C:/Gowin/Gowin_V1.9.12.04_x64/IDE/bin/gw_sh.exe', str(project / 'build.tcl')],
                            cwd=project, stdout=log, stderr=subprocess.STDOUT)
    (out / 'process.json').write_text(json.dumps(dict(pid=proc.pid, started=started, project=str(project))), encoding='utf8')
    print(f'BUILD_START {a.name} pid={proc.pid}', flush=True)
    code = proc.wait()
text = (out / 'build.log').read_text(encoding='utf8', errors='replace')
changed = [f for f, h in snapshot.items() if sha(project / f) != h]
# Gowin persists explicitly selected implementation options into this JSON.
# Source, constraints, ROMs, project and executable Tcl must remain immutable.
same = all(f in ['impl/keyboard_adsr_process_config.json','keyboard_adsr.gprj.user'] for f in changed)
result = dict(name=a.name, exit_code=code, seconds=round(time.time()-started, 3), snapshot_unchanged=same,
              phase_seconds={stage:float(seconds) for stage,seconds in re.findall(r'PHASE_DONE (\w+) ([\d.]+)', text)},
              options=a.option, changed_project_files=changed, reused_netlist=reused_netlist,
              implementation_config=json.loads(cfg.read_text(encoding='utf8')),
              errors=re.findall(r'^.*ERROR.*$', text, re.M))
if reuse:
    result['synthesis_reused'] = ('GowinSynthesis start' not in text and
                                  sha(project / 'impl/gwsynthesis/D2_keyboard_leds.vg') == reused_netlist['sha256'])
tr = project / 'impl/pnr/D2_keyboard_leds.tr'
if code == 0 and tr.exists():
    from inspect_timing import inspect
    result['timing'] = inspect(tr)
    fs = tr.with_suffix('.fs')
    result['bitstream_sha256'] = sha(fs) if fs.exists() else None
(out / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf8')
print('BUILD_RESULT', json.dumps(result), flush=True)
raise SystemExit(0 if code == 0 and same and not result['errors'] else 1)
