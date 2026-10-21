`timescale 1ns/1ps
`include "check.svh"
`include "../src/config/synth_config.svh"
`include "passive_matrix_model.svh"
// Full production top, including official PLLs and score/keyboard handoff.
module tb_score_audio;
 parameter integer VOICES=`VOICE_COUNT;
 reg ref_clk=0,ref_rst=1;reg [15:0] pressed=0;
 always #10 ref_clk=~ref_clk;
 tri [3:0] columns;wire [3:0] rows,selected;
 wire bck,ws,din,pa,db,dw,dd,dp;wire [5:0] leds;
 integer checks=0,score_events=0,key_events=0,finished_events=0,prior_nonzero;
 reg melody_seen=0;
 keyboard_top #(.BUTTON_DEBOUNCE_CYCLES(4),.SCORE_ENABLE(1),.SCORE_BEAT_FRAMES(8),.LED_STEP_CYCLES(4),.LOCK_N(32),
  .SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2),
  .MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.SUSTAIN(32768),.RELEASE(2))
  dut(.clk(ref_clk),.rst(ref_rst),.board_buttons_n(4'hf),.key_row(rows),.key_col(columns),
   .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),
   .DBG_BCK(db),.DBG_WS(dw),.DBG_DIN(dd),.DBG_PA_EN(dp),.led_n(leds));
 for(genvar k=0;k<4;k=k+1)assign selected[k]=(columns[k]===1'b0);
 passive_matrix_model physical_keys(pressed,selected,rows);
 wire clk=dut.audio_clk,rst=dut.audio_reset;
 wire note_valid=dut.note_valid,note_ready=dut.note_ready,note_on=dut.note_on;
 wire [6:0] note_id=dut.note_id;wire [31:0] note_fcw=dut.note_fcw;
 wire [1:0] note_timbre=dut.event_timbre;
 wire u=dut.underrun,frame_ce=dut.frame_ce;
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
 `define TIMBRE_REFERENCE
 `define AUDIO_REF_DUT dut.sound
 `include "poly_audio_reference.svh"
 `undef AUDIO_REF_DUT
 `undef TIMBRE_REFERENCE
 always @(posedge clk)if(!rst)begin
  if(dut.score_busy)begin
   `CHECK($countones(dut.voice_held)<=1,"default score has only one held melody note")
  end
  if(dut.score_busy)begin
   `CHECK(!dut.key_valid,"physical keyboard cannot enqueue notes during playback")
   if(note_valid && note_ready)begin
    score_events=score_events+1;
    `CHECK(note_id==60 || note_id==62 || note_id==64 || note_id==65 || note_id==67 || note_id==69,
      "melody identity follows pitch exactly as keyboard input")
    `CHECK(note_timbre==0,"default score shares the keyboard sine preset")
    if(note_on)melody_seen=1;
   end
  end else if(note_valid && note_ready)begin
   key_events=key_events+1;
   `CHECK(note_id==69 && note_timbre==0,"keyboard identity and selected preset resume after score")
  end
 end
 always @(bck or ws or din or pa)begin
  #0.001;`CHECK({db,dw,dd,dp}==={bck,ws,din,pa},"autoplay preserves all audio mirrors")
 end
 initial begin
  #100 ref_rst=0;wait(pa);wait(score_events>=8);
  // Hold A4 during playback: it must remain outside the synth until handoff.
  pressed=16'h0200;wait(dut.keys==16'h0200);more_frames(12);
  `CHECK(dut.score_busy && key_events==0,"held physical input cannot interrupt the score")
  wait(dut.score_done);#0.002;finished_events=score_events;
  `CHECK(score_events==84 && melody_seen,"all 42 single melody notes finish exactly once")
  `CHECK(dut.voice_held==0 && dut.voice_active==0,"score releases and tail finish before source handoff")
  wait(key_events==1);more_frames(20);
  `CHECK($countones(dut.voice_held)==1 && dut.sound.voice_ids[6:0]==69,"a key held during the score is recognized after handoff")
  pressed=0;wait(!dut.gate);more_frames(12);prior_nonzero=nonzero;more_frames(4);
  `CHECK(dut.voice_active==0 && nonzero==prior_nonzero && pa,"handoff and keyboard release return to zero without muting PA")
  `CHECK(score_events==finished_events && dut.score_done,"keyboard activity cannot restart the one-shot score")
  // Global reset replays from the beginning and cancels previous source state.
  ref_rst=1;#1;`CHECK(!pa && !note_valid && din==0,"reset cancels playback and keyboard audio")
  score_events=0;key_events=0;#99 ref_rst=0;wait(pa);wait(score_events>=1);#0.002;
  `CHECK(dut.score_busy && dut.score.pc<=1 && dut.sound.voice_ids[6:0]==60,"USR replay begins at the first score step")
  $display("SCORE_AUDIO_METRICS events=%0d max_delivery=%0d",finished_events,max_delivery_cycle);
  $display("PASS tb_score_audio checks=%0d",checks);$finish;
 end
 initial begin #30000000;$fatal(1,"score audio timeout");end
endmodule
