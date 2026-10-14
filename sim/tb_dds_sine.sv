`timescale 1ns/1ps
`include "check.svh"
module tb_dds_sine;
 reg clk=0,rst=1,ce=0;reg [31:0] fcw=0;always #5 clk=~clk;
 wire signed [15:0] sample;wire valid;wire [31:0] phase;
 integer checks=0,i,j,a,expected;reg [31:0] model=0;real x;
 dds_sine dut(clk,rst,ce,fcw,sample,valid,phase);
 initial begin
  #12 rst=0;
  for(j=0;j<5;j=j+1) begin
   case(j) 0:fcw=0;1:fcw=32'h0258bf26;2:fcw=1;3:fcw=32'h7fffffff;4:fcw=32'hffffffff;endcase
   for(i=0;i<1000;i=i+1) begin
    @(negedge clk);ce=1;a=model[31:20];x=$sin(6.283185307179586*a/4096.0)*32767.0;
    expected=x>=0?$rtoi(x+0.5):$rtoi(x-0.5);model=model+fcw;
    @(posedge clk);#1;`CHECK(valid && phase==model && sample==expected,"DDS phase/sample")
    @(negedge clk);ce=0;@(posedge clk);#1;`CHECK(!valid && phase==model,"DDS CE hold")
   end
  end
  rst=1;#1;`CHECK(phase==0 && !valid,"DDS reset")
  $display("PASS tb_dds_sine checks=%0d",checks);$finish;
 end
endmodule
