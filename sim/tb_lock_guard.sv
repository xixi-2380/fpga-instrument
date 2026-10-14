`timescale 1ns/1ps
`include "check.svh"
module tb_lock_guard;
 reg clk=0,rst=1,lock_async=0;always #5 clk=~clk;wire qualified;integer checks=0;
 lock_guard #(.STABLE_CYCLES(8)) dut(clk,rst,lock_async,qualified);
 initial begin
  #12 rst=0;lock_async=1;repeat(5) @(negedge clk);
  `CHECK(!qualified,"short lock rejected")
  lock_async=0;#1;`CHECK(!qualified,"lock loss resets qualification")
  #2 lock_async=1;repeat(9) @(negedge clk);`CHECK(!qualified,"minimum stability")
  repeat(2) @(negedge clk);`CHECK(qualified,"qualified lock")
  #1 lock_async=0;#1;`CHECK(!qualified,"immediate loss")
  $display("PASS tb_lock_guard checks=%0d",checks);$finish;
 end
endmodule
