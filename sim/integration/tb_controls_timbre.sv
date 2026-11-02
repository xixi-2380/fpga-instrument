`timescale 1ns/1ps
module tb_controls_timbre;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [3:0] buttons=15;reg uv=0,cr=1,av=0;reg [6:0] action=63,at=0;reg [7:0] ver=0;
 reg [2:0] up=0,dn=0,single=0,dbl=0;
 wire [4:0] selected,rate,cfg_rate;wire enabled,menu,cv,ultra_page,ultra_enabled,edit_strength,edit_rate,zh;
 wire [8:0] ew,rw,td;wire [6:0] ep,rp,dp,volume,umin,umax;wire [2:0] sens,mask,cfg_mask;
 wire [7:0] uver;wire [1:0] mode,theme,view;wire [10:0] ms;wire [15:0] bcd;wire [16:0] samples;
 `include "config/ui_layout.svh"
 timbre_control dut(.clk(clk),.rst(rst),.buttons_n(buttons),.selected(selected),.effects_enabled(enabled),.effect_mode(mode),
  .ui_action_valid(uv),.ui_action(action),.cfg_ready(cr),.menu_mode(menu),.cfg_valid(cv),.echo_wet(ew),.room_wet(rw),.tremolo_depth(td),.cfg_tremolo_rate_hz(cfg_rate),
  .echo_percent(ep),.room_percent(rp),.depth_percent(dp),.tremolo_rate_hz(rate),.volume_percent(volume),.ultrasonic_page(ultra_page),.ultrasonic_enabled(ultra_enabled),
  .ultrasonic_sensitivity(sens),.ultrasonic_min(umin),.ultrasonic_max(umax),.ultrasonic_version(uver),.auto_valid(av),.auto_version(ver),.auto_target(at),
  .encoder_up(up),.encoder_down(dn),.encoder_single(single),.encoder_double(dbl),.effect_mask(mask),.cfg_effect_mask(cfg_mask),
  .echo_edit_strength(edit_strength),.tremolo_edit_rate(edit_rate),.echo_time_ms(ms),.echo_time_bcd(bcd),.cfg_echo_samples(samples),.theme_id(theme),.view_mode(view),.language_zh(zh));
 integer checks=0,seed=32'h2380a001,expected_volume=100;
 reg stalled=0;reg [51:0] submitted;wire [51:0] payload={ew,rw,td,cfg_rate,cfg_mask,samples};
 always @(posedge clk)begin
  if(rst)stalled=0;
  else begin
   checks++;
   if(stalled && (!cv || payload!==submitted))$fatal(1,"CFG changed while backpressured");
   submitted=payload;stalled=cv&&!cr;
  end
 end
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask
 task tap(input [6:0] a);begin action=a;uv=1;clocks(1);uv=0;clocks(1);end endtask
 task enc(input integer n,input integer k);begin
  case(k)0:up=3'b1<<n;1:dn=3'b1<<n;2:single=3'b1<<n;3:dbl=3'b1<<n;endcase
  clocks(1);up=0;dn=0;single=0;dbl=0;clocks(1);
 end endtask
 task check_config;begin
  cr=1;clocks(8);
  if(ew!=(ep*256+50)/100 || rw!=(rp*256+50)/100 || td!=(dp*256+50)/100 || cfg_rate!=rate || cfg_mask!=mask || samples!=ms*48)
   $fatal(1,"CFG did not converge to complete independent settings snapshot");checks++;
  if(bcd!=(ms/1000)*4096+((ms/100)%10)*256+((ms/10)%10)*16+ms%10)$fatal(1,"Sustain time BCD mismatch");
 end endtask
 reg [95:0] settings;wire [95:0] state={selected,mask,mode,menu,ep,rp,dp,rate,volume,ultra_page,ultra_enabled,sens,umin,umax,uver,ms,theme,view,zh};
 initial begin
  clocks(3);rst=0;clocks(10);check_config;settings=state;
  for(integer n=0;n<128;n++)begin buttons=$random(seed);av=1;at=$unsigned($random(seed))%101;ver=$random(seed);clocks(3);
   if(state!==settings)$fatal(1,"Retired S0..S3 or automatic target changed settings");end
  av=0;buttons=15;
  for(integer n=0;n<1000;n++)begin
   up=0;dn=0;single=0;dbl=0;
   case($unsigned($random(seed))%4)
    0:begin up=2;if(expected_volume<100)expected_volume++;end
    1:begin dn=2;if(expected_volume>0)expected_volume--;end
    2:single=2;3:dbl=2;
   endcase
   av=1;ver=$random(seed);at=$random(seed);clocks(1);
   if(volume!=expected_volume || rp!=25 || mask!=0 || mode!=0)$fatal(1,"Encoder2/retired auto volume changed reverb or volume mismatch");
  end
  up=0;dn=0;single=0;dbl=0;av=0;
  tap(UI_VOLUME_DOWN);expected_volume=expected_volume>=5?expected_volume-5:0;if(volume!=expected_volume)$fatal(1,"Screen volume down failed");
  tap(UI_VOLUME_UP);expected_volume=expected_volume<=95?expected_volume+5:100;if(volume!=expected_volume)$fatal(1,"Screen volume up failed");
  enc(0,0);if(ms!=160 || volume!=expected_volume)$fatal(1,"Encoder1 time failed");
  enc(0,2);enc(0,0);if(ep!=26 || !edit_strength)$fatal(1,"Encoder1 strength failed");
  enc(0,3);if(mask!=1)$fatal(1,"Encoder1 switch failed");
  enc(2,2);enc(2,0);enc(2,3);if(rate!=6 || mask!=5 || !edit_rate)$fatal(1,"Encoder3 rate/switch failed");
  tap(UI_ROOM);tap(UI_MORE);if(rp!=30 || mask!=5)$fatal(1,"Screen reverb incorrectly changed independent masks");
  // Freeze old submitted configuration while several desired settings change.
  cr=0;tap(UI_MORE);clocks(2);tap(UI_FX);tap(UI_MORE);enc(0,1);clocks(20);check_config;
  tap(UI_THEME);if(theme!=1)$fatal(1,"Theme1 failed");tap(UI_THEME);if(theme!=2)$fatal(1,"Theme2 failed");
  tap(UI_EGG);if(theme!=3)$fatal(1,"Touch egg entry failed");tap(UI_EGG);if(theme!=2)$fatal(1,"Touch egg return failed");
  tap(UI_THEME);if(theme!=0)$fatal(1,"Theme cycle failed");tap(UI_LANGUAGE);if(!zh)$fatal(1,"Language failed");
  tap(UI_VIEW);if(view!=1)$fatal(1,"View1 failed");tap(UI_VIEW);tap(UI_VIEW);if(view!=0)$fatal(1,"View cycle failed");
  tap(UI_MODE);if(!menu)$fatal(1,"Menu failed");tap(UI_ULTRA_OPEN);tap(UI_ULTRA_TOGGLE);
  if(!ultra_page || !ultra_enabled || umin!=5 || umax!=40 || sens!=1)$fatal(1,"Sensor cm/deadband settings defaults failed");
  // The same controls now directly select a 1..5cm neutral half-width.
  // This change never owns master volume, endpoint range or effect settings.
  repeat(8)tap(UI_SENS_UP);if(sens!=5 || umin!=5 || umax!=40 || volume!=expected_volume)$fatal(1,"Neutral band upper cm bound or unrelated settings failed");
  repeat(8)tap(UI_SENS_DOWN);if(sens!=1 || umin!=5 || umax!=40 || volume!=expected_volume)$fatal(1,"Neutral band lower cm bound or unrelated settings failed");
  // Boundaries and published snapshots under random downstream stalls.
  for(integer n=0;n<500;n++)begin cr=$unsigned($random(seed))%3!=0;enc(1,n%2);end
  cr=1;
  repeat(150)enc(1,1);if(volume!=0)$fatal(1,"Volume lower bound failed");
  repeat(150)enc(1,0);if(volume!=100)$fatal(1,"Volume upper bound failed");
  repeat(25)tap(UI_VOLUME_DOWN);if(volume!=0)$fatal(1,"Screen volume lower bound failed");
  repeat(25)tap(UI_VOLUME_UP);if(volume!=100)$fatal(1,"Screen volume upper bound failed");
  // Sweep the complete percentage conversion table against rational rounding.
  repeat(150)enc(0,1);if(ep!=0)$fatal(1,"Strength lower bound failed");check_config;
  for(integer n=0;n<100;n++)begin enc(0,0);check_config;end
  enc(0,0);if(ep!=100)$fatal(1,"Strength upper bound failed");
  enc(0,2);repeat(250)enc(0,1);if(ms!=20)$fatal(1,"Tail time lower bound failed");
  for(integer n=0;n<198;n++)begin enc(0,0);check_config;end
  enc(0,0);if(ms!=2000)$fatal(1,"Tail time upper bound failed");
  repeat(30)enc(2,1);if(rate!=1)$fatal(1,"Tremolo rate lower bound failed");
  repeat(30)enc(2,0);if(rate!=20)$fatal(1,"Tremolo rate upper bound failed");
  enc(2,2);repeat(150)enc(2,1);if(dp!=0)$fatal(1,"Tremolo depth lower bound failed");
  repeat(150)enc(2,0);if(dp!=100)$fatal(1,"Tremolo depth upper bound failed");
  tap(UI_DEFAULTS);check_config;
  if(volume!=100 || mask!=0 || ms!=150 || ultra_enabled || sens!=1 || theme!=0 || !zh)$fatal(1,"Defaults changed retained UI state or control defaults");
  $display("PASS tb_controls_timbre checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"Timbre control timeout");end
endmodule
