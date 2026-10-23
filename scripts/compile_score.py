"""Compile editable beat-based scores into score_player's initialized ROM.

This is an offline data converter; it never invokes FPGA synthesis/programming.
"""
import argparse
from fractions import Fraction
import math
from pathlib import Path
import re

TIMBRES={'sine':0,'flute':1,'reed':2,'cello':3,'piano':4,'guitar':5,'vibraphone':6}

def grid(value):
    number=Fraction(value)*4
    if number.denominator!=1 or number<0 or number>0xffffffff:
        raise ValueError('time must be nonnegative, on the 1/4-beat grid, and fit 32 bits')
    return int(number)

def pitch_number(value):
    if value.isdecimal():
        pitch=int(value)
    else:
        m=re.fullmatch(r'([A-G])([#b]?)(-?\d+)',value)
        if not m:
            raise ValueError('pitch must be MIDI 0..127 or a note such as C4/F#4/Bb3')
        pitch=12*(int(m[3])+1)+{'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}[m[1]]
        pitch+={'':0,'#':1,'b':-1}[m[2]]
    if not 0<=pitch<=127:
        raise ValueError('MIDI pitch outside 0..127')
    return pitch

def compile_text(text, depth=512):
    if depth<1:
        raise ValueError('ROM depth must be positive')
    events=[]; intervals={}; ending=None; note_count=0
    for line_number,line in enumerate(text.splitlines(),1):
        # Full-line comments allow sharp note names in the actual score.
        line=line.strip()
        if not line or line.startswith('#'):
            continue
        fields=line.split()
        try:
            if fields[0]=='end':
                if len(fields)!=2 or ending is not None:
                    raise ValueError('use one end BEAT line')
                ending=grid(fields[1]);continue
            if len(fields)<3:
                raise ValueError('expected START_BEAT GATE_BEATS ID:PITCH:TIMBRE ...')
            start=grid(fields[0]);gate=grid(fields[1])
            if gate==0:
                raise ValueError('note gate must be positive')
            for token in fields[2:]:
                identity,pitch,timbre=token.split(':')
                identity=int(identity);pitch=pitch_number(pitch)
                if not 0<=identity<=127:
                    raise ValueError('identity outside 0..127')
                timbre=TIMBRES[timbre] if timbre in TIMBRES else int(timbre)
                if timbre not in range(7):
                    raise ValueError('timbre must be sine/flute/reed/cello/piano/guitar/vibraphone or 0..6')
                hz=440.0*2.0**((pitch-69)/12.0)
                # Exact project sample rate, no keyboard-map dependency.
                fcw=math.floor(hz*(1<<32)/48000+0.5)
                if not 0<fcw<1<<32:
                    raise ValueError('pitch is not representable at 48 kHz')
                finish=start+gate
                if finish>0xffffffff:
                    raise ValueError('note end exceeds 32-bit score time')
                for a,b in intervals.setdefault(identity,[]):
                    if start<b and a<finish:
                        raise ValueError('overlapping notes reuse identity '+str(identity))
                intervals[identity].append((start,finish))
                payload=(identity<<34)|((timbre&3)<<32)|((timbre>>2)<<41)|fcw
                events.extend([(start,1,identity,(2<<60)|payload),
                               (finish,0,identity,(3<<60)|payload)])
                note_count+=1
        except (ValueError,ZeroDivisionError) as exc:
            raise ValueError(f'line {line_number}: {exc}') from exc
    if ending is None:
        raise ValueError('missing end BEAT line')
    events.sort() # Offs precede Ons at the same time; identities give stable ordering.
    if events and ending<events[-1][0]:
        raise ValueError('end precedes a note release')
    words=[];cursor=0
    for time,_,_,word in events+[(ending,2,0,0)]:
        if time>cursor:
            words.append((1<<60)|(time-cursor));cursor=time
        words.append(word)
    used=len(words)
    if used>depth:
        raise ValueError(f'score requires {used} ROM words, depth is {depth}')
    words.extend([0]*(depth-used))
    return words,dict(notes=note_count,events=2*note_count,words=used,depth=depth,
                      quarter_beat_ticks=ending)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--depth',type=int,default=512)
    args=parser.parse_args()
    try:
        if args.source.resolve()==args.output.resolve():
            raise ValueError('source and ROM output must be different files')
        words,summary=compile_text(args.source.read_text(encoding='utf-8-sig'),args.depth)
        # Validate everything before touching the existing output.
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(''.join(f'{w:016x}\n' for w in words),encoding='ascii')
    except (ValueError,OSError) as exc:
        parser.exit(2,f'Score error: {exc}\n')
    print('SCORE_COMPILED',summary)

if __name__=='__main__':
    main()
