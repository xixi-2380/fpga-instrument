`timescale 1ns/1ps
`include "check.svh"
module tb_run_leds;
 reg clk=0,ready=0,key=0;always #5 clk=~clk;
 wire [5:0] leds,fast,diagnostic_leds;
 reg diag_ready=0,diag_lock1=0,diag_lock2=0,diag_reset=0,old_heartbeat;
 integer checks=0,cycles=0;
 run_leds #(.STEP_CYCLES(4),.DIAG_STEPS(0)) dut(
  .clk(clk),.audio_ready_async(ready),.key_active_async(key),
  .pll1_lock_async(1'b0),.pll2_lock_async(1'b0),.reset_active_async(1'b0),.led_n(leds));
 run_leds #(.STEP_CYCLES(1),.DIAG_STEPS(0)) boundary(
  .clk(clk),.audio_ready_async(ready),.key_active_async(key),
  .pll1_lock_async(1'b0),.pll2_lock_async(1'b0),.reset_active_async(1'b0),.led_n(fast));
 run_leds #(.STEP_CYCLES(4),.DIAG_STEPS(4)) startup_diagnostics(
  .clk(clk),.audio_ready_async(diag_ready),.key_active_async(1'b0),
  .pll1_lock_async(diag_lock1),.pll2_lock_async(diag_lock2),
  .reset_active_async(diag_reset),.led_n(diagnostic_leds));
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
  `CHECK(startup_diagnostics.diagnostic_active,"persistent not-ready enters diagnostic display")
  `CHECK(diagnostic_leds[5:1]==5'b11111,"no lock/reset/key leaves diagnostic status lights off")
  old_heartbeat=diagnostic_leds[0];repeat(4)@(negedge clk);
  `CHECK(diagnostic_leds[0]!=old_heartbeat,"reference heartbeat runs without audio clock")
  diag_lock1=1;@(posedge clk);#2;
  `CHECK(diagnostic_leds[1],"raw PLL lock first stage is not exposed")
  @(posedge clk);#2;`CHECK(!diagnostic_leds[1] && diagnostic_leds[2],"first PLL locked, second not locked")
  @(negedge clk);diag_lock2=1;diag_reset=1;
  repeat(2)@(posedge clk);#2;
  `CHECK(diagnostic_leds[3:1]==3'b000,"both raw locks and asserted user reset are visible")
  @(negedge clk);diag_ready=1;diag_reset=0;repeat(3)@(negedge clk);
  `CHECK(!startup_diagnostics.diagnostic_active && !diagnostic_leds[4],"ready exits diagnostics and lights LED4")
  `CHECK(diagnostic_leds[3:0]==leds[3:0],"ready restores original four-light sequence")
  diag_ready=0;diag_lock2=0;repeat(20)@(negedge clk);
  `CHECK(startup_diagnostics.diagnostic_active,"prolonged later lock loss re-enters diagnostics")
  `CHECK(diagnostic_leds[3:1]==3'b110,"second PLL loss distinguished from user reset")
  $display("PASS tb_run_leds checks=%0d",checks);$finish;
 end
 initial begin #10000;$fatal(1,"LED timeout");end
endmodule
