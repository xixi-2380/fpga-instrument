`timescale 1ns/1ps
`include "check.svh"
module tb_timbre_control;
 parameter integer N=4,L=100;
 reg clk=0,rst=1;reg [3:0] buttons_n=4'hf;
 wire [1:0] selected,effect_mode;wire effects_enabled;integer checks=0,presses=0;
 always #8.138020833 clk=~clk;
 timbre_control #(.DEBOUNCE_CYCLES(N),.LONG_PRESS_CYCLES(L)) dut(
  clk,rst,buttons_n,selected,effects_enabled,effect_mode);
 always @(posedge clk)if(!rst)presses=presses+$countones(dut.press_event);
 task settle(input [3:0] value);begin
  @(negedge clk);buttons_n=value;repeat(N+6)@(negedge clk);
 end endtask
 initial begin
  #23 rst=0;settle(4'hf);
  `CHECK(selected==0 && !effects_enabled && effect_mode==0 && presses==0,"startup selects dry echo preset without events")
  if(N>1)begin
   @(negedge clk);buttons_n=4'hd;repeat(N-1)@(negedge clk);buttons_n=4'hf;
   repeat(N+6)@(negedge clk);
   `CHECK(selected==0 && presses==0,"short press bounce is rejected")
  end
  settle(4'hd);`CHECK(selected==1 && presses==1,"S1 directly selects flute")
  repeat(N+10)@(negedge clk);`CHECK(presses==1,"held preset does not repeat")
  settle(4'hf);settle(4'hb);`CHECK(selected==2,"S2 directly selects reed")
  settle(4'hf);settle(4'he);`CHECK(selected==0,"S0 directly selects sine")
  settle(4'hf);settle(4'h7);
  `CHECK(!effects_enabled,"short S3 waits for stable release")
  if(N>1)begin
   @(negedge clk);buttons_n=4'hf;repeat(N-1)@(negedge clk);buttons_n=4'h7;
   repeat(N+6)@(negedge clk);
   `CHECK(!effects_enabled && presses==4,"release bounce cannot trigger short action")
  end
  settle(4'hf);`CHECK(effects_enabled && selected==0,"short release enables echo")
  settle(4'h7);settle(4'hf);`CHECK(!effects_enabled && effect_mode==0,"next short press bypasses echo")
  settle(4'h5);`CHECK(selected==1,"preset selection works during an effect press")
  settle(4'hf);`CHECK(effects_enabled && selected==1,"independent short release toggles effect")
  settle(4'h8);`CHECK(selected==0 && effects_enabled,"simultaneous presets choose lowest index")
  settle(4'hf);settle(4'h7);repeat(L+10)@(negedge clk);
  `CHECK(effect_mode==1 && effects_enabled,"long S3 selects room and enables it")
  repeat(L+10)@(negedge clk);`CHECK(effect_mode==1,"long hold selects only once")
  settle(4'hf);`CHECK(effect_mode==1 && effects_enabled,"long release is not a short toggle")
  settle(4'h7);repeat(L+10)@(negedge clk);settle(4'hf);
  `CHECK(effect_mode==2 && effects_enabled,"second long press selects tremolo")
  settle(4'h7);repeat(L+10)@(negedge clk);settle(4'hf);
  `CHECK(effect_mode==0 && effects_enabled,"third long press returns to echo")
  settle(4'h7);settle(4'hf);`CHECK(!effects_enabled && effect_mode==0,"short bypass keeps selected mode")
  rst=1;#1;`CHECK(selected==0 && !effects_enabled && effect_mode==0,"reset clears controls immediately")
  buttons_n=4'hf;#32;rst=0;settle(4'hf);
  `CHECK(!effects_enabled && selected==0,"no stale press after reset")
  $display("PASS tb_timbre_control checks=%0d debounce_cycles=%0d long_cycles=%0d",checks,N,L);$finish;
 end
 initial begin #2000000000;$fatal(1,"button test timeout");end
endmodule
