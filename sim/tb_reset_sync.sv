`timescale 1ns/1ps
`include "check.svh"
module tb_reset_sync;
 reg clk=0,arst=0;always #5 clk=~clk;wire rst;integer checks=0;
 reset_sync dut(clk,arst,rst);
 initial begin
  #2 arst=1;#1;`CHECK(rst==1,"async assert")
  #5 arst=0;@(posedge clk);#1;`CHECK(rst==1,"first sync edge")
  @(posedge clk);#1;`CHECK(rst==0,"second sync edge")
  #2 arst=1;#1;`CHECK(rst==1,"midcycle assertion")
  #1 arst=0;repeat(2) @(posedge clk);#1;`CHECK(rst==0,"short reset recovery")
  $display("PASS tb_reset_sync checks=%0d",checks);$finish;
 end
endmodule
