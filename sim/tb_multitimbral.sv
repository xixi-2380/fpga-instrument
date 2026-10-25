`timescale 1ns/1ps
`include "check.svh"
`include "../src/config/synth_config.svh"
module tb_multitimbral;
 parameter integer VOICES=32;
 reg clk=0,rst=1,note_valid=0,note_on=0;reg [6:0] note_id=0;
 reg [31:0] note_fcw=0;reg [1:0] note_timbre=0;
 always #8.138020833 clk=~clk;
 wire bck,ws,din,pa,u,frame_ce,note_ready,input_ready,gate;
 wire [VOICES-1:0] voice_active,voice_held;wire [16:0] level;
 integer checks=0,isolated_nonzero;
 // Isolate legacy voice/effect arithmetic; production conditioned output is
 // covered by tb_output_gain, tb_bluetooth_top and tb_bt_short_audio.
 synth_core #(.OUTPUT_ENABLE(0),.VOICES(VOICES),.MUTE(4),.FADE(4),.ATTACK(8),.DECAY(8),.SUSTAIN(32768),.RELEASE(16)) sound(
 .clk(clk),.rst(rst),.note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(note_fcw),
 .note_ready(note_ready),.input_ready(input_ready),.bck(bck),.ws(ws),.din(din),.pa_enable(pa),
 .underrun(u),.frame_ce(frame_ce),.gate(gate),.voice_active(voice_active),.voice_held(voice_held),
 .envelope_level(level),.note_timbre(note_timbre),.effects_enable(1'b0));
 function real waveform(input integer t,input real a);
 case(t)
 1:waveform=$sin(a)+0.20*$sin(2*a)+0.08*$sin(3*a);
 2:waveform=$sin(a)+0.60*$sin(3*a)+0.30*$sin(5*a)+0.15*$sin(7*a);
 default:waveform=$sin(a);
 endcase
 endfunction
 real peaks[0:2],value;
 initial for(integer t=0;t<3;t=t+1)begin
  peaks[t]=0;
  for(integer n=0;n<4096;n=n+1)begin
   value=waveform(t,6.283185307179586*n/4096.0);if(value<0)value=-value;
   if(value>peaks[t])peaks[t]=value;
  end
 end
 // Uses the same independent arithmetic/serial scoreboard, extended with harmonic equations.
 `define TIMBRE_REFERENCE
 `include "poly_audio_reference.svh"
 `undef TIMBRE_REFERENCE
 task event_note(input bit onoff,input integer id,input integer t);begin
  @(negedge clk);note_valid=1;note_on=onoff;note_id=id;note_timbre=t;note_fcw=32'h01000000+id*32'h12345;
  wait(note_ready);@(posedge clk);#0.001;@(negedge clk);note_valid=0;
 end endtask
 initial begin
  #23 rst=0;wait(input_ready);more_frames(10);
  // A single held key in any preset cannot create a full-scale impulse.
  for(integer t=0;t<3;t=t+1)begin
   peak_code=0;low_code=0;
   event_note(1,69,t);more_frames(40);
   `CHECK($countones(voice_held)==1 && $countones(voice_active)==1,
    "isolated preset starts exactly one voice")
   `CHECK(peak_code<=1023 && low_code>=-1024 && (peak_code>0 || low_code<0),
    "every isolated timbre stays within one voice gain, without full-scale spikes")
   event_note(0,69,t);more_frames(30);
   `CHECK(!gate && voice_active==0 && level==0,"each preset release drains to idle")
   isolated_nonzero=nonzero;more_frames(4);
   `CHECK(nonzero==isolated_nonzero,"no residual codes after isolated preset release")
  end
  // Reproduce ordinary two-note attacks, with independent note/voice state.
  // Every serial word remains checked against the independent waveform model.
  for(integer t=0;t<3;t=t+1)for(integer burst=0;burst<3;burst=burst+1)begin
   peak_code=0;low_code=0;
   event_note(1,60,t);event_note(1,69,t);more_frames(24);
   `CHECK($countones(voice_held)==2 && $countones(voice_active)==2,
    "ordinary two-note attacks preserve exactly two independent voices")
   `CHECK(peak_code<=2047 && low_code>=-2048,
    "two-note transient never exceeds two voices of gain")
   event_note(0,60,t);more_frames(20);
   `CHECK($countones(voice_held)==1 && $countones(voice_active)==1,
    "releasing one of a pair leaves the other note intact")
   event_note(0,69,t);more_frames(24);
   `CHECK(!gate && voice_active==0,"repeated two-note attacks drain cleanly")
  end
  for(integer v=0;v<VOICES;v=v+1)event_note(1,32+v,v%3);
  more_frames(25);
  `CHECK(&voice_active && &voice_held,"all 32 mixed-timbre voices sustain")
  for(integer v=0;v<VOICES;v=v+1)begin
   `CHECK(sound.voice_timbres[v*3+:3]==v%3,"accepted timbre stays with its voice")
  end
  note_timbre=2;more_frames(10);
  for(integer v=0;v<VOICES;v=v+1)begin
   `CHECK(sound.voice_timbres[v*3+:3]==v%3,"selection alone does not alter held notes")
  end
  event_note(0,32,0);more_frames(3);
  `CHECK(sound.voice_timbres[1:0]==0 && voice_active[0],"release preserves original timbre during tail")
  more_frames(20);event_note(1,100,2);more_frames(20);
  `CHECK(sound.voice_timbres[1:0]==2,"reused slot captures new timbre")
  event_note(1,100,1);more_frames(20);
  `CHECK(sound.voice_timbres[1:0]==1,"same-note retrigger accepts selected timbre")
  for(integer v=0;v<VOICES;v=v+1)event_note(0,32+v,0);
  event_note(0,100,0);more_frames(25);
  `CHECK(voice_active==0 && !u,"all timbres release to idle without underrun")
  $display("PASS tb_multitimbral checks=%0d delivery=%0d",checks,max_delivery_cycle);$finish;
 end
 initial begin #40000000;$fatal(1,"multitimbral timeout");end
endmodule

