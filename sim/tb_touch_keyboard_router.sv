`timescale 1ns/1ps
`include "check.svh"
module tb_touch_keyboard_router;
 reg clk=0,rst=1,blocked=0,menu=0,more=0,ultra=0,valid=0;always #5 clk=~clk;
 reg [35:0] piano=0;reg [11:0] aux=0;reg [2:0] online=0;
 wire [35:0] notes;wire av;wire [5:0] action;
 integer checks=0,events=0;reg [5:0] last_action;
 `include "../src/config/ui_layout.svh"
 touch_keyboard_router dut(clk,rst,blocked,menu,more,ultra,valid,piano,aux,online,notes,av,action);
 always @(posedge clk)begin #1;if(av)begin events++;last_action=action;end end
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task tap(input integer n,input [5:0] expected);integer before_count;begin
  before_count=events;aux=12'b1<<n;cycles(5);
  `CHECK(events==before_count+1 && last_action==expected,"AUX maps to one control and repeats only after release")
  cycles(12);`CHECK(events==before_count+1,"holding AUX cannot auto-repeat destructive actions")
  aux=0;cycles(3);
 end endtask
 initial begin
  #12;rst=0;piano=36'h800001001;valid=1;online=7;cycles(5);
  `CHECK(notes==0,"held startup keys cannot make sound")
  piano=0;cycles(3);piano=36'h800001001;cycles(2);
  `CHECK(notes==piano,"each octave including B6 is independently playable")
  online=5;cycles(3);`CHECK(notes==36'h800000001,"one disconnected board releases only its twelve keys")
  online=7;cycles(4);`CHECK(notes==36'h800000001,"reconnect cannot reattack a held key")
  piano[12]=0;cycles(2);piano[12]=1;cycles(2);`CHECK(notes==piano,"release rearms only that key")
  blocked=1;cycles(3);`CHECK(notes==0,"menu or Bluetooth entry drains every manual Note Off")
  blocked=0;cycles(4);`CHECK(notes==0,"return cannot replay held manual keys")
  piano[35]=0;cycles(3);piano[35]=1;cycles(2);`CHECK(notes==36'h800000000,"released key can resume while unrelated keys remain held")
  aux=12'b1<<9;cycles(5);`CHECK(events==0,"ultrasound shortcut is inactive outside settings")
  aux=0;cycles(3);aux=12'b1<<10;cycles(5);`CHECK(events==0,"library shortcut is inactive outside settings")
  aux=0;cycles(3);
  tap(0,UI_PREV);tap(1,UI_NEXT);tap(8,UI_MODE);
  menu=1;tap(9,UI_ULTRA_OPEN);tap(10,UI_OPEN_MORE);
  more=1;tap(8,UI_SONG_DELETE);tap(11,UI_MORE_BACK);more=0;
  ultra=1;tap(6,UI_MAX_DOWN);tap(11,UI_ULTRA_BACK);
  valid=0;cycles(3);valid=1;cycles(3);`CHECK(notes==0,"invalid snapshots do not admit held keys")
  $display("PASS tb_touch_keyboard_router checks=%0d actions=%0d",checks,events);$finish;
 end
endmodule
