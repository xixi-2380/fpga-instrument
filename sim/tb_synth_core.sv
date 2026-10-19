`timescale 1ns/1ps
`include "check.svh"
`include "../src/config/synth_config.svh"
// Direct event source validates logical voices independently of physical keys.
module tb_synth_core;
 parameter integer VOICES=`VOICE_COUNT,ATTACK_N=8,DECAY_N=8,SUSTAIN_N=32768;
 reg clk=0,rst=1,note_valid=0,note_on=0;
 reg [6:0] note_id=0;reg [31:0] note_fcw=0;
 always #8.138020833 clk=~clk;
 wire bck,ws,din,pa,u,frame_ce,note_ready,input_ready,gate;
 wire [VOICES-1:0] voice_active,voice_held;wire [16:0] level;
 integer checks=0,idle_nonzero;
 localparam integer RELEASE_SLOT=VOICES/2;
 synth_core #(.VOICES(VOICES),.MUTE(4),.FADE(4),.ATTACK(ATTACK_N),.DECAY(DECAY_N),.SUSTAIN(SUSTAIN_N),.RELEASE(16)) sound(
  .clk(clk),.rst(rst),.note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(note_fcw),
  .note_ready(note_ready),.input_ready(input_ready),.bck(bck),.ws(ws),.din(din),.pa_enable(pa),
  .underrun(u),.frame_ce(frame_ce),.gate(gate),.voice_active(voice_active),.voice_held(voice_held),.envelope_level(level),.note_timbre(2'd0),.effects_enable(1'b0));
 `include "poly_audio_reference.svh"
 task event_note(input bit n,input [6:0] id,input [31:0] word_fcw);begin
  @(negedge clk);note_valid=1;note_on=n;note_id=id;note_fcw=word_fcw;
  wait(note_ready);@(posedge clk);#0.001;
  @(negedge clk);note_valid=0;
 end endtask
 // Sample CE only on the source clock edge. Waiting on combinational CE
 // transitions can count delta-cycle pulses during the BCK counter rollover.
 task next_frame;begin
  @(posedge clk);while(!frame_ce)@(posedge clk);#0.002;
 end endtask
 initial begin
  #23 rst=0;wait(input_ready);more_frames(20);
  `CHECK(pa && level==0 && nonzero==0,"idle retains zero samples and existing PA policy")
  event_note(1,32,32'h016534c3);more_frames(30);
  `CHECK(voice_held==1 && level==SUSTAIN_N && nonzero>20,"first direct note sustains")
  for(integer v=1;v<VOICES;v=v+1)event_note(1,7'(32+v),32'h01000000+v*32'h0012345);
  more_frames(30);
  `CHECK(&voice_active && &voice_held,"all configured voices sustain concurrently")
  for(integer v=0;v<VOICES;v=v+1)begin
   `CHECK(sound.voice_level[v]==SUSTAIN_N,"each chord voice has independent sustained envelope")
  end
  event_note(0,7'(32+RELEASE_SLOT),0);more_frames(1);
  `CHECK($countones(voice_held)==VOICES-1 && &voice_active,"targeted release preserves independent tail")
  more_frames(30);`CHECK($countones(voice_active)==VOICES-1,"one release completes without ending peers")
  event_note(1,100,32'h0258bf26);more_frames(20);
  `CHECK(&voice_held && sound.voice_ids[RELEASE_SLOT*7+:7]==100,"free slot precedes held voices")
  event_note(1,101,32'h03519586);more_frames(20);
  `CHECK(sound.voice_ids[0+:7]==101 && &voice_held,"overflow replaces oldest held assignment")
  event_note(0,32,0);more_frames(2);
  `CHECK(&voice_held,"stale release cannot stop replacement")
  event_note(1,101,32'h0258bf26);more_frames(20);
  `CHECK(&voice_held && sound.voice_level[0]==SUSTAIN_N,"same identity retriggers with new FCW and no duplicate")
  for(integer v=0;v<VOICES;v=v+1)event_note(0,7'(32+v),0);
  event_note(0,100,0);event_note(0,101,0);
  more_frames(30);`CHECK(!gate && voice_active==0 && level==0,"all independent releases reach idle")
  idle_nonzero=nonzero;more_frames(20);
  `CHECK(nonzero==idle_nonzero && pa,"all-idle output is zero and amplifier unchanged")
  event_note(1,120,32'h0258bf26);more_frames(20);
  `CHECK(gate && sound.voice_ids[0+:7]==120,"generic synth accepts non-matrix identity")
  event_note(0,120,0);more_frames(30);
  event_note(1,120,32'h0258bf26);event_note(0,120,0);more_frames(30);
  `CHECK(!gate && voice_active==0,"short On/Off leaves no stuck voice")
  // Four frames are one full turn at FCW=1/4. Stagger allocation on
  // identical frame offsets; every voice still reaches the same phase without
  // requiring all 32 ownership searches to fit inside one idle window.
  for(integer v=0;v<VOICES;v=v+1)begin
   next_frame;wait(!sound.render_busy);
   event_note(1,7'(32+v),32'h40000000);
   if(v<VOICES-1)repeat(3)next_frame;
  end
  peak_code=0;low_code=0;more_frames(30);
  `CHECK(&voice_held && &voice_active,"coherent full-load chord occupies every logical voice")
  if(ATTACK_N==0 && DECAY_N==0 && SUSTAIN_N==65536)begin
   $display("COHERENT_PEAKS positive=%0d negative=%0d expected=%0d",peak_code,low_code,((VOICES*32767)>>>5));
   if(peak_code!=((VOICES*32767)>>>5))
    for(integer v=0;v<VOICES;v=v+1)
     $display("COHERENT_CONTEXT voice=%0d id=%0d phase=%h",v,sound.voice_ids[v*7+:7],sound.phase[v*32+:32]);
   `CHECK(peak_code==((VOICES*32767)>>>5),"coherent positive peak preserves 1/32 gain")
   `CHECK(low_code==((-(VOICES*32767))>>>5),"coherent negative peak preserves signed rounding")
  end
  // A queued input waits for the ongoing render without changing this frame.
  next_frame;repeat(24)@(posedge clk);
  event_note(1,110,32'h0258bf26);more_frames(4);
  `CHECK(&voice_held,"event offered during busy eventually completes")
  // Reset in the middle of a job must cancel all old output and phase contexts.
  next_frame;repeat(24)@(posedge clk);#3 rst=1;note_valid=0;#1;
  `CHECK(!pa && !input_ready && !gate && din==0 && level==0 && !sound.render_busy,"reset cancels in-flight render")
  #31 rst=0;wait(input_ready);more_frames(20);
  `CHECK(pa && level==0 && nonzero==0 && voice_held==0,"restart invents no note or stale sample")
  // Deterministic burst traffic while the serial reference checks every frame.
  for(integer n=0;n<256;n=n+1)begin
   event_note(1,7'((n*37+17)%128),32'h00400000+n*32'h00023456);
   if(n%3==0)event_note(0,7'((n*11+23)%128),0);
   if(n%7==0)more_frames(2);
  end
  for(integer n=0;n<128;n=n+1)event_note(0,7'(n),0);
  more_frames(30);`CHECK(!gate && voice_active==0 && level==0,"burst traffic drains all logical voices")
  $display("RENDER_METRICS voices=%0d max_delivery_cycles=%0d budget=%0d",VOICES,max_delivery_cycle,32+16*VOICES);
  $display("PASS tb_synth_core checks=%0d",checks);$finish;
 end
 initial begin #30000000;$fatal(1,"shared synth timeout");end
endmodule


