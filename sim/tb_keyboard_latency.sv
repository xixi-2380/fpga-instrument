`timescale 1ns/1ps
`include "check.svh"
`include "../src/config/synth_config.svh"
`include "passive_matrix_model.svh"
module tb_keyboard_latency;
 parameter integer VOICES=`VOICE_COUNT;
 reg clk=0,rst=1;always #8.138020833 clk=~clk;
 reg [15:0] pressed=0;
 wire [3:0] rows,columns,key;wire [VOICES-1:0] voice_active,voice_held;wire [15:0] keys;
 wire bck,ws,din,pa,u,ghost,gate,key_gate,frame_ce,input_ready,note_ready,note_valid,note_on;
 wire [6:0] note_id;wire [31:0] note_fcw;wire [16:0] level;
 integer checks=0,edges=0,bits=0,word=0;
 reg rx_synced=0,previous_ws=1;
 real press_ns=0,first_code_ns=0,off_ns=0,note_on_ns=0;
 keyboard_core dut(.clk(clk),.rst(rst),.input_ready(input_ready),.note_ready(note_ready),.key_row(rows),
  .col_enable(columns),.keys(keys),.ghost(ghost),.note_valid(note_valid),.note_on(note_on),
  .note_id(note_id),.note_fcw(note_fcw),.gate(key_gate),.last_key(key));
 synth_core #(.VOICES(VOICES),.MUTE(4),.FADE(4)) sound(
  .clk(clk),.rst(rst),.note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(note_fcw),
  .note_ready(note_ready),.input_ready(input_ready),.bck(bck),.ws(ws),.din(din),.pa_enable(pa),
  .underrun(u),.frame_ce(frame_ce),.gate(gate),.voice_active(voice_active),.voice_held(voice_held),.envelope_level(level),.note_timbre(2'd0),.effects_enable(1'b0));
 passive_matrix_model model(pressed,columns,rows);
 always @(posedge gate)if(!rst && press_ns>0)note_on_ns=$realtime;
 always @(posedge bck)if(!rst)begin
  edges=edges+1;
  if(!rx_synced)begin if(ws!=previous_ws)begin rx_synced=1;bits=0;word=0;end end
  else begin
   word=((word<<1)|din)&65535;
   if(bits==15)begin
    `CHECK(ws!=previous_ws,"latency is measured from a complete I2S word")
    if(press_ns>0 && first_code_ns==0 && word!=0)first_code_ns=$realtime;
    word=0;bits=0;
   end else bits=bits+1;
  end
  previous_ws=ws;
 end
 initial begin
  #23 rst=0;wait(pa);wait(edges>=800);#103;
  press_ns=$realtime;pressed=16'h0200;
  wait(first_code_ns>0);
  `CHECK(gate && key==9 && $countones(voice_held)==1,"production scanner delivers A4 to allocator")
  `CHECK(note_on_ns-press_ns<5000000.0,"production event latency stays below 5ms")
  `CHECK(first_code_ns-press_ns<5000000.0,"production first DAC code stays below 5ms")
  #71;off_ns=$realtime;pressed=0;wait(!gate);
  `CHECK($realtime-off_ns<5000000.0,"production release-event latency stays below 5ms")
  `CHECK(!u,"polyphony adds no underrun at production scan timings")
  $display("LATENCY_US note_on=%0.3f first_code=%0.3f note_off=%0.3f",
   (note_on_ns-press_ns)/1000.0,(first_code_ns-press_ns)/1000.0,($realtime-off_ns)/1000.0);
  $display("PASS tb_keyboard_latency checks=%0d",checks);$finish;
 end
 initial begin #12000000;$fatal(1,"production latency timeout");end
endmodule


