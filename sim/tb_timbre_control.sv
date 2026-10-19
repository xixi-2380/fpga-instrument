`timescale 1ns/1ps
`include "check.svh"
module tb_timbre_control;
 reg clk=0,rst=1;reg [15:0] keys=0;wire [1:0] selected;integer checks=0;
 always #5 clk=~clk;
 timbre_control dut(clk,rst,keys,selected);
 task keyset(input [15:0] k);begin @(negedge clk);keys=k;repeat(4)@(negedge clk);end endtask
 initial begin
  #12 rst=0;#1;`CHECK(selected==0,"reset selects sine")
  keyset(16'h0001);`CHECK(selected==0,"ordinary note does not switch")
  keyset(16'h8001);`CHECK(selected==1,"opposite corners select flute")
  repeat(20)@(negedge clk);`CHECK(selected==1,"held chord changes only once")
  keyset(16'h8000);keyset(16'h8001);`CHECK(selected==1,"partial release cannot repeat")
  keyset(0);keyset(16'h8003);`CHECK(selected==1,"larger chord does not select")
  keyset(0);keyset(16'h8001);`CHECK(selected==2,"full release arms next selection")
  keyset(0);keyset(16'h8001);`CHECK(selected==0,"selection wraps to sine")
  rst=1;#1;`CHECK(selected==0,"reset clears selection")
  $display("PASS tb_timbre_control checks=%0d",checks);$finish;
 end
endmodule
