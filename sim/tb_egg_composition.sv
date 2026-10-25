`timescale 1ns/1ps
`include "check.svh"
module tb_egg_composition;
 reg clk=0;always #5 clk=~clk;
 reg [10:0] x=0,y=0;reg [3:0] animation=0;wire [23:0] pixel;
 reg [23:0] original[0:383999];integer checks=0,changed=0,portrait=0,sole=0;
 ui_theme_art dut(clk,2'd3,animation,x,y,pixel,1'b0);
 task at(input integer xx,yy);begin @(negedge clk);x=xx;y=yy;@(posedge clk);#1;
  `CHECK(dut.egg_addr>=0 && dut.egg_addr<30000,"static photograph address always stays within its complete ROM")
 end endtask
 initial begin
  for(integer n=0;n<384000;n=n+1)begin
   at(n%800,n/800);original[n]=pixel;
   `CHECK((^pixel)!==1'bx,"large Easter portrait pixels are defined")
   if(n%800>=80 && n%800<210 && n/800>=140 && n/800<260 && pixel[23:16]>integer'(pixel[15:8])+35 && pixel[7:0]>integer'(pixel[15:8])+15 && pixel[23:16]>integer'(pixel[7:0])+20)portrait=portrait+1;
   if(n%800>=270 && n%800<420 && n/800>=150 && n/800<390 && pixel[23:16]>integer'(pixel[15:8])+20 && pixel[15:8]>integer'(pixel[7:0])+20)sole=sole+1;
  end
  `CHECK(portrait>1200 && sole>10000,"woman and foreground foot are both visible, not a foot-only frame")
  animation=15;
  for(integer n=0;n<384000;n=n+1)begin
   at(n%800,n/800);
   `CHECK(pixel===original[n],"every photograph pixel is static across changed animation counter values")
   if(pixel!=original[n])changed=changed+1;
  end
  `CHECK(changed==0,"neither the person nor the foot moves")
  // A fixed safety margin protects the complete head and foot.
  at(350,116);`CHECK(pixel[23:16]>=220 && pixel[15:8]>=220 && pixel[7:0]>=220,"static photograph retains a light margin above the complete head and foot")
  $display("PASS tb_egg_composition checks=%0d portrait=%0d foot=%0d changed=%0d",checks,portrait,sole,changed);$finish;
 end
endmodule
