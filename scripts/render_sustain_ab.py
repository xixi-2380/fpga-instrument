"""Compare checkpoint echo with sustain using RTL PCM, not a board recording.

The sample clock remains48kHz. Only the testbench audio clock and BCK divider
are reduced together (8 voices) to accelerate simulation. Production clock,
32-voice deadline and latency are checked by the separate production tests.
"""
import argparse,concurrent.futures,hashlib,json,os,pathlib,re,shutil,subprocess,time,wave,xml.etree.ElementTree as ET
import numpy as np
p=argparse.ArgumentParser();p.add_argument('--out-dir',required=True);p.add_argument('--baseline-cache');a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];out=r/a.out_dir;out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
base='6960804a9a62c6a73287cea9c3a0856788922f4f'
def gitfile(name):return subprocess.check_output(['git','show',base+':'+name],cwd=r)
old_xml=ET.fromstring(gitfile('keyboard_adsr.gprj'));oldpaths=[f.get('path') for f in old_xml.findall('./FileList/File') if f.get('enable')=='1']
baseline=out/'baseline'
for name in oldpaths:
 dst=baseline/name;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(gitfile(name))
newpaths=[f.get('path') for f in ET.parse(r/'keyboard_adsr.gprj').getroot().findall('./FileList/File') if f.get('enable')=='1']
inputs={name:sha(r/name) for name in newpaths};(out/'input_manifest.json').write_text(json.dumps(inputs,indent=2),encoding='utf8')
bench=r'''
`timescale 1ns/1ps
module tb_audio_ab;
 reg clk=0,rst=1,nv=0,on=0;always #40.690104167 clk=~clk;
 reg [6:0] id=60;reg [31:0] fcw=23409859;wire nr,ready,frame;integer fd,frames=0,first=-1;string dir;
 synth_core #(.VOICES(8),.STEREO_ENABLE(1),.MUTE(1),.FADE(1),
`ifdef FIXED
 .SUSTAIN_ENABLE(1),
`endif
 .OUTPUT_GAIN(24)) sound(.clk(clk),.rst(rst),.note_valid(nv),.note_on(on),.note_id(id),.note_fcw(fcw),.note_timbre(3'd0),
 .note_ready(nr),.input_ready(ready),.frame_ce(frame),.effects_enable(1'b1),.effect_mode(2'd0),.effect_cfg_valid(1'b1),
 .effect_echo_wet(9'd256),.effect_room_wet(9'd0),.effect_tremolo_depth(9'd0),.effect_tremolo_rate_hz(5'd5),
 .effect_echo_samples(17'd7200),.effect_mask(3'b001),.flush(1'b0),.output_flush(1'b0),.velocity_valid(1'b0),
 .note_velocity(7'd127),.volume_percent(7'd100),.note_pitch(id));
 defparam sound.timing.HALF_CYCLES=4;
 always @(posedge frame)if(ready)begin #1;
  $fwrite(fd,"%0d,%0d\n",$signed(sound.frame_l),$signed(sound.frame_r));
  if(first<0 && (sound.frame_l!=0 || sound.frame_r!=0))first=frames;
  frames++;
 end
 task waitframes(input integer n);integer target;begin target=frames+n;wait(frames>=target);@(negedge clk);end endtask
 task event_send(input bit pressed,input [6:0] key);begin
  @(negedge clk);on=pressed;id=key;fcw=key==60?23409859:key==64?29494575:35075158;nv=1;
  do @(posedge clk);while(!nr);@(negedge clk);nv=0;
 end endtask
 initial begin
  if(!$value$plusargs("OUT=%s",dir))$fatal(1,"missing output");fd=$fopen({dir,"/pcm.csv"},"w");
  #100 rst=0;wait(ready);waitframes(512); // settle wet/ramp before the first short tap
  $display("ONSET_FRAME %0d",frames);event_send(1,60);waitframes(96);event_send(0,60);waitframes(96);
  event_send(1,60);waitframes(96);event_send(0,60);waitframes(96);
  event_send(1,64);event_send(1,67);waitframes(96);event_send(0,64);event_send(0,67);
  waitframes(17000);$fclose(fd);$display("PASS tb_audio_ab first_sound_frame=%0d total=%0d",first,frames);$finish;
 end
 initial begin #500000000;$fatal(1,"AB timeout");end
endmodule
'''
(out/'tb_audio_ab.sv').write_text(bench,encoding='utf8');bins=r/'tools/mingw64/bin';env=os.environ.copy();env['PATH']=str(bins)+os.pathsep+env['PATH']
def run(fixed):
 name='after' if fixed else 'before';d=out/name;d.mkdir(exist_ok=True);paths=newpaths if fixed else oldpaths
 sources=[(r if fixed else baseline)/f for f in paths if f.endswith('.sv')]
 start=time.monotonic()
 if not fixed and a.baseline_cache:
  cache=r/a.baseline_cache
  assert (cache/'tb_audio_ab.sv').read_text(encoding='utf8')==bench
  assert all(sha(cache/'baseline'/f)==hashlib.sha256(gitfile(f)).hexdigest() for f in oldpaths)
  oldlog=(cache/'before/simulation.log').read_text(encoding='utf8')
  assert 'PASS tb_audio_ab' in oldlog
  for name0 in ['pcm.csv','simulation.log','compile.log']:shutil.copy2(cache/'before'/name0,d/name0)
 else:
  cmd=[str(bins/'iverilog.exe'),'-g2012','-grelative-include','-s','tb_audio_ab','-o',str(d/'run.vvp')]
  if fixed:cmd+=['-DFIXED']
  v=subprocess.run(cmd+[f.as_posix() for f in sources]+[(out/'tb_audio_ab.sv').as_posix()],cwd=r,env=env,capture_output=True)
  (d/'compile.log').write_bytes(v.stdout+v.stderr);assert v.returncode==0
  with (d/'simulation.log').open('wb') as log:
   proc=subprocess.Popen([str(bins/'vvp.exe'),str(d/'run.vvp'),'+OUT='+d.as_posix()],cwd=r,env=env,stdout=log,stderr=subprocess.STDOUT);code=proc.wait()
  assert code==0
 pcm=np.loadtxt(d/'pcm.csv',delimiter=',',dtype=np.int16)
 assert int(re.search(r'total=(\d+)',(d/'simulation.log').read_text())[1])==len(pcm)
 with wave.open(str(out/(name+'.wav')),'wb') as w:w.setnchannels(2);w.setsampwidth(2);w.setframerate(48000);w.writeframes(pcm.astype('<i2').tobytes())
 nz=np.flatnonzero(np.any(pcm!=0,axis=1));result=dict(name=name,samples=len(pcm),first_nonzero_sample=int(nz[0]) if len(nz) else None,peak=int(np.max(np.abs(pcm.astype(np.int32)))),seconds=round(time.monotonic()-start,3))
 print(json.dumps(result),flush=True);return result
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(run,[False,True]))
assert all(sha(r/f)==v for f,v in inputs.items())
assert results[1]['first_nonzero_sample']<results[0]['first_nonzero_sample']-6000
(out/'validation.json').write_text(json.dumps(dict(passed=True,baseline_commit=base,scope='RTL frame-buffer PCM,48kHz sample rate with accelerated test-only audio clock; not a board recording or production latency test',results=results),indent=2),encoding='utf8')
