`timescale 1ns/1ps
`include "check.svh"
module tb_timbre_control;
 parameter integer N=4;
 reg clk=0,rst=1;reg [3:0] buttons_n=4'hf;
 wire [1:0] selected;wire effects_enabled;integer checks=0,presses=0;
 always #8.138020833 clk=~clk;
 timbre_control #(.DEBOUNCE_CYCLES(N)) dut(clk,rst,buttons_n,selected,effects_enabled);
 always @(posedge clk)if(!rst)presses=presses+$countones(dut.press_event);
 task settle(input [3:0] value);begin
  @(negedge clk);buttons_n=value;repeat(N+6)@(negedge clk);
 end endtask
 initial begin
  #23 rst=0;settle(4'hf);
  `CHECK(selected==0 && !effects_enabled && presses==0,"released startup is sine, dry, no events")
  // Less than the qualification interval must not change a control.
  if(N>1)begin
   @(negedge clk);buttons_n=4'hd;repeat(N-1)@(negedge clk);buttons_n=4'hf;
   repeat(N+6)@(negedge clk);
   `CHECK(selected==0 && presses==0,"short press bounce is rejected")
  end
  settle(4'hd);`CHECK(selected==1 && presses==1,"S1 directly selects flute")
  repeat(N+10)@(negedge clk);`CHECK(presses==1,"held preset does not repeat")
  settle(4'hf);settle(4'hb);`CHECK(selected==2 && presses==2,"S2 directly selects reed")
  settle(4'hf);settle(4'he);`CHECK(selected==0 && presses==3,"S0 directly selects sine")
  settle(4'hf);settle(4'h7);`CHECK(effects_enabled && selected==0,"S3 enables echo independently")
  repeat(N+20)@(negedge clk);`CHECK(effects_enabled && presses==4,"held S3 toggles exactly once")
  if(N>1)begin
   @(negedge clk);buttons_n=4'hf;repeat(N-1)@(negedge clk);buttons_n=4'h7;
   repeat(N+6)@(negedge clk);
   `CHECK(effects_enabled && presses==4,"release bounce cannot rearm echo")
  end
  settle(4'hf);settle(4'h7);`CHECK(!effects_enabled && presses==5,"stable release rearms next toggle")
  settle(4'hf);settle(4'h5);
  `CHECK(effects_enabled && selected==1 && presses==7,"preset and effect buttons work simultaneously")
  settle(4'hf);settle(4'h8);
  `CHECK(selected==0 && effects_enabled,"simultaneous presets choose lowest index, preserve echo")
  rst=1;#1;`CHECK(selected==0 && !effects_enabled,"reset clears all controls immediately")
  buttons_n=4'hf;#32;rst=0;settle(4'hf);
  `CHECK(selected==0 && !effects_enabled,"no stale press after reset")
  $display("PASS tb_timbre_control checks=%0d debounce_cycles=%0d",checks,N);$finish;
 end
 initial begin #2000000000;$fatal(1,"button test timeout");end
endmodule
