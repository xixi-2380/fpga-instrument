`timescale 1ns/1ps
`include "check.svh"
module tb_voice_mixer;
 reg clk=0,rst=1,valid=0;always #5 clk=~clk;
 reg [95:0] samples=0;wire ov;wire signed [15:0] sample;
 reg signed [63:0] sum,expected;integer checks=0;
 voice_mixer dut(clk,rst,valid,samples,ov,sample);
 task mix(input integer a,b,c,d);begin
  @(negedge clk);samples={d[23:0],c[23:0],b[23:0],a[23:0]};valid=1;
  sum=a;sum=sum+b;sum=sum+c;sum=sum+d;expected=sum>>>8;
  if(expected>32767)expected=32767;
  if(expected < -32768)expected=-32768;
  @(posedge clk);#1;
  if((ov && sample==expected)!==1'b1)$display("MIX a=%0d b=%0d c=%0d d=%0d sum=%0d expected=%0d actual=%0d valid=%b total=%0d scaled=%0d",a,b,c,d,sum,expected,sample,ov,dut.total,dut.scaled);
  `CHECK(ov && sample==expected,"signed wide sum, one truncation and DAC saturation")
 end endtask
 initial begin
  #12 rst=0;
  mix(0,0,0,0);mix(1,-1,255,-255);mix(255,0,0,0);mix(-1,0,0,0);
  mix(8388607,8388607,8388607,8388607);
  mix(-8388608,-8388608,-8388608,-8388608);
  mix(8388607,-8388608,8388607,-8388608);
  mix(256,256,256,256);mix(-256,-256,-256,-256);
  for(integer i=0;i<1000;i=i+1)
   mix($signed(24'($random)),$signed(24'($random)),$signed(24'($random)),$signed(24'($random)));
  @(negedge clk);valid=0;@(posedge clk);#1;`CHECK(!ov,"mixer valid is a one-cycle pipeline")
  rst=1;#1;`CHECK(!ov && sample==0,"mixer reset clears output")
  $display("PASS tb_voice_mixer checks=%0d",checks);$finish;
 end
endmodule
