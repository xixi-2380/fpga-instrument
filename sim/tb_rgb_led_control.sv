`timescale 1ns/1ps
module tb_rgb_led_control;
 `include "../src/config/ui_layout.svh"
 `include "../src/config/rgb_led_config.svh"
 reg clk=0,rst=1,menu=1,av=0;always #10 clk=~clk;
 reg [6:0] action=63;wire [15:0] cfg;wire page;
 reg [35:0] keys=0;reg [2:0] online=7;wire [20:0] manual;
 reg [20:0] held=0;wire data,busy;wire [519:0] preview;
 integer checks=0,min_b=255,max_b=0;reg [23:0] first_color;
 rgb_led_settings settings(clk,rst,menu,av,action,cfg,page);
 rgb_key_lights physical(keys,online,manual);
 rgb_led_controller #(.FRAME_CYCLES(60000)) dut(clk,rst,1'b1,1'b1,cfg,held,data,busy,preview);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task act(input [6:0] code);begin @(negedge clk);action=code;av=1;@(negedge clk);av=0;@(negedge clk);end endtask
 task fresh;begin
  @(posedge dut.start);#1;
  while(preview[519:504]!==cfg)begin @(posedge dut.start);#1;end
 end endtask
 initial begin
  #45;rst=0;repeat(3)@(negedge clk);check(cfg==RGB_DEFAULTS,"off blue10 runtime defaults");
  for(integer n=0;n<36;n++)begin
   keys=36'd1<<n;#1;check(manual==(rgb_white_index(7'(60+n))<21?(21'd1<<rgb_white_index(7'(60+n))):21'd0),"physical white/black mapping all36");
   online=7 ^ (3'd1<<(n/12));#1;check(manual==0,"invalid/offline board releases its lamps");online=7;
  end
  keys=0;fresh;check(preview[503:0]==0,"boot complete black frame");
  act(UI_RGB_OPEN);check(page,"RGB settings opens");act(UI_RGB_TOGGLE);fresh;
  for(integer j=0;j<21;j++)check(preview[j*24+:24]==24'h000019,"blue10 exact dim preview");
  repeat(30)act(UI_RGB_UP);check(cfg[8:2]==100,"brightness upper bound");
  act(UI_RGB_COLOR);act(UI_RGB_KEYS);held=1;fresh;
  check(preview[23:0]==24'hff0000 && preview[503:24]==0,"held C4 only");
  act(UI_RGB_REVERSE);fresh;check(preview[503:480]==24'hff0000 && preview[479:0]==0,"reverse physical endpoints");
  held=0;fresh;check(preview[503:0]==0,"release black despite effects");
  act(UI_RGB_RAINBOW);fresh;check(preview[23:0]!=preview[47:24],"rainbow spatial colors");first_color=preview[23:0];
  repeat(12)fresh;check(preview[23:0]!=first_color,"rainbow advances every ten ticks");
  act(UI_RGB_BREATH);
  repeat(205)begin fresh;if(preview[23:16]<min_b)min_b=preview[23:16];if(preview[23:16]>max_b)max_b=preview[23:16];end
  check(min_b==0 && max_b==255,"two-second triangular breath includes both endpoints");
  act(UI_RGB_TOGGLE);fresh;check(preview[503:0]==0,"turn off commits full black frame");
  act(UI_RGB_BACK);check(!page,"back keeps parameters");
  act(UI_RGB_OPEN);menu=0;repeat(3)@(negedge clk);check(!page,"S0 menu exit closes page");
  menu=1;act(UI_DEFAULTS);check(cfg==RGB_DEFAULTS,"shared restore defaults resets LED settings");
  $display("PASS tb_rgb_led_control checks=%0d",checks);$finish;
 end
 initial begin #300000000;$fatal(1,"controller timeout");end
endmodule
