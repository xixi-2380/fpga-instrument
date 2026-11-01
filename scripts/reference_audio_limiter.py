"""Independent window model and limiter audition vectors; pure software only."""
import argparse, collections, json, math, pathlib, random, struct, wave


class Limiter:
    def __init__(self, window=64, pre_gain=24, ceiling=29204, release_shift=12, release_hold=0):
        self.w, self.pre, self.ceiling, self.shift = window, pre_gain, ceiling, release_shift
        self.audio = collections.deque([0] * (window - 1), maxlen=window)
        self.gains = collections.deque([65536] * window, maxlen=window)
        self.release = 65536
        self.error = 0
        self.hold = release_hold; self.remaining = 0

    def step(self, sample):
        self.audio.append(sample * self.pre)
        peak = max(abs(x) for x in self.audio)
        allowed = min(65536, (self.ceiling * 65536) // max(1, peak))
        if self.hold and allowed <= self.release:
            self.release = allowed; self.error = 0; self.remaining = self.hold
        elif self.remaining:
            self.remaining -= 1
        else:
            total = 65536 - self.release + self.error
            recovery = total >> self.shift
            self.error = 0 if allowed < self.release + recovery else total % (1 << self.shift)
            self.release = min(allowed, self.release + recovery)
        self.gains.append(self.release)
        gain = sum(self.gains) // self.w
        product = self.audio[0] * gain
        result = (abs(product) >> 16) * (-1 if product < 0 else 1)
        assert abs(result) <= self.ceiling, (sample, result, peak, gain)
        return result, gain


def write_wav(path, samples):
    with wave.open(str(path), 'wb') as f:
        f.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
        f.writeframes(b''.join(struct.pack('<h', max(-32768, min(32767, x))) for x in samples))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out-dir', required=True)
    p.add_argument('--hold-samples',type=int,default=0)
    a = p.parse_args()
    out = pathlib.Path(a.out_dir); out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(71423)
    values = [0] * 80 + [1023, -1024] * 96 + [32767, -32768] * 160
    values += [int(1023 * math.sin(i * 2 * math.pi / 367)) for i in range(1100)]
    values += [rng.randrange(-32768, 32768) for _ in range(900)]
    values += [0] * 180
    if a.hold_samples: values += [0]*(a.hold_samples+300)
    model = Limiter(release_hold=a.hold_samples); packed = []
    for i, value in enumerate(values):
        reset = i == 0 or i in (323, 1000, 1800)
        if reset: model = Limiter(release_hold=a.hold_samples)
        result, gain = model.step(value)
        packed.append((int(reset) << 49) | ((value & 65535) << 33) | (gain << 16) | (result & 65535))
    (out / 'limiter_vectors.hex').write_text(f'{len(packed):016x}\n' + ''.join(f'{x:016x}\n' for x in packed), encoding='ascii')

    # Seven actual wave tables and distinct pitches; note segments include
    # short gates, sustained notes, aligned/full-load peaks, and silence.
    root = pathlib.Path(__file__).resolve().parents[1]
    tables = []
    for name in ('sine', 'flute', 'reed', 'cello', 'piano', 'guitar', 'vibraphone'):
        vals = [int(x, 16) for x in (root / f'src/rom/{name}4096.hex').read_text().split()]
        tables.append([v - 65536 if v >= 32768 else v for v in vals])
    phases = [0] * 32; source = []
    for n in range(48000):
        section = n // 6000
        voices = (1, 1, 2, 4, 8, 16, 32, 0)[section]
        total = 0
        for v in range(voices):
            phases[v] += (130.81278265 if v == 0 else 130.81278265 * 2**((v % 12)/12)) / 48000
            # 70% sustained envelope, the existing /32 gain. Fractional
            # voice terms are summed before the final conversion.
            total += tables[section % 7][int(phases[v] * 4096) % 4096] * 0.7 / 32
        source.append(max(-32768, min(32767, int(total))))
    write_wav(out/'source_original.wav', source)
    source_rms = math.sqrt(sum(x*x for x in source)/len(source))
    stats = []
    for w in (32, 64):
        for pre in (16, 24):
            m = Limiter(w, pre); rendered = []; gains = []
            for value in source:
                y, g = m.step(value); rendered.append(y); gains.append(g)
            label = f'w{w}_gain{pre}'
            write_wav(out/(label+'.wav'), rendered)
            rms = math.sqrt(sum(x*x for x in rendered)/len(rendered))
            match_gain = min(source_rms/max(1e-9,rms),32767/max(1,max(map(abs,rendered))))
            write_wav(out/(label+'_matched.wav'),[round(x*match_gain) for x in rendered])
            stats.append(dict(candidate=label,peak=max(map(abs, rendered)),rms=rms,
                              matched_rms_gain=match_gain,
                              limited_fraction=sum(g < 65536 for g in gains)/len(gains),
                              minimum_gain=min(gains)/65536,delay_samples=w-1))
    # Float model has independent queues/math and exposes Q16 quantization.
    fq = collections.deque([0.0]*63, maxlen=64)
    gq = collections.deque([1.0]*64, maxlen=64); release = 1.0
    integer = Limiter(); error = 0.0
    for x in source:
        fq.append(x*24.0); bound = min(1.0, 29204/max(1.0, max(map(abs, fq))))
        release = min(bound, release+(1-release)/4096)
        gq.append(release); y = fq[0]*sum(gq)/64
        yi, _ = integer.step(x); error = max(error, abs(y-yi))
    report = dict(vector_count=len(values),candidates=stats,
                  float_comparison_max_code_error=error,
                  selected=dict(window=64,pre_gain=24,ceiling=29204,release_shift=12),
                  scope='synthetic software audition; no hardware or user listening confirmation')
    (out/'model_summary.json').write_text(json.dumps(report,indent=2), encoding='utf8')
    print('PASS limiter window-bound model;', len(values), 'bit-exact vectors;', len(stats), 'audition candidates')


if __name__ == '__main__': main()
