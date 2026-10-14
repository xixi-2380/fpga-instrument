`timescale 1ns/1ps
`include "check.svh"
`include "synth_config.svh"
module tb_audio_timing;
 reg clk=0,rst=1; always #5 clk=~clk;
 wire bck,rise_ce,fall_ce,frame_ce;wire [4:0] bit_index;
 integer checks=0,cycle=0,last_edge=-1,last_frame=-1,frames=0,expected_bit=0;
 audio_timing dut(clk,rst,bck,rise_ce,fall_ce,frame_ce,bit_index);
 always @(posedge clk) if(!rst) begin
  cycle=cycle+1;
  if(rise_ce||fall_ce) begin
   if(last_edge>=0) begin `CHECK(cycle-last_edge==20,"BCK half period") end
   last_edge=cycle;
  end
  if(fall_ce) begin `CHECK(bit_index==expected_bit,"bit index") expected_bit=(expected_bit+1)%32; end
  if(frame_ce) begin
   if(last_frame>=0) begin `CHECK(cycle-last_frame==1280,"frame period") end
   last_frame=cycle;frames=frames+1;
  end
 end
 initial begin
  `CHECK(`AUDIO_HZ%(`SAMPLE_HZ*`WORD_BITS*4)==0,"exact audio division")
  `CHECK(`FRAME_CYCLES*`SAMPLE_HZ==`AUDIO_HZ,"sample frequency contract")
  #23 rst=0;wait(frames==100);#2 rst=1;#1;
  `CHECK(bck===1'b1 && bit_index==0,"async reset")
  last_edge=-1;last_frame=-1;expected_bit=0;#17 rst=0;
  wait(frames==105);$display("PASS tb_audio_timing checks=%0d",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
