`timescale 1ns/1ps
`include "check.svh"
module tb_theme_controls;
 `include "../src/config/ui_layout.svh"
 parameter integer N=3,L=32;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [3:0] buttons=15;reg valid=0;reg [5:0] action=UI_NONE;
 wire [2:0] timbre;wire [1:0] theme,fx;wire en,menu,zh;wire [1:0] view;
 wire [6:0] ep,rp,dp;wire [3:0] hz;
 integer checks=0;reg [38:0] audio_state;
 timbre_control #(.DEBOUNCE_CYCLES(N),.LONG_PRESS_CYCLES(L)) dut(
  .clk(clk),.rst(rst),.buttons_n(buttons),.selected(timbre),.effects_enabled(en),.effect_mode(fx),
  .ui_action_valid(valid),.ui_action(action),.cfg_ready(1'b1),.menu_mode(menu),
  .echo_percent(ep),.room_percent(rp),.depth_percent(dp),.tremolo_rate_hz(hz),.theme_id(theme),.language_zh(zh),.view_mode(view));
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task act(input [5:0] a);begin @(negedge clk);valid=1;action=a;cycles(1);valid=0;cycles(4);end endtask
 task short_key(input integer k);begin buttons=15^(1<<k);cycles(N+7);buttons=15;cycles(N+7);end endtask
 task hold3;begin buttons=7;cycles(L+N+10);end endtask
 task release3;begin buttons=15;cycles(N+7);end endtask
 task unchanged;begin `CHECK({timbre,fx,en,menu,ep,rp,dp,hz}==audio_state,"themes preserve instrument, effects, page and all parameters") end endtask
 initial begin
  #12 rst=0;cycles(5);`CHECK(theme==0,"British default")
  // Selecting any effect must preserve bypass, including returning to ECHO.
  act(UI_ROOM);`CHECK(!en && fx==1,"ROOM selection preserves disabled state")
  act(UI_TREMOLO);`CHECK(!en && fx==2,"TREMOLO selection preserves disabled state")
  act(UI_ECHO);`CHECK(!en && fx==0,"return to ECHO cannot re-enable FX")
  act(UI_FX);`CHECK(en,"explicit FX action enables processing")
  act(UI_ROOM);act(UI_TREMOLO);act(UI_ECHO);`CHECK(en,"effect selections also preserve enabled state")
  act(UI_FX);act(UI_ROOM);act(UI_ECHO);`CHECK(!en,"off remains off after repeated effect selections")
  act(UI_CELLO);act(UI_ROOM);act(UI_FX);act(UI_MORE);act(UI_MODE);
  audio_state={timbre,fx,en,menu,ep,rp,dp,hz};
  for(integer reserved=0;reserved<3;reserved=reserved+1)begin
   short_key(reserved);buttons=15^(1<<reserved);cycles(L*3);buttons=15;cycles(N+7);
   `CHECK(theme==0 && !zh,"S0/S1/S2 short and long do nothing") unchanged;
  end
  act(UI_THEME);`CHECK(theme==1,"screen cycles cat") unchanged;
  act(UI_THEME);`CHECK(theme==2,"screen cycles capybara") unchanged;
  act(UI_THEME);`CHECK(theme==0,"touch command follows normal cycle") unchanged;
  act(UI_THEME);`CHECK(theme==1,"touch command enters cat")
  hold3;`CHECK(theme==3,"long S3 enters hidden theme") unchanged;
  cycles(L*3);`CHECK(theme==3,"holding long S3 fires only once")
  release3;`CHECK(theme==3,"long release does not toggle FX") unchanged;
  hold3;release3;`CHECK(theme==1,"long S3 restores preceding cat theme") unchanged;
  hold3;release3;act(UI_THEME);`CHECK(theme==2,"normal switch leaves hidden theme using remembered cycle") unchanged;
  hold3;release3;act(UI_THEME);`CHECK(theme==0,"screen switch can leave hidden theme") unchanged;
  short_key(3);`CHECK(en && fx==1,"short S3 cannot change FX")
  short_key(3);unchanged;
  // Reject a sub-debounce pulse, then check held S2 never auto-repeats.
  if(N>1)begin buttons=11;cycles(N-1);buttons=15;cycles(N+8);`CHECK(theme==0,"S2 bounce rejected") end
  buttons=11;cycles(L*3);`CHECK(theme==0,"held S2 is inactive")
  buttons=15;cycles(N+7);
  for(integer style=0;style<4;style=style+1)begin
   if(style==3)begin hold3;release3;end
   `CHECK(theme==(style==3 ? 3 : style),"language tested in three normal themes plus Easter")
   act(UI_LANGUAGE);`CHECK(zh,"screen switches Chinese in every theme/page") unchanged;
   act(UI_DEFAULTS);`CHECK(zh,"effect restore preserves selected language")
   // Restore the audio tuple used by the isolation assertions.
   act(UI_ROOM);act(UI_FX);act(UI_MORE);
   audio_state={timbre,fx,en,menu,ep,rp,dp,hz};
   act(UI_LANGUAGE);`CHECK(!zh,"second language touch returns English") unchanged;
   act(UI_THEME);
  end
  for(integer m=0;m<6;m=m+1)begin
   `CHECK(view==m%3,"wave FFT XY three-state view cycle") act(UI_VIEW);unchanged;
  end
  `CHECK(view==0,"view returns to waveform")
  // Inactive physical input cannot suppress a simultaneous language command.
  buttons=8;act(UI_LANGUAGE);`CHECK(zh,"S0..S2 held never block touch")
  buttons=15;cycles(N+7);
  // Reset while held cannot leave a hidden theme or stale action.
  rst=1;cycles(2);`CHECK(theme==0 && !en,"reset restores British/default effects")
  buttons=15;rst=0;cycles(N+8);`CHECK(theme==0,"reset leaves no stale press")
  $display("PASS tb_theme_controls checks=%0d",checks);$finish;
 end
endmodule
