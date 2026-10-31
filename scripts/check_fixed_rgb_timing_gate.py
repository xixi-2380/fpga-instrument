"""Check the actual fixed-key/RGB implementation, clock bounds and source pairing."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from inspect_timing import inspect
from check_lcd_clock_timing import inspect as inspect_lcd

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('build_dir')
p.add_argument('--out')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
build = (root / a.build_dir).resolve()
project = build / 'project'
base = project / 'impl/pnr/D2_keyboard_leds'
sha = lambda f: hashlib.sha256(f.read_bytes()).hexdigest()
result = dict(build=str(build), requirements={'ref_clk':50.0, 'audio_clk':61.44, 'pixel_clk':35.0}, checks={})
checks = result['checks']
completion = build/'result.json'
if completion.is_file():
    run = json.loads(completion.read_text(encoding='utf8'))
    checks['native_build_completed_cleanly'] = (run.get('exit_code') == 0 and
        run.get('snapshot_unchanged') is True and not run.get('errors'))
    result['phase_seconds'] = run.get('phase_seconds', {})
else:
    checks['native_build_completed_cleanly'] = False
timing = inspect(base.with_suffix('.tr'))
result['timing'] = timing
checks['setup_hold_endpoints_zero'] = timing['counts'] == {'Setup':0, 'Hold':0}
tns = timing['tns']
required_pairs = {(clock, analysis) for clock in ['ref_clk','mid_clk','audio_clk','pixel_clk','lcd_pclk']
                  for analysis in ['setup','hold']}
checks['all_clock_tns_present_and_zero'] = (
    required_pairs.issubset({(v['clock'],v['analysis']) for v in tns}) and
    all(v['tns'] == 0 and v['endpoints'] == 0 for v in tns))
checks['all_fmax_meet_unchanged_targets'] = all(
    clock in timing['fmax'] and abs(timing['fmax'][clock]['target']-target)<0.001 and
    timing['fmax'][clock]['actual'] >= target for clock,target in result['requirements'].items())
checks['all_reported_paths_nonnegative'] = bool(timing['path_tables']) and timing['all_reported_paths_nonnegative']
checks['all_internal_domains_present_nonnegative'] = all(timing['internal_wns'].get(c,-1) >= 0 for c in result['requirements'])
checks['pulse_width_checked_nonnegative'] = bool(timing['pulse_width_slacks']) and timing['pulse_width_pass']
try:
    result['lcd_physical'] = inspect_lcd(base.with_suffix('.tr'), base.with_suffix('.sdf'))
    checks['lcd_forward_clock_same_build_sta_sdf'] = result['lcd_physical']['passed']
except (AssertionError, ValueError, KeyError, FileNotFoundError) as error:
    result['lcd_physical_error'] = str(error)
    checks['lcd_forward_clock_same_build_sta_sdf'] = False

manifest = json.loads((build/'input_manifest.json').read_text(encoding='utf8'))
design = {f:h for f,h in manifest.items() if f.startswith('src/') or f=='keyboard_adsr.gprj'}
checks['snapshot_sources_unchanged'] = all((project/f).is_file() and sha(project/f)==h for f,h in design.items())
checks['workspace_sources_match_build'] = all((root/f).is_file() and sha(root/f)==h for f,h in design.items())
pins = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+)\s*;', (project/'src/keyboard.cst').read_text(encoding='utf8')))
original_cst = subprocess.check_output(['git','show','4a0ea05:src/keyboard.cst'], cwd=root).decode('utf8')
original = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+)\s*;', original_cst))
checks['74_unique_pins_unchanged'] = pins==original and len(pins)==74 and len(set(pins.values()))==74 and pins.get('rgb_led_data')=='P25'
rpt = base.with_suffix('.rpt.txt').read_text(encoding='utf8', errors='replace')
actual = {}
for port in pins:
    match = re.search(r'^'+re.escape(port)+r'\s*\|\s*[^|]*\|\s*([A-Z]+\d+)/\d+\s*\|\s*(Y|N)', rpt, re.M)
    if match:
        actual[port] = {'ball':match[1], 'fixed':match[2]}
checks['all_74_implemented_pins_match'] = all(actual.get(port)=={'ball':ball,'fixed':'Y'} for port,ball in pins.items())
result['implemented_pins'] = actual
resources = {}
for key in ['Logic','Register','BSRAM','DSP','PLL']:
    match = re.search(r'^\s*'+key+r'\s*\|\s*(\d+(?:\.\d+)?)/(\d+)', rpt, re.M)
    if match:
        resources[key] = {'used':float(match[1]),'available':int(match[2])}
result['resources'] = resources
checks['three_plls_and_resources_fit'] = (resources.get('PLL',{}).get('used')==3 and
    all(key in resources and 0<resources[key]['used']<=resources[key]['available'] for key in ['Logic','Register','BSRAM','DSP']))
fs = base.with_suffix('.fs')
checks['bitstream_present'] = fs.is_file() and fs.stat().st_size>0
if checks['bitstream_present']:
    result['bitstream_sha256'] = sha(fs)
result['passed'] = all(checks.values())
dest = Path(a.out) if a.out else build/'acceptance.json'
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(json.dumps(result,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in result.items() if k not in ['timing','implemented_pins']},indent=2))
raise SystemExit(0 if result['passed'] else 1)
