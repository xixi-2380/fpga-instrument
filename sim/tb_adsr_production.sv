`timescale 1ns/1ps
`include "check.svh"
`include "../src/config/keyboard_config.svh"
module tb_adsr_production;
 reg clk=0,rst=1,on=0,off=0;always #5 clk=~clk;
 wire [16:0] q;wire active;integer checks=0,expected;
 adsr_envelope dut(clk,rst,1'b1,on,off,q,active);
 task next_tick;begin @(posedge clk);#1;end endtask
 initial begin
  #12 rst=0;@(negedge clk);on=1;next_tick;
  @(negedge clk);on=0;
  for(integer i=1;i<=`ADSR_ATTACK_FRAMES;i=i+1)begin
   next_tick;expected=65536*i/`ADSR_ATTACK_FRAMES;
   `CHECK(q==expected,"production Attack exact duration")
  end
  for(integer i=1;i<=`ADSR_DECAY_FRAMES;i=i+1)begin
   next_tick;expected=65536-(65536-`ADSR_SUSTAIN_LEVEL)*i/`ADSR_DECAY_FRAMES;
   `CHECK(q==expected,"production Decay exact duration")
  end
  @(negedge clk);off=1;next_tick;@(negedge clk);off=0;
  for(integer i=1;i<=`ADSR_RELEASE_FRAMES;i=i+1)begin
   next_tick;expected=`ADSR_SUSTAIN_LEVEL-`ADSR_SUSTAIN_LEVEL*i/`ADSR_RELEASE_FRAMES;
   `CHECK(q==expected,"production Release exact duration")
  end
  `CHECK(q==0 && !active,"production idle")
  $display("PASS tb_adsr_production checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"production envelope timeout");end
endmodule
