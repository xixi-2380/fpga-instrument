`timescale 1ns/1ps
`include "check.svh"
module tb_ui_controls;
 `include "../src/config/ui_layout.svh"
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [3:0] buttons=15;reg v=0,ready=1;reg [5:0] action=UI_NONE;
 wire [2:0] timbre;wire [1:0] fx;wire en,menu,cv;wire [8:0] e,r,d;
 wire [6:0] ep,rp,dp;wire [3:0] hz,cfg_hz;
 integer checks=0,commands=0;reg [30:0] held;
 timbre_control #(.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(32)) dut(
  .clk(clk),.rst(rst),.buttons_n(buttons),.selected(timbre),.effects_enabled(en),.effect_mode(fx),
  .ui_action_valid(v),.ui_action(action),.cfg_ready(ready),.cfg_valid(cv),.menu_mode(menu),
  .echo_wet(e),.room_wet(r),.tremolo_depth(d),.cfg_tremolo_rate_hz(cfg_hz),
  .echo_percent(ep),.room_percent(rp),.depth_percent(dp),.tremolo_rate_hz(hz));
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task act(input [5:0] a);begin @(negedge clk);v=1;action=a;@(negedge clk);v=0;cycles(4);end endtask
 task short0;begin buttons=14;cycles(10);buttons=15;cycles(10);end endtask
 always @(posedge clk)if(!rst && cv && ready)commands=commands+1;
 initial begin
  #12 rst=0;cycles(5);
  `CHECK(!menu && fx==0 && !en && ep==25 && rp==25 && dp==50 && hz==5,"default UI settings")
  act(UI_FLUTE);buttons=14;cycles(100);buttons=15;cycles(10);
  `CHECK(!menu && timbre==1,"short and long S0 no longer change timbre/page")
  act(UI_MODE);`CHECK(menu && timbre==1,"screen mode replaces S0")
  act(UI_CELLO);`CHECK(timbre==3,"direct cello command preserves third identity bit")
  act(UI_PIANO);`CHECK(timbre==4,"direct piano command")
  act(UI_GUITAR);`CHECK(timbre==5,"direct guitar command")
  act(UI_VIBES);`CHECK(timbre==6,"direct vibraphone command")
  act(UI_NEXT);`CHECK(timbre==0,"next wraps seven presets")
  act(UI_PREV);`CHECK(timbre==6,"previous wraps seven presets")
  repeat(7)act(UI_NEXT);`CHECK(timbre==6,"full cycle preserves preset identity")
  act(UI_SINE);
  act(UI_ECHO);act(UI_FX);repeat(30)begin act(UI_MORE);`CHECK(e==(ep*256+50)/100,"percentage lookup matches rounded arithmetic") end
  `CHECK(ep==100 && e==256 && en,"echo amount clamps at 100 percent")
  repeat(30)begin act(UI_LESS);`CHECK(e==(ep*256+50)/100,"descending percentage lookup matches rounded arithmetic") end
  `CHECK(ep==0 && e==0,"echo clamps at zero")
  act(UI_ROOM);repeat(3)act(UI_MORE);`CHECK(rp==40 && r==102 && ep==0,"room target is independent")
  act(UI_TREMOLO);repeat(15)act(UI_MORE);repeat(15)act(UI_FASTER);
  `CHECK(dp==100 && d==256 && hz==10 && cfg_hz==10,"depth and rate clamp high")
  repeat(15)act(UI_SLOWER);`CHECK(hz==1 && cfg_hz==1,"rate clamps low")
  act(UI_ECHO);act(UI_FASTER);`CHECK(hz==1,"rate controls ignored outside tremolo")
  act(UI_DEFAULTS);`CHECK(ep==25 && rp==25 && dp==50 && hz==5 && fx==0 && !en,"restore effects defaults preserves timbre and menu")
  ready=0;act(UI_MORE);cycles(4);`CHECK(cv,"pending parameter packet offered")
  held={e,r,d,cfg_hz};act(UI_MORE);act(UI_MORE);
  `CHECK({e,r,d,cfg_hz}==held && ep==40,"offered tuple stable while newer targets coalesce")
  ready=1;cycles(8);`CHECK(e==102 && !cv,"latest target submitted after backpressure clears")
  act(UI_TREMOLO);act(UI_FX);buttons=7;cycles(50);buttons=15;cycles(10);
  `CHECK(fx==2 && en && dut.theme_id==3,"long S3 enters hidden theme and preserves UI-selected effect")
  `CHECK(commands>10,"parameter snapshots exercised")
  rst=1;#1;`CHECK(!menu && !en && ep==25 && e==64,"reset restores controller and packet")
  $display("PASS tb_ui_controls checks=%0d commands=%0d",checks,commands);$finish;
 end
endmodule
