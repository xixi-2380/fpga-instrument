"""Check the physical bounds used by the Gowin LCD receiver clock model."""
import argparse
import hashlib
import json
import re
from pathlib import Path


def clock_and_end(path, kind):
    section = path.split('Data ' + kind + ' Path:', 1)[1].split('Path Statistics:', 1)[0]
    if kind == 'Arrival':
        section = section.split('Data Required Path:', 1)[0]
    edge = None
    clock = None
    endpoint = None
    for line in section.splitlines():
        fields = line.split()
        if not fields:
            continue
        try:
            at = float(fields[0])
        except ValueError:
            continue
        if 'active clock edge time' in line:
            edge = at
        if 'pixel_clock_forward/' in fields[-1] and fields[-1].endswith('/CLK'):
            clock = at
        if fields[-1].endswith('lcd_clk_obuf/O'):
            endpoint = at
    assert edge is not None and clock is not None, 'Missing physical ODDR CLK trace'
    return clock - edge, None if endpoint is None else endpoint - clock


def sdf_forward_delay(file):
    text = Path(file).read_text(encoding='utf8')
    units = re.search(r'\(TIMESCALE\s+([\d.]+)\s*(fs|ps|ns|us|ms|s)\)', text)
    assert units, 'Missing SDF timescale'
    scale = float(units[1]) * {'fs': 1e-6, 'ps': 1e-3, 'ns': 1, 'us': 1e3, 'ms': 1e6, 's': 1e9}[units[2]]
    normalize = lambda name: name.replace('\\', '')
    cells = {}
    header = r'\(\s*CELL\s+\(\s*CELLTYPE\s+"([^"]+)"\s*\)\s+\(\s*INSTANCE\s+([^\s)]+)\s*\)'
    wanted = {'lcd_on.display_driver/pixel_clock_forward': 'ODDR', 'lcd_clk_obuf': 'OBUF'}
    for m in re.finditer(header, text):
        name = normalize(m[2])
        if name not in wanted:
            continue
        assert m[1] == wanted[name], 'Unexpected clock forwarding primitive'
        depth = 0
        for end in range(m.start(), len(text)):
            if text[end] == '(':
                depth += 1
            elif text[end] == ')':
                depth -= 1
                if depth == 0:
                    cells[name] = text[m.start():end+1]
                    break
    assert set(cells) == set(wanted), 'Missing physical clock forwarding SDF cells'

    def maximum(values):
        triples = re.findall(r'\(([\d.eE:+\- ]+)\)', values)
        assert triples, 'Missing SDF min/typ/max delay'
        numbers = []
        for triple in triples:
            pieces = triple.split(':')
            assert len(pieces) == 3 and all(p.strip() for p in pieces), 'Incomplete SDF corner delay'
            numbers.extend(float(p) * scale for p in pieces)
        assert min(numbers) >= 0, 'Unexpected negative physical forward delay'
        return max(numbers)

    def arc(cell, source, destination):
        pattern = r'\(IOPATH\s+' + source + r'\s+' + destination + r'\s+((?:\([^()]*\)\s*)+)\)'
        found = re.findall(pattern, cell)
        assert found, 'Missing physical SDF arc ' + source + ' -> ' + destination
        return max(maximum(p) for p in found)

    wire = []
    for m in re.finditer(r'\(INTERCONNECT\s+(\S+)\s+(\S+)\s+((?:\([^()]*\)\s*)+)\)', text):
        if normalize(m[1]) == 'lcd_on.display_driver/pixel_clock_forward/Q0' and normalize(m[2]) == 'lcd_clk_obuf/I':
            wire.append(maximum(m[3]))
    assert len(wire) == 1, 'Missing or ambiguous Q0 -> output buffer SDF interconnect'
    stages = {'oddr_clk_q0_ns': arc(cells['lcd_on.display_driver/pixel_clock_forward'], 'CLK', 'Q0'),
              'q0_obuf_wire_ns': wire[0], 'obuf_ns': arc(cells['lcd_clk_obuf'], 'I', 'O')}
    stages['clk_to_pin_max_ns'] = round(sum(stages.values()), 6)
    assert stages['clk_to_pin_max_ns'] <= 5.000, 'SDF CLK-to-pin exceeds the 5ns hold allocation'
    stages['sdf_sha256'] = hashlib.sha256(Path(file).read_bytes()).hexdigest()
    return stages


def inspect(report, sdf=None):
    text = Path(report).read_text(encoding='utf8', errors='replace')
    body = text.split('3.3 Timing Report By Analysis Type', 2)[-1]
    groups = re.split(r'(?m)^Report Command:', body)[1:]
    values = {}
    for group in groups:
        command = group.splitlines()[0]
        setup = '-setup' in command
        hold = '-hold' in command
        if not (setup or hold):
            continue
        if '-to [get_pins {lcd_on.display_driver/pixel_clock_forward/D1}]' in command:
            key = 'slow_clk_ns' if setup else 'fast_clk_ns'
            kind = 'Required'
        else:
            continue
        paths = re.split(r'(?m)^\s*Path\d+\s*$', group)[1:]
        assert paths, 'No timing paths for ' + command
        values[key] = []
        for path in paths:
            clock, forward = clock_and_end(path, kind)
            value = clock if kind == 'Required' else forward
            assert value is not None, 'Missing forwarded clock output endpoint'
            values[key].append(round(value, 3))
    expected = {'slow_clk_ns', 'fast_clk_ns'}
    assert set(values) == expected, 'Missing independent LCD clock guard reports: ' + str(expected - set(values))
    assert min(values['slow_clk_ns']) >= 6.000, 'Slow capture clock earlier than the 6ns model'
    assert max(values['fast_clk_ns']) <= 6.000, 'Fast capture clock later than the 6ns model'
    forward = sdf_forward_delay(sdf or Path(report).with_suffix('.sdf'))
    return {'passed': True, 'source_latency_ns': 6.000, 'hold_forward_allocation_ns': 5.000, **values, **forward}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report')
    parser.add_argument('--out')
    parser.add_argument('--sdf', help='Defaults to the .sdf beside the .tr report')
    args = parser.parse_args()
    result = inspect(args.report, args.sdf)
    if args.out:
        Path(args.out).write_text(json.dumps(result, indent=2) + '\n', encoding='utf8')
    print('PASS LCD clock physical bounds ' + json.dumps(result))
