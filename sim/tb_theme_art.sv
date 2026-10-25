`timescale 1ns/1ps
`include "check.svh"
module tb_theme_art;
 reg clk=0;always #5 clk=~clk;
 reg [1:0] theme=1;reg [3:0] animation=0;
 reg [10:0] x=0,y=0;wire [23:0] pixel;
 integer checks=0,changed=0,n,fd;reg [23:0] static_frame[0:95999];
 reg [23:0] cat_sample[0:20479];reg [4095:0] outdir,path;
 ui_theme_art dut(clk,theme,animation,x,y,pixel,1'b1);
 task at(input integer xx,yy);begin
  @(negedge clk);x=xx;y=yy;@(posedge clk);#1;
  `CHECK((^pixel)!==1'bx,"synchronous artwork ROM pixel defined")
 end endtask
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir=".";
  for(n=0;n<16;n=n+1)begin
   animation=n;theme=1;at(620,250);
   `CHECK(dut.anim_addr>=0 && dut.anim_addr<327680,"cat frame address bounded")
   theme=2;at(620,250);
   `CHECK(dut.anim_addr>=0 && dut.anim_addr<327680,"capybara frame address bounded")
  end
  theme=1;animation=0;
  for(n=0;n<20480;n=n+1)begin at(500+(n%128)*2,96+(n/128)*2);cat_sample[n]=pixel;end
  animation=6;
  for(n=0;n<20480;n=n+1)begin
   at(500+(n%128)*2,96+(n/128)*2);if(pixel!=cat_sample[n])changed=changed+1;
  end
  `CHECK(changed>1000,"video frames contain real changing dance pixels")
  theme=3;animation=0;
  for(n=0;n<96000;n=n+1)begin at((n%400)*2,(n/400)*2);static_frame[n]=pixel;end
  animation=15;changed=0;
  for(n=0;n<96000;n=n+1)begin
   at((n%400)*2,(n/400)*2);
   `CHECK(pixel===static_frame[n],"entire Easter photograph is independent of video animation index")
   if(pixel!=static_frame[n])changed=changed+1;
  end
  `CHECK(changed==0,"Easter photograph remains completely static")
  $display("PASS tb_theme_art checks=%0d easter_changed=%0d",checks,changed);$finish;
 end
endmodule
