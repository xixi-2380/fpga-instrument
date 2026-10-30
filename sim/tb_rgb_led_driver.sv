`timescale 1ns/1ps
module tb_rgb_led_driver;
 reg clk=0,rst_n=0,start=0,en=1;always #10 clk=~clk;
 reg [7:0] brightness=128,count=18;reg [503:0] frame=0,expected;
 wire data,busy,done;integer checks=0;time high_begin,previous_rise;
 reg [503:0] received;reg [23:0] color;integer red,green,blue;
 ws2812_driver dut(clk,rst_n,start,en,brightness,count,frame,data,busy,done);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task capture;begin
  received=0;previous_rise=0;
  for(integer n=0;n<504;n++)begin
   while(data!==1'b1)@(negedge clk);high_begin=$time;
   if(n%24!=0)check(high_begin-previous_rise==1260,"bit period 1260ns");
   previous_rise=high_begin;
   while(data===1'b1)@(negedge clk);check($time-high_begin==360 || $time-high_begin==680,"50MHz high pulse 360/680ns");
   received[(n/24)*24+23-(n%24)]=($time-high_begin==680);
  end
  @(posedge done);#1;check(received===expected,"21 GRB pixels / scaling / inactive count");
  check(!busy && !data,"latch completes low and idle");
 end endtask
 task launch;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
 initial begin
  for(integer i=0;i<21;i++)begin
   color={8'(i*11+1),8'(255-i*7),8'(i*9+3)};frame[i*24+:24]=color;
   red=integer'(color[23:16])*128/255;green=integer'(color[15:8])*128/255;blue=integer'(color[7:0])*128/255;
   expected[i*24+:24]=i<18?{8'(green),8'(red),8'(blue)}:24'd0;
  end
  #45;rst_n=1;wait(!busy);
  fork capture;begin launch;repeat(40)@(negedge clk);frame='1;brightness=255;count=21;start=1;repeat(4)@(negedge clk);start=0;end join
  en=0;expected=0;fork capture;launch;join
  $display("PASS tb_rgb_led_driver checks=%0d",checks);$finish;
 end
 initial begin #5000000;$fatal(1,"driver timeout");end
endmodule
