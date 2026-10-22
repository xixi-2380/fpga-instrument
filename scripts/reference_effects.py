"""Independent sample-domain integer model; emits vectors, never runs FPGA tools."""
from collections import deque
from pathlib import Path
import argparse
import json
import random


class EffectsReference:
    def __init__(self, production=False):
        self.delays = (1499, 1601, 1867, 2053) if production else (3, 5, 7, 11)
        self.echo = deque([0] * (7200 if production else 8))
        self.combs = [deque([0] * n) for n in self.delays]
        self.step = 447392 if production else 0x10000000
        self.phase = self.fade = self.active = 0

    def sample(self, x, enabled, mode):
        delayed = self.echo.popleft()
        self.echo.append(x)
        taps = []
        for line in self.combs:
            old = line.popleft()
            total = x + old
            line.append(total // 2 if total >= 0 else -((-total) // 2))
            taps.append(old)
        room = sum(taps) // 4
        triangle = (self.phase >> 23) & 255
        if self.phase & 0x80000000:
            triangle = 255 - triangle
        tremolo = x * (128 + triangle // 2) // 256
        self.phase = (self.phase + self.step) & 0xFFFFFFFF
        wet = ((192 * x + 64 * room) // 256 if self.active == 1 else
               tremolo if self.active == 2 else (192 * x + 64 * delayed) // 256)
        value = ((256 - self.fade) * x + self.fade * wet) // 256
        assert -32768 <= value <= 32767
        requested = mode if mode in (1, 2) else 0
        if requested != self.active:
            if self.fade:
                self.fade -= 1
            else:
                self.active = requested
        elif enabled:
            self.fade = min(256, self.fade + 1)
        else:
            self.fade = max(0, self.fade - 1)
        return value


def generate(production=False):
    model = EffectsReference(production)
    rows = [1 << 35]
    rng = random.Random(20261022)

    def emit(x, enabled=True, mode=0):
        value = model.sample(x, enabled, mode)
        rows.append((mode << 33) | (int(enabled) << 32) | ((x & 65535) << 16) | (value & 65535))
        return value

    for _ in range(350):
        emit(0)
    emit(20000)
    n = 7200 if production else 8
    for index in range(1, n + 3):
        value = emit(0)
        assert value == (5000 if index == n else 0), (index, value)
    for index in range(1200):
        emit(rng.randint(-32768, 32767), index % 173 < 90, (index // 71) % 4)
    for _ in range(600):
        emit(0, True, 1)
    emit(-32768, True, 1)
    for _ in range(18 * max(model.delays)):
        tail = emit(0, True, 1)
    assert tail == 0, "negative feedback residue must decay to exact silence"
    for _ in range(600):
        emit(0, True, 2)
    tremolo_codes = [emit(16384, True, 2) for _ in range(11000 if production else 64)]
    assert max(tremolo_codes) > min(tremolo_codes) + 4000
    for index in range(1200):
        emit((-32768, 32767, 0, -1, 1)[index % 5], index % 41 < 20, (index // 113) % 4)
    rows.append(1 << 35)
    model = EffectsReference(production)
    for _ in range(64):
        assert emit(0, True, 1) == 0, "reset must hide dirty RAM"
    for _ in range(600):
        emit(rng.randint(-32768, 32767), False, 0)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--production', action='store_true')
    args = parser.parse_args()
    rows = generate(args.production)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(''.join(f'{x:09x}\n' for x in rows), encoding='ascii')
    print(json.dumps({'vectors': len(rows), 'production': args.production}))


if __name__ == '__main__':
    main()
