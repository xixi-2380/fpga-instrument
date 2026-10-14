`timescale 1ns/1ps
`include "check.svh"
module tb_run_leds;
 reg clk=0,ready=0,key=0;always #5 clk=~clk;
 wire [5:0] leds,fast;
 integer checks=0,cycles=0;
 run_leds #(.STEP_CYCLES(4)) dut(clk,ready,key,leds);
 run_leds #(.STEP_CYCLES(1)) boundary(clk,ready,key,fast);
 always @(posedge clk)begin
  #1;cycles=cycles+1;
  `CHECK(leds[3:0]==~(4'b0001<<((cycles/4)%4)),"exact four-light sequence and period")
  `CHECK(fast[3:0]==~(4'b0001<<(cycles%4)),"one-cycle parameter boundary")
 end
 initial begin
  #1;`CHECK(leds==6'b111110,"power-on first LED only, active low")
  repeat(32)@(negedge clk);
  ready=1;key=1;
  @(posedge clk);#2;`CHECK(leds[5:4]==2'b11,"first CDC stage not exposed")
  @(posedge clk);#2;`CHECK(leds[5:4]==2'b00,"ready and key cross in two stages")
  @(negedge clk);ready=0;
  repeat(2)@(posedge clk);#2;`CHECK(leds[5:4]==2'b01,"PLL failure clears ready, not key")
  @(negedge clk);key=0;
  repeat(2)@(posedge clk);#2;`CHECK(leds[5:4]==2'b11,"status returns off while run sequence continues")
  repeat(16)@(negedge clk);
  $display("PASS tb_run_leds checks=%0d",checks);$finish;
 end
 initial begin #10000;$fatal(1,"LED timeout");end
endmodule
