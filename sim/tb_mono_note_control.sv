`timescale 1ns/1ps
`include "check.svh"
module tb_mono_note_control;
 reg clk=0,rst=1,ce=0;always #5 clk=~clk;
 reg [15:0] keys=0;wire on,off,gate;wire [31:0] fcw;wire [3:0] selected;
 integer checks=0;
 mono_note_control dut(clk,rst,ce,keys,on,off,fcw,gate,selected);
 task snapshot(input [15:0] k,input integer expect_on,expect_off,key);begin
  @(negedge clk);keys=k;ce=1;#1;
  `CHECK(on==expect_on && off==expect_off,"atomic Note On/Off at sample boundary")
  @(posedge clk);#1;
  `CHECK(gate==(|k),"gate tracks held bitmap")
  if(k!=0)begin `CHECK(selected==key,"new-key/fallback priority") end
  @(negedge clk);ce=0;#1;`CHECK(!on && !off,"events bounded by sample enable")
 end endtask
 initial begin
  #12 rst=0;
  snapshot(1,1,0,0);snapshot(1,0,0,0);
  snapshot(16'h0021,1,0,5);snapshot(16'h0001,1,0,0);
  snapshot(16'h0000,0,1,0);snapshot(0,0,0,0);
  snapshot(16'h8200,1,0,15);snapshot(16'h0200,1,0,9);
  `CHECK(fcw==32'h0258bf26,"A4 frequency word")
  snapshot(0,0,1,0);
  for(integer k=0;k<16;k=k+1)begin
   snapshot(16'h1<<k,1,0,k);
   `CHECK(fcw>0,"all sixteen notes have frequency")
   snapshot(0,0,1,0);
  end
  #2 rst=1;#1;`CHECK(!gate && !on && !off,"reset releases note")
  $display("PASS tb_mono_note_control checks=%0d",checks);$finish;
 end
 initial begin #20000;$fatal(1,"note timeout");end
endmodule
