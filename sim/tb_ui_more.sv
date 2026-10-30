`timescale 1ns/1ps
module tb_ui_more;
 `include "../src/config/ui_layout.svh"
 reg clk=0,rst=1,menu=1,down=0,ready=1;always #5 clk=~clk;
 reg [3:0] count=0;reg [15:0] x=0,y=0,keys=0;
 wire touch_valid,key_valid,open,confirm,cv,inhibit,info;wire [5:0] ta,ka;wire [3:0] cmd;
 integer checks=0,commands=0;reg [3:0] last;
 ui_touch_actions touch(clk,rst,1'b1,1'b1,1'b1,1'b0,down,count,x,y,16'd800,16'd480,2'd0,menu,touch_valid,ta,open,1'b0,1'b0,1'b0);
 ui_keypad_router #(.RELEASE_CYCLES(2)) keypad(clk,rst,menu,1'b0,keys,inhibit,key_valid,ka,open,1'b0);
 ui_more_actions more(clk,rst,menu,touch_valid || key_valid,key_valid?ka:ta,open,confirm,cv,ready,cmd,info);
 always @(posedge clk)if(!rst && cv && ready)begin commands++;last=cmd;end
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task tap(input integer px,py);begin down=0;count=0;cycles(3);x=px;y=py;down=1;count=1;cycles(5);down=0;count=0;cycles(3);end endtask
 task key(input integer n);begin keys=0;cycles(4);keys=16'd1<<n;cycles(4);keys=0;cycles(4);end endtask
 initial begin
  #12 rst=0;cycles(5);tap(740,260);check(!open && commands==0,"old effect-increase UI_MORE cannot open new page");
  tap(600,442);check(open && inhibit,"single settings entry opens more without enabling manual notes");
  tap(30,210);check(last==0,"previous selection");tap(210,210);check(last==1,"next selection");
  tap(390,210);check(last==6,"load is separate from play");tap(570,210);check(last==2,"play action");
  tap(30,265);check(last==3,"pause action");tap(210,265);check(last==4,"resume action");tap(390,265);check(last==5,"stop action");
  tap(30,316);check(last==7,"save action independent of playback");
  tap(210,316);check(confirm && last==7,"first delete is confirmation only");tap(390,316);check(!confirm && info,"INFO shows cached metadata and cancels confirmation");
  tap(210,316);tap(210,316);check(last==8 && !confirm,"second released delete confirms exactly once");
  ready=0;tap(570,210);check(cv && cmd==2,"control command retained under CDC backpressure");tap(210,210);check(cv && cmd==2,"pending command payload stays stable");ready=1;cycles(3);
  key(0);check(last==0,"more matrix previous mapping");key(7);check(last==7,"more matrix save mapping");
  key(8);check(confirm,"matrix delete arms confirmation");key(15);check(!open && !confirm,"matrix BACK cancels confirmation and returns to settings");
  key(15);check(open,"settings R4C4 reopens more");menu=0;cycles(3);check(!open,"S0/page exit closes more");
  $display("PASS tb_ui_more checks=%0d commands=%0d",checks,commands);$finish;
 end
endmodule
