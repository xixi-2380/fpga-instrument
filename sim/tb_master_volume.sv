`timescale 1ns/1ps
`include "check.svh"
module tb_master_volume;
 reg clk=0,rst=1,v=0;always #5 clk=~clk;
 reg signed [15:0] sample=10000;reg [6:0] percent=100;
 wire ov;wire signed [15:0] result;integer checks=0;
 master_volume dut(clk,rst,v,sample,percent,ov,result);
 task samples(input integer n);begin repeat(n)@(negedge clk);end endtask
 initial begin #12 rst=0;v=1;samples(4);
  `CHECK(result==10000,"100 percent is bit exact")
  percent=50;samples(260);`CHECK(result==5000,"50 percent applies after settling")
  sample=-10000;samples(4);`CHECK(result==-5000,"signed gain preserves negative samples")
  percent=0;samples(260);`CHECK(result==0,"zero percent mutes")
  percent=100;samples(260);sample=-32768;samples(4);
  `CHECK(result==-32768,"full-scale negative remains exact")
  sample=32767;samples(4);`CHECK(result==32767,"full-scale positive remains exact")
  v=0;samples(4);`CHECK(!ov,"valid is delayed with the matching PCM")
  $display("PASS tb_master_volume checks=%0d",checks);$finish;
 end
endmodule
