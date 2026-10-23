`timescale 1ns/1ps
`include "check.svh"
module tb_timbre_control;
 parameter integer N=4,L=100;
 reg clk=0,rst=1;reg [3:0] buttons_n=4'hf;
 wire [2:0] selected;wire [1:0] effect_mode,theme;reg [1:0] remembered;wire effects_enabled;integer checks=0,presses=0;
 always #8.138020833 clk=~clk;
 timbre_control #(.DEBOUNCE_CYCLES(N),.LONG_PRESS_CYCLES(L)) dut(
  .clk(clk),.rst(rst),.buttons_n(buttons_n),.selected(selected),.effects_enabled(effects_enabled),
  .theme_id(theme),.effect_mode(effect_mode),.ui_action_valid(1'b0),.ui_action(6'd63),.cfg_ready(1'b1));
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
  settle(4'hd);`CHECK(selected==0 && theme==2 && presses==1,"S1 selects previous theme without selecting an instrument")
  repeat(N+10)@(negedge clk);`CHECK(presses==1,"held preset does not repeat")
  settle(4'hf);settle(4'hb);`CHECK(selected==0 && theme==0,"S2 selects next theme")
  settle(4'hf);settle(4'he);settle(4'hf);`CHECK(selected==0,"S0 short release selects sine")
  settle(4'hf);settle(4'h7);
  `CHECK(!effects_enabled,"short S3 waits for stable release")
  if(N>1)begin
   @(negedge clk);buttons_n=4'hf;repeat(N-1)@(negedge clk);buttons_n=4'h7;
   repeat(N+6)@(negedge clk);
   `CHECK(!effects_enabled && presses==4,"release bounce cannot trigger short action")
  end
  settle(4'hf);`CHECK(effects_enabled && selected==0,"short release enables echo")
  settle(4'h7);settle(4'hf);`CHECK(!effects_enabled && effect_mode==0,"next short press bypasses echo")
  settle(4'h5);`CHECK(selected==0 && theme==2,"theme selection works during an effect press")
  settle(4'hf);`CHECK(effects_enabled && selected==0,"independent short release toggles effect")
  settle(4'h8);settle(4'hf);`CHECK(selected==0 && effects_enabled,"simultaneous presets resolve to S0 on short release")
  remembered=theme;settle(4'hf);settle(4'h7);repeat(L+10)@(negedge clk);
  `CHECK(effect_mode==0 && effects_enabled && theme==3,"long S3 enters hidden theme and preserves audio")
  repeat(L+10)@(negedge clk);`CHECK(effect_mode==0 && theme==3,"long hold selects hidden theme only once")
  settle(4'hf);`CHECK(effect_mode==0 && effects_enabled && theme==3,"long release is not a short toggle")
  settle(4'h7);repeat(L+10)@(negedge clk);settle(4'hf);
  `CHECK(effect_mode==0 && effects_enabled && theme==remembered,"second long press restores remembered normal theme")
  settle(4'h7);repeat(L+10)@(negedge clk);settle(4'hf);
  `CHECK(effect_mode==0 && effects_enabled && theme==3,"third long press returns to hidden theme")
  settle(4'h7);settle(4'hf);`CHECK(!effects_enabled && effect_mode==0,"short bypass keeps selected mode")
  rst=1;#1;`CHECK(selected==0 && !effects_enabled && effect_mode==0,"reset clears controls immediately")
  buttons_n=4'hf;#32;rst=0;settle(4'hf);
  `CHECK(!effects_enabled && selected==0,"no stale press after reset")
  $display("PASS tb_timbre_control checks=%0d debounce_cycles=%0d long_cycles=%0d",checks,N,L);$finish;
 end
 initial begin #2000000000;$fatal(1,"button test timeout");end
endmodule
