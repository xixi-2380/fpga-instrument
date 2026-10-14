`timescale 1ns/1ps
`include "check.svh"
module tb_frame_buffer;
 reg clk=0,rst=1,fc=0,v=0;reg [15:0] l=0,r=0;always #5 clk=~clk;
 wire ready,u;wire [15:0] fl,fr;integer checks=0;
 frame_buffer dut(clk,rst,fc,v,ready,l,r,fl,fr,u);
 initial begin
  #12 rst=0;@(negedge clk);fc=1;#1;`CHECK(fl==0 && fr==0,"initial zero pair")
  @(negedge clk);fc=0;v=1;l=16'h1234;r=16'hfedc;
  @(negedge clk);v=0;`CHECK(!ready && !u,"pending backpressure")
  repeat(3) @(negedge clk);`CHECK(fl==0 && fr==0,"frame stable")
  fc=1;#1;`CHECK(fl==16'h1234 && fr==16'hfedc,"atomic pending pair")
  v=1;l=16'h8000;r=16'h7fff;
  @(negedge clk);fc=0;v=0;#1;`CHECK(fl==16'h1234 && fr==16'hfedc,"boundary consume old pair")
  @(negedge clk);fc=1;#1;`CHECK(fl==16'h8000 && fr==16'h7fff,"simultaneous new pair queued")
  @(negedge clk);fc=0;@(negedge clk);fc=1;#1;`CHECK(fl==0 && fr==0,"underflow zero")
  @(negedge clk);fc=0;`CHECK(u,"sticky underrun")
  rst=1;#1;`CHECK(!u,"reset clears underrun")
  $display("PASS tb_frame_buffer checks=%0d",checks);$finish;
 end
endmodule
