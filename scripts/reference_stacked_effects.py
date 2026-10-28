"""Independent sample-domain model of serial effects and tap crossfades."""
import argparse
from collections import deque
import json
from pathlib import Path
import random


class StackedEffects:
    def __init__(self, production=False):
        self.capacity = 24000 if production else 32
        self.initial = 7200 if production else 8
        self.lengths = (1499, 1601, 1867, 2053) if production else (3, 5, 7, 11)
        self.memory = [0] * self.capacity
        self.position = 0
        self.current = self.next = self.initial
        self.fade = 0
        self.crossing = False
        self.combs = [deque([0] * n) for n in self.lengths]
        self.levels = [0, 0, 0]
        self.targets = [64, 64, 128]
        self.phase = 0
        self.step = 447392
        self.delay = self.initial

    def configure(self, delay, echo, room, depth, hz):
        self.delay = min(self.capacity, max(1, delay))
        self.targets = [min(256, x) for x in (echo, room, depth)]
        hz = min(10, max(1, hz))
        self.step = (hz * 2**32 + 24000) // 48000

    def sample(self, x, mask):
        a = self.memory[(self.position - self.current) % self.capacity]
        b = self.memory[(self.position - self.next) % self.capacity]
        cross = self.fade if self.crossing else 0
        delayed = ((256 - cross) * a + cross * b) // 256
        self.memory[self.position] = x
        self.position = (self.position + 1) % self.capacity
        if not self.crossing and self.delay != self.current:
            self.next, self.fade, self.crossing = self.delay, 1, True
        elif self.crossing:
            if self.fade == 255:
                self.current, self.fade, self.crossing = self.next, 0, False
            else:
                self.fade += 1
        echo, room, depth = self.levels
        y = ((256 - echo) * x + echo * delayed) // 256
        taps = []
        for line in self.combs:
            old = line.popleft()
            total = y + old
            line.append(total // 2 if total >= 0 else -((-total) // 2))
            taps.append(old)
        reverberated = sum(taps) // 4
        y = ((256 - room) * y + room * reverberated) // 256
        triangle = (self.phase >> 23) & 255
        if self.phase & 0x80000000:
            triangle = 255 - triangle
        gain = 256 - depth + triangle * depth // 256
        y = y * gain // 256
        assert -32768 <= y <= 32767
        self.phase = (self.phase + self.step) & 0xFFFFFFFF
        for i, level in enumerate(self.levels):
            target = self.targets[i] if mask & (1 << i) else 0
            self.levels[i] = level + (level < target) - (level > target)
        return y


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out-dir', required=True)
    parser.add_argument('--production', action='store_true')
    args = parser.parse_args()
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    model = StackedEffects(args.production)
    rng = random.Random(20261025)
    rows = []
    configuration = [model.initial, 64, 64, 128, 5]

    def emit(x, mask, cfg=False):
        if cfg:
            model.configure(*configuration)
        y = model.sample(x, mask)
        rows.append([0, int(cfg), mask, *configuration, x, y])
        return y

    def reset():
        nonlocal model
        rows.append([1, 0, 0, *configuration, 0, 0])
        model = StackedEffects(args.production)

    for mask in range(8):
        for i in range(750):
            emit(rng.randint(-32768, 32767), mask, cfg=i == 0)
    # Requests arriving in the middle of previous tap crossfades coalesce.
    choices = [960, 24000, 7200, 12000, 48] if args.production else [1, 32, 8, 19, 3]
    for i in range(3000):
        cfg = i % 17 == 0
        if cfg:
            configuration = [choices[(i // 17) % len(choices)],
                             rng.randrange(300), rng.randrange(300), rng.randrange(300), rng.randrange(16)]
        emit(rng.randint(-32768, 32767), (i // 89) % 8, cfg)
    reset()
    # Dirty physical RAM must be masked across reset; exact bypass endpoints.
    for x in [0, -32768, 32767, 0] * 80:
        emit(x, 0)
    configuration = [model.initial, 64, 64, 128, 5]
    for i in range(700):
        emit(10000, 7, cfg=i == 0)
    # Complete serial history and feedback tails eventually return to zero.
    for i in range(model.capacity + max(model.lengths) * 32 + 1024):
        y = emit(0, 7)
    assert y == 0
    reset()
    for i in range(100):
        assert emit(0, 7) == 0
    (out / 'stacked_vectors.txt').write_text('\n'.join(' '.join(map(str, row)) for row in rows) + '\n')
    (out / 'model.json').write_text(json.dumps(dict(production=args.production,
        vectors=len(rows),capacity=model.capacity,combs=model.lengths), indent=2))
    print(f'Generated {len(rows)} independent stacked-effect vectors, production={args.production}')


if __name__ == '__main__':
    main()
