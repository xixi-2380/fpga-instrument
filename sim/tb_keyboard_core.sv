`timescale 1ns/1ps
`include "check.svh"
`include "../src/config/synth_config.svh"
`include "passive_matrix_model.svh"
module tb_keyboard_core;
 parameter integer VOICES=`VOICE_COUNT;
 reg clk=0,rst=1;always #8.138020833 clk=~clk;
 reg [15:0] pressed=0;
 wire [3:0] rows,columns,key;wire [VOICES-1:0] voice_active,voice_held;wire [15:0] keys;
 wire bck,ws,din,pa,u,ghost,gate,key_gate,frame_ce,input_ready,note_ready,note_valid,note_on;
 wire [6:0] note_id;wire [31:0] note_fcw;wire [16:0] level;
 integer checks=0,f;string sim_out_dir;
 keyboard_core #(.SLOT_CYCLES(8),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(3)) dut(
  .clk(clk),.rst(rst),.input_ready(input_ready),.note_ready(note_ready),.key_row(rows),
  .col_enable(columns),.keys(keys),.ghost(ghost),.note_valid(note_valid),.note_on(note_on),
  .note_id(note_id),.note_fcw(note_fcw),.gate(key_gate),.last_key(key));
 synth_core #(.VOICES(VOICES),.MUTE(4),.FADE(4),.ATTACK(8),.DECAY(8),.SUSTAIN(32768),.RELEASE(16)) sound(
  .clk(clk),.rst(rst),.note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(note_fcw),
  .note_ready(note_ready),.input_ready(input_ready),.bck(bck),.ws(ws),.din(din),.pa_enable(pa),
  .underrun(u),.frame_ce(frame_ce),.gate(gate),.voice_active(voice_active),.voice_held(voice_held),.envelope_level(level));
 passive_matrix_model model(pressed,columns,rows);
 `include "poly_audio_reference.svh"
 always @(posedge bck)begin
  #0.004;if(!rst && frame_complete)$fdisplay(f,"%0d,%0d,%0d,%0d,%0d,%0d,%0d",frames,keys,key,level,ghost,voice_held,last_sample);
 end
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",sim_out_dir))sim_out_dir="reports/sim/current";
  f=$fopen({sim_out_dir,"/D2_samples.csv"},"w");
  if(f==0)$fatal(1,"Cannot open simulation sample output");
  $fdisplay(f,"frame,keys,last_key,envelope_max,ghost,voice_held,sample");
  #23 rst=0;more_frames(20);`CHECK(nonzero==0 && !gate,"idle matrix remains silent")
  for(integer k=0;k<16;k=k+1)begin
   pressed=16'h1<<k;more_frames(24);
   `CHECK(gate && key==k && $countones(voice_held)==1,"all sixteen physical positions reach one distinct voice")
   pressed=0;more_frames(24);`CHECK(!gate && level==0 && voice_active==0,"each release fully finishes")
  end
  `CHECK(nonzero>100,"keys produce serial audio")
  pressed=16'h0001;more_frames(24);pressed=16'h0201;more_frames(24);
  `CHECK(key==9 && $countones(voice_held)==2,"new A4 joins held C4 instead of overriding it")
  pressed=16'h0001;more_frames(24);
  `CHECK($countones(voice_held)==1 && sound.voice_level[0]==32768,"one release leaves held C4 sustained")
  pressed=0;more_frames(24);
  pressed=16'h1111;more_frames(24);
  `CHECK(!ghost && voice_held==15 && voice_active==15,"four keys in one physical column play simultaneously")
  pressed=16'h1101;more_frames(24);
  `CHECK($countones(voice_held)==3 && $countones(voice_active)==3,"independent physical release leaves three voices")
  // Two disconnected star groups permit five physical keys without a rectangle.
  pressed=0;more_frames(24);
  pressed=16'h0001;more_frames(20);pressed=16'h0003;more_frames(20);
  pressed=16'h0007;more_frames(20);pressed=16'h0087;more_frames(20);
  `CHECK(!ghost && voice_held==15,"four sequential physical keys occupy the available voices")
  pressed=16'h0887;more_frames(20);
  if(VOICES==4)begin
   `CHECK(!ghost && voice_held==15 && sound.voice_ids[0+:7]==71,"fifth physical key replaces oldest only in four-voice mode")
  end else begin
   `CHECK(!ghost && voice_held==31 && sound.voice_ids[4*7+:7]==71,"five unambiguous keys have independent voices")
  end
  pressed=16'h0886;more_frames(20);
  if(VOICES==4)begin
   `CHECK(voice_held==15 && sound.voice_ids[0+:7]==71,"old physical release preserves replacement")
  end else begin
   `CHECK($countones(voice_held)==4 && sound.voice_ids[4*7+:7]==71,"C4 release leaves four independent physical notes")
  end
  pressed=16'h0013;more_frames(24);
  `CHECK(ghost && !gate && level==0,"ambiguous rectangle releases every voice")
  pressed=16'h0002;more_frames(24);
  `CHECK(!ghost && gate && key==1,"valid input recovers after ambiguity")
  #3 rst=1;#1;`CHECK(!pa && din==0 && columns==0,"reset while playing clears audio and scanning")
  #31 rst=0;more_frames(30);
  `CHECK(gate && key==1 && level!=0,"held key resumes after reset")
  $fclose(f);$display("PASS tb_keyboard_core checks=%0d",checks);$finish;
 end
 initial begin #30000000;$fatal(1,"polyphonic keyboard timeout");end
endmodule
