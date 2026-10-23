`timescale 1ns/1ps
`include "check.svh"
module tb_theme_controls;
 `include "../src/config/ui_layout.svh"
 parameter integer N=3,L=32;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [3:0] buttons=15;reg valid=0;reg [5:0] action=UI_NONE;
 wire [2:0] timbre;wire [1:0] theme,fx;wire en,menu;
 wire [6:0] ep,rp,dp;wire [3:0] hz;
 integer checks=0;reg [38:0] audio_state;
 timbre_control #(.DEBOUNCE_CYCLES(N),.LONG_PRESS_CYCLES(L)) dut(
  .clk(clk),.rst(rst),.buttons_n(buttons),.selected(timbre),.effects_enabled(en),.effect_mode(fx),
  .ui_action_valid(valid),.ui_action(action),.cfg_ready(1'b1),.menu_mode(menu),
  .echo_percent(ep),.room_percent(rp),.depth_percent(dp),.tremolo_rate_hz(hz),.theme_id(theme));
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task act(input [5:0] a);begin @(negedge clk);valid=1;action=a;cycles(1);valid=0;cycles(4);end endtask
 task short_key(input integer k);begin buttons=15^(1<<k);cycles(N+7);buttons=15;cycles(N+7);end endtask
 task hold3;begin buttons=7;cycles(L+N+10);end endtask
 task release3;begin buttons=15;cycles(N+7);end endtask
 task unchanged;begin `CHECK({timbre,fx,en,menu,ep,rp,dp,hz}==audio_state,"themes preserve instrument, effects, page and all parameters") end endtask
 initial begin
  #12 rst=0;cycles(5);`CHECK(theme==0,"British default")
  act(UI_CELLO);act(UI_ROOM);act(UI_MORE);act(UI_MODE);
  audio_state={timbre,fx,en,menu,ep,rp,dp,hz};
  short_key(2);`CHECK(theme==1,"S2 next to cat") unchanged;
  short_key(2);`CHECK(theme==2,"S2 next to capybara") unchanged;
  short_key(2);`CHECK(theme==0,"normal cycle excludes hidden theme") unchanged;
  short_key(1);`CHECK(theme==2,"S1 previous wraps to capybara") unchanged;
  act(UI_THEME);`CHECK(theme==0,"touch command follows normal cycle") unchanged;
  act(UI_THEME);`CHECK(theme==1,"touch command enters cat")
  hold3;`CHECK(theme==3,"long S3 enters hidden theme") unchanged;
  cycles(L*3);`CHECK(theme==3,"holding long S3 fires only once")
  release3;`CHECK(theme==3,"long release does not toggle FX") unchanged;
  hold3;release3;`CHECK(theme==1,"long S3 restores preceding cat theme") unchanged;
  hold3;release3;short_key(2);`CHECK(theme==2,"normal switch leaves hidden theme using remembered cycle") unchanged;
  hold3;release3;act(UI_THEME);`CHECK(theme==0,"screen switch can leave hidden theme") unchanged;
  short_key(3);`CHECK(!en && fx==1,"short S3 still switches effect bypass without changing type")
  short_key(3);unchanged;
  // Reject a sub-debounce pulse, then check held S2 never auto-repeats.
  if(N>1)begin buttons=11;cycles(N-1);buttons=15;cycles(N+8);`CHECK(theme==0,"S2 bounce rejected") end
  buttons=11;cycles(L*3);`CHECK(theme==1,"held S2 advances exactly once")
  buttons=15;cycles(N+7);
  // Reset while held cannot leave a hidden theme or stale action.
  rst=1;cycles(2);`CHECK(theme==0 && !en,"reset restores British/default effects")
  buttons=15;rst=0;cycles(N+8);`CHECK(theme==0,"reset leaves no stale press")
  $display("PASS tb_theme_controls checks=%0d",checks);$finish;
 end
endmodule
