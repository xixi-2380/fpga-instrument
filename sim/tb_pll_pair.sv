`timescale 1ns/1ps
`include "check.svh"
module tb_pll_pair;
 reg clk=0,rst=1,rst2=1;always #10 clk=~clk;
 wire mid,audio,l1,l2;integer checks=0;realtime t,period;
 pll_pair dut(clk,rst,rst2,mid,audio,l1,l2);
 initial begin
  #100 rst=0;wait(l1);#2000000 rst2=0;wait(l2);
  repeat(10) @(posedge audio);
  repeat(100)begin
   @(posedge audio);t=$realtime;@(posedge audio);period=$realtime-t;
   `CHECK(period>16.274 && period<16.278,"vendor model audio frequency")
  end
  @(posedge mid);t=$realtime;@(posedge mid);period=$realtime-t;
  `CHECK(period>31.247 && period<31.253,"vendor model intermediate frequency")
  $display("PASS tb_pll_pair checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"PLL timeout");end
endmodule
