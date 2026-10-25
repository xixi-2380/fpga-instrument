`timescale 1ns/1ps
`include "check.svh"
module tb_egg_composition;
 reg clk=0;always #5 clk=~clk;
 reg [10:0] x=0,y=0;reg [3:0] foot=0;wire [23:0] pixel;
 reg [23:0] original[0:383999];integer checks=0,changed=0,portrait=0,sole=0;
 ui_theme_art dut(clk,2'd3,4'd0,foot,x,y,pixel,1'b0);
 task at(input integer xx,yy);begin @(negedge clk);x=xx;y=yy;@(posedge clk);#1;end endtask
 initial begin
  for(integer n=0;n<384000;n=n+1)begin
   at(n%800,n/800);original[n]=pixel;
   `CHECK((^pixel)!==1'bx,"large Easter portrait pixels are defined")
   if(n%800>=80 && n%800<210 && n/800>=140 && n/800<260 && pixel!=original[0])portrait=portrait+1;
   if(n%800>=270 && n%800<420 && n/800>=150 && n/800<390 && pixel!=original[0])sole=sole+1;
  end
  `CHECK(portrait>6000 && sole>15000,"woman and foreground foot are both visible, not a foot-only frame")
  foot=15;
  for(integer n=0;n<384000;n=n+1)begin
   at(n%800,n/800);
   if(n%800<220)`CHECK(pixel===original[n],"person and left background stay fixed during foot enlargement")
   if(pixel!=original[n])changed=changed+1;
  end
  `CHECK(changed>1500 && changed<35000,"foot animation changes only a limited foreground region")
  // Top of the foot must have margin at either scale, avoiding clipped toes.
  at(350,116);`CHECK(pixel===original[0],"top padding remains at maximum foot zoom")
  $display("PASS tb_egg_composition checks=%0d portrait=%0d foot=%0d changed=%0d",checks,portrait,sole,changed);$finish;
 end
endmodule
