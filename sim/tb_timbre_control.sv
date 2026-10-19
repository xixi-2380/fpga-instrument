`timescale 1ns/1ps
`include "check.svh"
module tb_timbre_control;
 reg clk=0,rst=1;reg [15:0] keys=0;wire [1:0] selected;wire effects_enabled;integer checks=0;
 always #5 clk=~clk;
 timbre_control dut(clk,rst,keys,selected,effects_enabled);
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
  keys=0;rst=0;keyset(0);keyset(16'h1008);
  `CHECK(effects_enabled && selected==0,"other diagonal enables effect without changing timbre")
  repeat(20)@(negedge clk);`CHECK(effects_enabled,"held effect chord does not repeat")
  keyset(0);keyset(16'h8001);`CHECK(selected==1 && effects_enabled,"timbre chord preserves effect state")
  keyset(0);keyset(16'h1008);`CHECK(!effects_enabled && selected==1,"effect chord toggles off")
  rst=1;#1;`CHECK(!effects_enabled && selected==0,"reset clears both controls")
  $display("PASS tb_timbre_control checks=%0d",checks);$finish;
 end
endmodule

