`timescale 1ns/1ps
`include "check.svh"
module tb_ui_inputs;
 `include "../src/config/ui_layout.svh"
 reg clk=0,rst=1,menu=0,ghost=0;always #5 clk=~clk;
 reg [15:0] keys=0;wire inhibit,kv;wire [5:0] ka;
 reg enabled=1,valid=1,ready=1,error=0,down=0;reg [3:0] count=0;
 reg [15:0] x=0,y=0,rx=800,ry=480;reg [1:0] fx=0;
 wire tv;wire [5:0] ta;integer checks=0,kevents=0,tevents=0;
 ui_keypad_router #(.RELEASE_CYCLES(2)) k(clk,rst,menu,ghost,keys,inhibit,kv,ka);
 ui_touch_actions t(clk,rst,enabled,valid,ready,error,down,count,x,y,rx,ry,fx,menu,tv,ta);
 always @(posedge clk)begin if(kv)kevents=kevents+1;if(tv)tevents=tevents+1;end
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task contact(input integer px,py,input [5:0] expected);integer before_events;begin
  down=0;count=0;cycles(3);before_events=tevents;x=px;y=py;down=1;count=1;cycles(5);
  `CHECK(tevents==before_events+(expected!=UI_NONE),"touch hit count and bounds")
  if(expected!=UI_NONE)`CHECK(ta==expected,"touch maps to shared action ID")
  x=700;y=440;cycles(8);`CHECK(tevents==before_events+(expected!=UI_NONE),"drag and hold never repeat")
 end endtask
 initial begin
  #12 rst=0;cycles(4);`CHECK(!inhibit,"released keyboard arms play")
  keys=1;cycles(4);menu=1;cycles(5);`CHECK(inhibit && kevents==0,"menu entry suppresses held note as command")
  keys=0;cycles(4);keys=16'h0200;cycles(4);
  `CHECK(kevents==1 && ka==UI_MORE,"matrix R3C2 adjusts amount")
  cycles(10);`CHECK(kevents==1,"held menu key fires once")
  keys=0;cycles(3);keys=16'h0003;cycles(4);`CHECK(kevents==1,"multi-key menu input is ignored")
  ghost=1;keys=0;cycles(3);ghost=0;cycles(1);keys=16'h0200;cycles(4);
  `CHECK(kevents==1,"ghost recovery cannot treat transient zero keys as full release")
  keys=0;cycles(3);keys=16'h8000;cycles(4);`CHECK(ka==UI_MODE && kevents==2,"R4C4 exits menu")
  menu=0;cycles(3);`CHECK(inhibit,"exit key cannot become a played note")
  keys=0;cycles(3);`CHECK(!inhibit,"all keys released rearms notes")
  menu=1;cycles(4);keys=16'h2000;cycles(4);`CHECK(ka==UI_PREV,"R4C2 now selects previous timbre")
  keys=0;cycles(4);keys=16'h4000;cycles(4);`CHECK(ka==UI_NEXT,"R4C3 now selects next timbre")
  keys=0;cycles(4);menu=0;
  contact(536,420,UI_THEME);contact(647,463,UI_THEME);contact(648,463,UI_NONE);
  contact(32,140,UI_NONE); // performance page must not select timbre
  contact(664,40,UI_MODE);menu=1;
  contact(28,132,UI_SINE);contact(152,132,UI_FLUTE);contact(28,196,UI_REED);
  contact(152,196,UI_CELLO);contact(28,260,UI_PIANO);contact(152,260,UI_GUITAR);contact(28,324,UI_VIBES);
  contact(139,183,UI_SINE);contact(140,183,UI_NONE);
  contact(308,124,UI_ECHO);contact(464,124,UI_ROOM);contact(620,124,UI_TREMOLO);
  contact(152,324,UI_FX);contact(308,240,UI_LESS);contact(767,287,UI_MORE);contact(768,287,UI_NONE);
  contact(308,344,UI_NONE);fx=2;contact(308,344,UI_SLOWER);contact(716,344,UI_FASTER);
  contact(536,420,UI_THEME);contact(664,420,UI_DEFAULTS);contact(800,0,UI_NONE);
  down=0;count=0;cycles(3);error=1;down=1;count=1;cycles(3);error=0;cycles(3);
  `CHECK(!tv,"error recovery cannot fire an already held touch")
  rx=1024;contact(30,140,UI_NONE);rx=800;
  enabled=0;contact(30,140,UI_NONE);enabled=1;cycles(3);`CHECK(!tv,"enabling while held requires release")
  $display("PASS tb_ui_inputs checks=%0d keypad_events=%0d touch_events=%0d",checks,kevents,tevents);$finish;
 end
endmodule
