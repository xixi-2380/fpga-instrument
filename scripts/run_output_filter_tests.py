"""Standalone final-PCM filter checks; no EDA or hardware access.

The floating-point model uses the linear transfer equations. A separate
sample-domain integer model creates cycle/tag vectors for RTL comparison.
"""
from pathlib import Path
import argparse,cmath,hashlib,json,math,os,random,re,subprocess,time

FS=48000
Q=1<<16

def trunc(value,bits):
    return (value>>bits) if value>=0 else -((-value)>>bits)

def rounded(value):
    return ((value+Q//2)>>16) if value>=0 else -(((-value+Q//2)>>16))

def clip(value):
    return min(32767,max(-32768,value))

class IntegerModel:
    def __init__(self):self.estimate=self.previous=self.lowpass=0
    def sample(self,value,silence=False):
        if silence:
            self.estimate=self.previous=self.lowpass=0
            return 0
        error=(value<<16)-self.estimate
        self.estimate+=trunc(error,12)
        ac=error-trunc(error,13)
        self.lowpass=trunc(5*(ac+self.previous)-2*self.lowpass,3)
        self.previous=ac
        assert -(1<<31)<=self.estimate<(1<<31)
        assert abs(self.lowpass)<=81920*Q
        return clip(rounded(self.lowpass))

class FloatModel:
    def __init__(self):self.estimate=self.previous=self.lowpass=0.0
    def sample(self,value,silence=False):
        if silence:
            self.estimate=self.previous=self.lowpass=0.0
            return 0
        error=value-self.estimate
        self.estimate+=error/4096
        ac=error*(8191/8192)
        self.lowpass=0.625*(ac+self.previous)-0.25*self.lowpass
        self.previous=ac
        return clip(math.floor(self.lowpass+0.5) if self.lowpass>=0 else -math.floor(-self.lowpass+0.5))

def response(frequency):
    z=cmath.exp(-2j*math.pi*frequency/FS)
    return (8191/8192)*(1-z)/(1-(4095/4096)*z)*((5/8)*(1+z)/(1+z/4))

def fit_amplitude(values,frequency,start):
    # Least-squares sinusoid plus DC: valid even for a fractional period.
    matrix=[[0.0]*4 for _ in range(3)]
    for offset,value in enumerate(values):
        angle=2*math.pi*frequency*(start+offset)/FS
        basis=[math.sin(angle),math.cos(angle),1.0]
        for i in range(3):
            matrix[i][3]+=basis[i]*value
            for j in range(3):matrix[i][j]+=basis[i]*basis[j]
    for col in range(3):
        pivot=max(range(col,3),key=lambda n:abs(matrix[n][col]))
        matrix[col],matrix[pivot]=matrix[pivot],matrix[col]
        scale=matrix[col][col]
        for k in range(col,4):matrix[col][k]/=scale
        for row in range(3):
            if row==col:continue
            scale=matrix[row][col]
            for k in range(col,4):matrix[row][k]-=scale*matrix[col][k]
    return math.hypot(matrix[0][3],matrix[1][3])

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-bin',type=Path,required=True)
    parser.add_argument('--out-dir',type=Path,required=True)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    out=args.out_dir.resolve();out.mkdir(parents=True,exist_ok=True)
    tools=args.tool_bin.resolve()
    env=os.environ.copy();env['PATH']=str(tools)+os.pathsep+env.get('PATH','')
    files=[root/'src/audio_output_filter.sv',root/'sim/tb_audio_output_filter.sv',Path(__file__).resolve()]
    before={str(path.relative_to(root)):hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
    vectors=out/'vectors.hex';rng=random.Random(23801101)
    cycle=0;tag=0;logical=0;silenced=0;float_max_error=0;integer=IntegerModel();floating=FloatModel();due={}
    zero_results=[];measurements=[];segments=[]
    with vectors.open('w+',encoding='ascii',newline='\n') as stream:
        stream.write('000000000000000000\n')
        def offer(value=0,valid=True,reset=False,silence=False):
            nonlocal cycle,tag,logical,silenced,float_max_error,integer,floating,due
            if reset:
                integer=IntegerModel();floating=FloatModel();due={}
            elif valid:
                y=integer.sample(value,silence);reference=floating.sample(value,silence)
                if silence:
                    assert y==0
                    silenced+=1
                float_max_error=max(float_max_error,abs(y-reference))
                assert abs(y-reference)<=1,(cycle,value,y,reference)
                due[cycle+4]=(y,tag);logical+=1
            result=due.pop(cycle,None)
            word=(int(reset)<<69)|(int(valid)<<68)|(int(silence)<<67)|((value&65535)<<51)|(tag<<34)
            if result:word|=(1<<33)|((result[0]&65535)<<17)|result[1]
            stream.write(f'{word:018x}\n')
            cycle+=1
            if valid:tag=(tag+1)&0x1ffff
            return integer.lowpass,clip(rounded(integer.lowpass))
        def idle(n):
            for _ in range(n):offer(valid=False)
        def reset():
            offer(32767,reset=True);offer(-32768,reset=True)
        def zeros(name,n=65000):
            tail=[]
            for k in range(n):
                _,y=offer(0)
                if k>=n-4096:tail.append(y)
            assert set(tail)=={0},(name,set(tail))
            zero_results.append(dict(name=name,zero_input_samples=n,terminal_samples=len(tail),terminal_output_exactly_zero=True))
        reset()
        # Step and polarity changes exercise the internal headroom and output
        # saturation; long zero tails must return to digital0 with no limit cycle.
        for value in [32767,-32768,1,-1]:
            count=25000 if abs(value)>1 else 5000
            for _ in range(count):offer(value)
            zeros('dc_step_'+str(value))
        reset();offer(32767);zeros('positive_impulse')
        reset();offer(-32768);zeros('negative_impulse')
        # Continuous valid and full-scale alternating input, including tag wrap.
        for n in range(65536):offer(-32768 if n&1 else 32767)
        for n in range(40000):offer(rng.randrange(-32768,32768))
        # Back-to-back resets deliberately cancel nonempty valid pipelines.
        for n in range(300):
            offer(rng.randrange(-32768,32768),reset=n%17 in [3,4])
        reset()
        for n in range(12000):
            offer(rng.randrange(-32768,32768))
            idle(n%5)
        zeros('random_and_gap_tail');idle(8)
        # Explicit mute must keep valid/tag transactions even for deliberately
        # nonzero PCM, cancel all filter histories in sample order, and restart
        # without mixing old-state data into the first unmuted samples.
        reset()
        for _ in range(1024):offer(32767)
        for _ in range(64):offer(-32768,silence=True)
        for _ in range(1024):offer(32767)
        for n in range(4096):
            offer(rng.randrange(-32768,32768),silence=n%7<3)
            if n%3==0:idle(1)
        idle(8)
        # Each sine starts at reset; the measurement half-window begins after
        # about5.86 DC time constants. The low-cutoff points use a looser
        # bound because only a fraction/few periods fit into a short fixture.
        for frequency in [1,5,27.5,100,1000,4186.009,8000,12000,15743.3,20000,23500]:
            reset();outputs=[]
            for n in range(36000):
                value=int(math.floor(12000*math.sin(2*math.pi*frequency*n/FS)+0.5))
                _,y=offer(value);outputs.append(y)
            idle(8)
            amplitude=fit_amplitude(outputs[24000:],frequency,24000)
            expected=abs(response(frequency))
            measured=amplitude/12000
            error=abs(measured-expected)
            assert error<(0.008 if frequency<10 else 0.001),(frequency,measured,expected)
            measurements.append(dict(frequency_hz=frequency,gain=measured,gain_db=20*math.log10(max(measured,1e-12)),theoretical_gain=expected,absolute_gain_error=error))
        reset();zeros('final_zero_tail');idle(8)
        stream.seek(0);stream.write(f'{cycle:018x}\n')
    assert cycle<=1200000
    name='tb_audio_output_filter'
    command=[str(tools/'iverilog.exe'),'-g2012','-Wall','-s',name,'-o',(out/'filter.vvp').as_posix(),files[0].as_posix(),files[1].as_posix()]
    compile_run=subprocess.run(command,cwd=root,env=env,capture_output=True,text=True,encoding='utf-8')
    (out/'compile.log').write_text(compile_run.stdout+compile_run.stderr,encoding='utf-8')
    assert compile_run.returncode==0,compile_run.stderr
    start=time.monotonic()
    run=subprocess.run([str(tools/'vvp.exe'),(out/'filter.vvp').as_posix(),'+VECTORS='+vectors.as_posix()],cwd=root,env=env,capture_output=True,text=True,encoding='utf-8',timeout=900)
    log=run.stdout+run.stderr;(out/'run.log').write_text(log,encoding='utf-8')
    print(log,flush=True)
    assert run.returncode==0 and 'PASS '+name in log,log
    assert all(hashlib.sha256((root/path).read_bytes()).hexdigest()==digest for path,digest in before.items())
    report=dict(passed=True,checks=cycle,accepted_samples=logical,explicit_silence_samples=silenced,rtl_seconds=round(time.monotonic()-start,3),
                latency_edges=4,register_stages=5,source_sha256=before,
                vector_sha256=hashlib.sha256(vectors.read_bytes()).hexdigest(),
                maximum_integer_vs_float_pcm_error=float_max_error,
                zero_tail_checks=zero_results,frequency_response=measurements,
                lowpass_cutoff_hz=FS/math.pi*math.atan(5/3),dc_cutoff_hz=-(FS/(2*math.pi))*math.log(4095/4096),
                arithmetic='Signed Q16 state, truncation toward zero in feedback, symmetric final round-to-nearest and16-bit saturation',
                hardware_programmed=False,gowin_run=False,command=command)
    (out/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['passed','checks','accepted_samples','maximum_integer_vs_float_pcm_error','lowpass_cutoff_hz','dc_cutoff_hz']},indent=2),flush=True)

if __name__=='__main__':main()
