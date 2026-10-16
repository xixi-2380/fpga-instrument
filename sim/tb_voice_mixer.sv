`timescale 1ns/1ps
`include "check.svh"
module tb_voice_mixer;
 reg clk=0,rst=1,valid=0,first=0,last=0;always #5 clk=~clk;
 reg signed [23:0] term=0;wire ov;wire signed [15:0] sample;
 reg signed [63:0] sum,expected;integer checks=0;
 voice_mixer dut(clk,rst,valid,term,first,last,ov,sample);
 task send_term(input integer value,input bit f,l);begin
  @(negedge clk);valid=1;first=f;last=l;term=value;
  if(f)sum=0;sum=sum+value;expected=sum>>>8;
  if(expected>32767)expected=32767;
  if(expected < -32768)expected=-32768;
  @(posedge clk);#1;
  `CHECK(ov==l,"only last voice emits one mixed sample")
  if(l)begin `CHECK(sample==expected,"serial sum includes last voice with signed truncation and saturation") end
  @(negedge clk);valid=0;@(posedge clk);#1;
  `CHECK(!ov && dut.accumulator==sum,"bubbles preserve sum and suppress duplicate output")
 end endtask
 task mix(input integer a,b,c,d);begin
  send_term(a,1,0);send_term(b,0,0);send_term(c,0,0);send_term(d,0,1);
 end endtask
 initial begin
  #12 rst=0;
  mix(0,0,0,0);mix(1,-1,255,-255);mix(255,0,0,0);mix(-1,0,0,0);
  mix(8388607,8388607,8388607,8388607);mix(-8388608,-8388608,-8388608,-8388608);
  mix(8388607,-8388608,8388607,-8388608);
  mix(256,256,256,256);mix(-256,-256,-256,-256);
  send_term(-1,1,1);send_term(255,1,1);
  for(integer run=0;run<1000;run=run+1)begin
   for(integer v=0;v<32;v=v+1)
    send_term($signed(24'($random)),v==0,v==31);
  end
  for(integer v=0;v<32;v=v+1)send_term(8388607,v==0,v==31);
  for(integer v=0;v<32;v=v+1)send_term(-8388608,v==0,v==31);
  send_term(12345,1,0);rst=1;#1;
  `CHECK(!ov && sample==0 && dut.accumulator==0,"reset cancels a partial frame")
  @(negedge clk);valid=0;rst=0;send_term(0,1,1);
  $display("PASS tb_voice_mixer checks=%0d",checks);$finish;
 end
endmodule
