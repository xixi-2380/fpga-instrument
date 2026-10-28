`timescale 1ns/1ps
module tb_frame_boundary;
 parameter integer HALF=20;
 reg clk=0,rst=1;always #5 clk=~clk;
 wire bck,rise,fall,frame;wire [4:0] bit_no;integer checks=0,frames=0;
 audio_timing #(.HALF_CYCLES(HALF)) dut(clk,rst,bck,rise,fall,frame,bit_no,);
 always @(negedge clk)begin
  checks++;if(frame!==(!rst && fall && bit_no==0))$fatal(1,"registered boundary shifted serial frame");
  if(frame)frames++;
 end
 initial begin
  #17 rst=0;repeat(140*HALF)@(negedge clk);#2 rst=1;#1;
  if(frame)$fatal(1,"reset must suppress frame pulse");#14 rst=0;
  repeat(140*HALF)@(negedge clk);if(frames<4)$fatal(1,"frame pulses missing");
  $display("PASS tb_frame_boundary checks=%0d HALF=%0d",checks,HALF);$finish;
 end
endmodule
