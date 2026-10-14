`timescale 1ns/1ps
`include "check.svh"
module tb_sine_rom;
 reg clk=0,ce=0;reg [11:0] addr=0;always #5 clk=~clk;
 wire signed [15:0] q;integer checks=0,i,expected;real x;
 sine_rom dut(clk,ce,addr,q);
 initial begin
  for(i=0;i<4096;i=i+1) begin
   @(negedge clk);ce=1;addr=i;@(posedge clk);#1;
   x=$sin(6.283185307179586*i/4096.0)*32767.0;
   expected=x>=0?$rtoi(x+0.5):$rtoi(x-0.5);
   `CHECK(q==expected,"ROM reference sinusoid")
  end
  @(negedge clk);ce=0;addr=0;@(posedge clk);#1;`CHECK(q==expected,"ROM CE hold")
  $display("PASS tb_sine_rom checks=%0d",checks);$finish;
 end
endmodule
