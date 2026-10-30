`timescale 1ns/1ps
`include "check.svh"
module tb_ui_controls;
 `include "../src/config/ui_layout.svh"
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [3:0] buttons=15;reg v=0,ready=1;reg [6:0] action=UI_NONE;
 wire [4:0] timbre;wire [1:0] fx;wire en,menu,cv;wire [8:0] e,r,d;
 wire [6:0] ep,rp,dp;wire [4:0] hz,cfg_hz;
 reg av=0;reg [7:0] aver=0;reg [6:0] atarget=0;
 wire upage,uen;wire [2:0] sens;wire [6:0] umin,umax;wire [7:0] uver;
 integer checks=0,commands=0;reg [30:0] held;
 timbre_control #(.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(32),.ULTRA_SLEW_CYCLES(3)) dut(
  .clk(clk),.rst(rst),.buttons_n(buttons),.selected(timbre),.effects_enabled(en),.effect_mode(fx),
  .ui_action_valid(v),.ui_action(action),.cfg_ready(ready),.cfg_valid(cv),.menu_mode(menu),
  .echo_wet(e),.room_wet(r),.tremolo_depth(d),.cfg_tremolo_rate_hz(cfg_hz),
  .echo_percent(ep),.room_percent(rp),.depth_percent(dp),.tremolo_rate_hz(hz),
  .ultrasonic_page(upage),.ultrasonic_enabled(uen),.ultrasonic_sensitivity(sens),
  .ultrasonic_min(umin),.ultrasonic_max(umax),.ultrasonic_version(uver),
  .auto_valid(av),.auto_version(aver),.auto_target(atarget));
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task act(input [6:0] a);begin @(negedge clk);v=1;action=a;@(negedge clk);v=0;cycles(4);end endtask
 task short0;begin buttons=14;cycles(10);buttons=15;cycles(10);end endtask
 always @(posedge clk)if(!rst && cv && ready)commands=commands+1;
 initial begin
  #12 rst=0;cycles(5);
  `CHECK(!menu && fx==0 && !en && ep==25 && rp==25 && dp==50 && hz==5,"default UI settings")
  act(UI_FLUTE);buttons=14;cycles(50);
  `CHECK(menu && timbre==1,"long S0 enters menu without changing timbre")
  cycles(50);`CHECK(menu,"held S0 toggles once")
  buttons=15;cycles(10);`CHECK(menu && timbre==1,"long release has no sine action")
  short0;`CHECK(timbre==0 && menu,"short S0 selects sine on release")
  act(UI_CELLO);`CHECK(timbre==3,"direct cello command preserves third identity bit")
  act(UI_PIANO);`CHECK(timbre==4,"direct piano command")
  act(UI_GUITAR);`CHECK(timbre==5,"direct guitar command")
  act(UI_VIBES);`CHECK(timbre==6,"direct vibraphone command")
  act(UI_NEXT);`CHECK(timbre==7,"next reaches added organ")
  act(UI_SINE);act(UI_PREV);`CHECK(timbre==15,"previous wraps sixteen presets")
  repeat(16)act(UI_NEXT);`CHECK(timbre==15,"full cycle preserves preset identity")
  act(UI_SINE);act(7'd80);`CHECK(timbre==8,"page switch reaches second bank")
  for(integer i=0;i<8;i++)begin act(7'(64+i));`CHECK(timbre==8+i,"all second-page instruments selectable") end
  act(7'd80);`CHECK(timbre==7,"page switch preserves card index")
  act(UI_SINE);
  act(UI_ECHO);repeat(30)begin act(UI_MORE);`CHECK(e==(ep*256+50)/100,"percentage lookup matches rounded arithmetic") end
  `CHECK(ep==100 && e==256 && en,"echo amount clamps at 100 percent")
  repeat(30)begin act(UI_LESS);`CHECK(e==(ep*256+50)/100,"descending percentage lookup matches rounded arithmetic") end
  `CHECK(ep==0 && e==0,"echo clamps at zero")
  act(UI_ROOM);repeat(3)act(UI_MORE);`CHECK(rp==40 && r==102 && ep==0,"room target is independent")
  act(UI_TREMOLO);repeat(15)act(UI_MORE);repeat(15)act(UI_FASTER);
  `CHECK(dp==100 && d==256 && hz==20 && cfg_hz==20,"depth and rate clamp high")
  repeat(25)act(UI_SLOWER);`CHECK(hz==1 && cfg_hz==1,"rate clamps low")
  act(UI_ECHO);act(UI_FASTER);`CHECK(hz==1,"rate controls ignored outside tremolo")
  act(UI_DEFAULTS);`CHECK(ep==25 && rp==25 && dp==50 && hz==5 && fx==0 && !en,"restore effects defaults preserves timbre and menu")
  ready=0;act(UI_MORE);cycles(4);`CHECK(cv,"pending parameter packet offered")
  held={e,r,d,cfg_hz};act(UI_MORE);act(UI_MORE);
  `CHECK({e,r,d,cfg_hz}==held && ep==40,"offered tuple stable while newer targets coalesce")
  ready=1;cycles(8);`CHECK(e==102 && !cv,"latest target submitted after backpressure clears")
  act(UI_TREMOLO);buttons=7;cycles(50);buttons=15;cycles(10);
  `CHECK(fx==0 && en,"S3 cycles from UI-selected tremolo instead of stale button state")
  `CHECK(commands>10,"parameter snapshots exercised")
  rst=1;#1;`CHECK(!menu && !en && ep==25 && e==64,"reset restores controller and packet")
  rst=0;cycles(4);act(UI_DEFAULTS);
  `CHECK(dut.volume_percent==100,"volume defaults to unity")
  repeat(25)act(UI_VOLUME_DOWN);
  `CHECK(dut.volume_percent==0,"volume clamps at zero")
  repeat(25)act(UI_VOLUME_UP);
  `CHECK(dut.volume_percent==100,"volume clamps at full gain")
  `CHECK(ui_hit(24,420,0,1)==UI_VOLUME_DOWN && ui_hit(192,420,0,1)==UI_VOLUME_UP,"settings volume buttons share hit layout")
  act(UI_MODE);buttons=13;cycles(10);buttons=15;cycles(10);
  `CHECK(dut.volume_percent==95 && timbre==0,"S1 in settings lowers volume without selecting flute")
  buttons=11;cycles(10);buttons=15;cycles(10);
  `CHECK(dut.volume_percent==100 && timbre==0,"S2 in settings raises volume without selecting reed")
  act(UI_ULTRA_OPEN);`CHECK(upage && menu && !uen && sens==1 && umin==0 && umax==100,"sensor settings entry and defaults")
  repeat(9)act(UI_SENS_UP);`CHECK(sens==5,"sensitivity clamps at five")
  repeat(9)act(UI_SENS_DOWN);`CHECK(sens==1,"sensitivity clamps at one")
  repeat(4)act(UI_MAX_DOWN);repeat(4)act(UI_MIN_UP);
  `CHECK(umin==20 && umax==80,"independent min/max settings")
  repeat(20)act(UI_MIN_UP);`CHECK(umin==umax && umax==80,"minimum never exceeds maximum")
  act(UI_MAX_DOWN);`CHECK(umin==80 && umax==80,"maximum never drops below minimum")
  repeat(12)act(UI_MIN_DOWN);
  act(UI_ULTRA_TOGGLE);`CHECK(uen && dut.volume_percent==100,"enabling holds current volume until matching result")
  av=1;aver=uver-1;atarget=43;cycles(12);
  `CHECK(dut.volume_percent==100,"old session target cannot change volume")
  aver=uver;cycles(9);`CHECK(dut.volume_percent==97,"auto slew is one percent per three test cycles")
  act(UI_VOLUME_DOWN);`CHECK(dut.volume_percent>90,"manual command cannot decrement five while auto owns volume")
  cycles(200);`CHECK(dut.volume_percent==43,"automatic target reached smoothly at a non-five-percent value")
  buttons=13;cycles(10);buttons=15;cycles(10);
  `CHECK(dut.volume_percent==43,"S1 cannot override automatic ownership")
  buttons=11;cycles(10);buttons=15;cycles(10);
  `CHECK(dut.volume_percent==43,"S2 cannot override automatic ownership")
  act(UI_ULTRA_TOGGLE);`CHECK(!uen && dut.volume_percent==43,"disabling retains exact current volume")
  act(UI_VOLUME_DOWN);`CHECK(dut.volume_percent==38,"manual takes over from retained auto level")
  act(UI_ULTRA_BACK);`CHECK(menu && !upage,"subpage back returns to original settings")
  act(UI_DEFAULTS);`CHECK(!uen && sens==1 && umin==0 && umax==100 && dut.volume_percent==100,"reset restores all control defaults")
  $display("PASS tb_ui_controls checks=%0d commands=%0d",checks,commands);$finish;
 end
endmodule
