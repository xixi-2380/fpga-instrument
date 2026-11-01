"""Passive HDL trace of actual upload/player/CDC/synth/stereo I2S; no hardware."""
import argparse,hashlib,json,os,pathlib,subprocess,xml.etree.ElementTree as ET
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--timbre',type=int,default=0);p.add_argument('--out-root',default='reports/pcb_flash_debug_2026-10-28');a=p.parse_args();assert 0<=a.timbre<=6
r=pathlib.Path(__file__).resolve().parents[1];out=r/a.out_root/f'bt_trace_timbre_{a.timbre}';out.mkdir(parents=True,exist_ok=True)
paths=[r/f.get('path') for f in ET.parse(r/'keyboard_adsr.gprj').getroot().findall('./FileList/File') if f.get('enable')=='1']+[r/'sim/tb_bt_identity.sv',r/'sim/data/bt_identity_notes.hex']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs={str(f.relative_to(r)):sha(f) for f in paths};(out/'input_manifest.json').write_text(json.dumps(inputs,indent=2),encoding='utf8')
monitor=r'''
 integer trace_fd,trace_word=0,trace_bit=0,trace_channel=0;
 reg trace_sync=0,trace_ws=1;string trace_dir;
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",trace_dir))$fatal(1,"missing trace directory");
  trace_fd=$fopen({trace_dir,"/audio_trace.csv"},"w");
  $fdisplay(trace_fd,"# time_ps; SRC=kind,id,pitch,velocity; NOTE=on,id,FCW,pitch,velocity,timbre; VOICE=slot,held,FCW,pitch,gain,timbre; MIX/FX=left,right; LIMIT=left,right,gainL,gainR; PCM=left,right; I2S=channel,signed16");
 end
 always @(posedge clk)if(!dut.bluetooth_on.source_reset && dut.bluetooth_on.source_valid && dut.bluetooth_on.source_ready)
  $fdisplay(trace_fd,"SRC,%0t,%0d,%0d,%0d,%0d",$time,dut.bluetooth_on.source_kind,dut.bluetooth_on.source_id,dut.bluetooth_on.source_pitch,dut.bluetooth_on.source_velocity);
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  if(dut.note_valid && dut.note_ready)$fdisplay(trace_fd,"NOTE,%0t,%0d,%0d,%0d,%0d,%0d,%0d",$time,dut.note_on,dut.note_id,dut.note_fcw,dut.bt_pitch,dut.bt_velocity,dut.event_timbre);
  if(dut.frame_ce)for(integer v=0;v<32;v++)if(dut.voice_active[v] || dut.voice_held[v])
   $fdisplay(trace_fd,"VOICE,%0t,%0d,%0d,%0d,%0d,%0d,%0d",$time,v,dut.voice_held[v],dut.sound.voice_fcw[v*32+:32],dut.sound.voice_pitches[v*7+:7],dut.sound.voice_gains[v*9+:9],dut.sound.voice_timbres[v*3+:3]);
  if(dut.sound.stereo_mix_valid)$fdisplay(trace_fd,"MIX,%0t,%0d,%0d",$time,$signed(dut.sound.stereo_mix_l),$signed(dut.sound.stereo_mix_r));
  if(dut.sound.effect_valid)$fdisplay(trace_fd,"FX,%0t,%0d,%0d",$time,$signed(dut.sound.effect_sample),$signed(dut.sound.effect_sample_r));
  if(dut.sound.limited_valid)$fdisplay(trace_fd,"LIMIT,%0t,%0d,%0d,%0d,%0d",$time,$signed(dut.sound.limited_sample),$signed(dut.sound.stereo_on.right_limited_sample),dut.sound.limiter_gain,dut.sound.stereo_on.right_limiter_gain);
  if(dut.sound.output_valid)$fdisplay(trace_fd,"PCM,%0t,%0d,%0d",$time,$signed(dut.sound.output_sample),$signed(dut.sound.output_sample_r));
 end
 always @(posedge dut.MAX_BCLK)if(!dut.audio_reset)begin
  if(trace_sync)begin
   trace_word=((trace_word<<1)|dut.MAX_DIN)&65535;
   if(trace_bit==15)begin
    $fdisplay(trace_fd,"I2S,%0t,%0d,%0d",$time,trace_channel,trace_word>=32768?trace_word-65536:trace_word);
    trace_channel=dut.MAX_LRCLK;trace_word=0;trace_bit=0;
   end else trace_bit++;
  end else if(dut.MAX_LRCLK!=trace_ws)begin trace_sync=1;trace_channel=dut.MAX_LRCLK;trace_word=0;trace_bit=0;end
  trace_ws=dut.MAX_LRCLK;
 end
'''
bench=(r/'sim/tb_bt_identity.sv').read_text();i=bench.rfind('endmodule');bench=bench[:i]+monitor+bench[i:]
(out/'tb_bt_identity_trace.sv').write_text(bench,encoding='utf8')
sources=[f for f in paths if f.suffix=='.sv' and f.name not in ['pll_pair.sv','tb_bt_identity.sv']]+[r/'sim/pll_pair_behavioral.sv',r/'sim/pixel_pll_behavioral.sv']
vendor=pathlib.Path('C:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v').read_text(encoding='utf8');io='`timescale 1ns/1ps\n'
for name in ['ODDR','GSR']:
 start=vendor.index('module '+name+' (');end=vendor.index('endmodule',start)+len('endmodule');io+=vendor[start:end]+'\n'
(out/'gowin_io_sim.v').write_text(io,encoding='utf8')
sources += [out/'gowin_io_sim.v',out/'tb_bt_identity_trace.sv']
bins=r/'tools/mingw64/bin';env=os.environ.copy();env['PATH']=str(bins)+os.pathsep+env['PATH']
cmd=[str(bins/'iverilog.exe'),'-g2012','-grelative-include','-Isim','-s','tb_bt_identity','-P','tb_bt_identity.TIMBRE='+str(a.timbre),'-o',str(out/'trace.vvp')]+[f.as_posix() for f in sources]
c=subprocess.run(cmd,cwd=r,env=env,capture_output=True,text=True);(out/'compile.log').write_text(c.stdout+c.stderr,encoding='utf8');assert c.returncode==0,c.stderr
run=subprocess.run([str(bins/'vvp.exe'),str(out/'trace.vvp'),'+SIM_OUT_DIR='+out.as_posix()],cwd=r,env=env,capture_output=True,text=True,timeout=1800)
(out/'simulation.log').write_text(run.stdout+run.stderr,encoding='utf8')
from collections import Counter
rows=(out/'audio_trace.csv').read_text().splitlines();counts=Counter(row.split(',')[0] for row in rows if not row.startswith('#'))
passed=run.returncode==0 and 'PASS tb_bt_identity' in run.stdout and all(counts[k]>0 for k in ['SRC','NOTE','VOICE','MIX','FX','LIMIT','PCM','I2S'])
assert all(sha(r/f)==h for f,h in inputs.items()),'Trace inputs changed'
result=dict(passed=passed,timbre=a.timbre,records=counts,behavioral_pll=True,scope='passive trace of full RTL byte-upload chain; not a board capture',trace_sha256=sha(out/'audio_trace.csv'))
(out/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf8');print('TRACE_RESULT',json.dumps(result))
raise SystemExit(0 if passed else 1)
