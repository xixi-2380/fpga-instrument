`timescale 1ns/1ps
`include "check.svh"
`include "../src/config/synth_config.svh"
// Generic event source, deliberately independent of keyboard dimensions/maps.
module tb_synth_core;
 parameter integer VOICES=`VOICE_COUNT;
 reg clk=0,rst=1,note_valid=0,note_on=0;
 reg [6:0] note_id=0;reg [31:0] note_fcw=0;
 always #8.138020833 clk=~clk;
 wire bck,ws,din,pa,u,frame_ce,note_ready,input_ready,gate;
 wire [VOICES-1:0] voice_active,voice_held;wire [16:0] level;
 integer checks=0,idle_nonzero;
 synth_core #(.VOICES(VOICES),.MUTE(4),.FADE(4),.ATTACK(8),.DECAY(8),.SUSTAIN(32768),.RELEASE(16)) sound(
  .clk(clk),.rst(rst),.note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(note_fcw),
  .note_ready(note_ready),.input_ready(input_ready),.bck(bck),.ws(ws),.din(din),.pa_enable(pa),
  .underrun(u),.frame_ce(frame_ce),.gate(gate),.voice_active(voice_active),.voice_held(voice_held),.envelope_level(level));
 `include "poly_audio_reference.svh"
 task event_note(input bit n,input [6:0] id,input [31:0] word_fcw);begin
  @(negedge clk);note_valid=1;note_on=n;note_id=id;note_fcw=word_fcw;
  wait(note_ready);@(posedge clk);#0.001;
  @(negedge clk);note_valid=0;
 end endtask
 initial begin
  #23 rst=0;wait(input_ready);more_frames(20);
  `CHECK(pa && level==0 && nonzero==0,"idle retains zero samples and existing PA policy")
  event_note(1,60,32'h016534c3);more_frames(30);
  `CHECK(voice_held==1 && level==32768 && nonzero>20,"first direct note sustains")
  event_note(1,64,32'h01c20d2f);event_note(1,67,32'h02173456);event_note(1,72,32'h02ca6987);
  more_frames(30);
  `CHECK(voice_active==15 && voice_held==15,"four direct notes produce four concurrent envelopes")
  for(integer v=0;v<4;v=v+1)begin `CHECK(sound.voice_level[v]==32768,"each chord voice sustains independently") end
  event_note(0,64,0);more_frames(1);
  `CHECK(voice_held==13 && voice_active==15,"released voice has an audible tail while peers remain held")
  more_frames(30);`CHECK(voice_active==13,"one Release completes without ending the chord")
  event_note(1,69,32'h0258bf26);more_frames(20);
  `CHECK(voice_held==15 && sound.voice_ids[7+:7]==69,"inactive slot reused before held voices")
  event_note(1,75,32'h03519586);more_frames(20);
  `CHECK(sound.voice_ids[0+:7]==75 && voice_held==15,"fifth note replaces oldest held assignment")
  event_note(0,60,0);more_frames(2);
  `CHECK(voice_held==15,"release of stolen old identity cannot stop new voice")
  event_note(1,75,32'h03519586);more_frames(20);
  `CHECK(voice_held==15 && sound.voice_level[0]==32768,"same identity retriggers without duplicate voice")
  event_note(0,75,0);event_note(0,69,0);event_note(0,67,0);event_note(0,72,0);
  more_frames(30);`CHECK(!gate && voice_active==0 && level==0,"all four releases reach idle")
  idle_nonzero=nonzero;more_frames(20);
  `CHECK(nonzero==idle_nonzero && pa,"all-idle output is zero and amplifier control unchanged")
  event_note(1,100,32'h0258bf26);more_frames(20);
  `CHECK(gate && sound.voice_ids[0+:7]==100,"synth accepts identity outside current matrix key range")
  event_note(0,100,0);more_frames(30);
  event_note(1,60,32'h016534c3);event_note(0,60,0);more_frames(30);
  `CHECK(!gate && voice_active==0,"sub-frame press/release does not leave a stuck voice")
  event_note(1,69,32'h0258bf26);more_frames(12);
  #3 rst=1;#1;
  `CHECK(!pa && !input_ready && !gate && din==0 && level==0,"reset clears polyphonic sound immediately")
  #31 rst=0;wait(input_ready);more_frames(20);
  `CHECK(pa && level==0 && nonzero==0 && voice_held==0,"reset invents no note events")
  $display("PASS tb_synth_core checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"four-voice synth timeout");end
endmodule
