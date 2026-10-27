`timescale 1ns/1ps
`include "check.svh"
module tb_ultrasonic_volume;
 parameter integer LOST_MS=20;
 reg clk=0,rst=1,cfg_valid=1,enabled=0,report=0,valid=0;always #500 clk=~clk;
 reg [2:0] sensitivity=1;reg [6:0] minimum=0,maximum=100,manual=43;
 reg [7:0] version=0;reg [12:0] mm=0;
 wire [6:0] target;wire [2:0] status;wire [11:0] bcd;wire [7:0] applied;
 integer checks=0;
 ultrasonic_volume #(.CLOCK_HZ(1000000),.LOST_MS(LOST_MS)) dut(
  clk,rst,cfg_valid,enabled,sensitivity,minimum,maximum,manual,version,
  report,valid,mm,target,status,bcd,applied);
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task sample(input integer distance,input bit good);begin
  @(negedge clk);mm=distance;valid=good;report=1;@(negedge clk);report=0;cycles(110);
 end endtask
 task triple(input integer distance);begin repeat(3)sample(distance,1);end endtask
 initial begin
  #1200;rst=0;cycles(4);`CHECK(target==43 && status==0,"off follows manual snapshot")
  enabled=1;version=1;cycles(4);`CHECK(target==43 && status==1 && applied==1,"enable starts at current manual target")
  sample(50,1);`CHECK(target==100 && status==2 && bcd==12'h050,"near boundary maps to maximum and 5.0cm")
  sample(100,1);`CHECK(target==100,"median rejects one abrupt distance change")
  sample(100,1);`CHECK(target==86 && bcd==12'h100,"second consistent measurement tracks 10.0cm")
  sample(390,1);`CHECK(target==86,"single far outlier does not change volume")
  sample(100,1);`CHECK(target==86,"median recovers after outlier")
  sample(0,0);`CHECK(target==86 && status==3,"short loss holds last target")
  cycles(500);`CHECK(target==86,"short loss cannot cause a sudden drop")
  minimum=20;maximum=80;version=2;cycles(5);`CHECK(target==80 && applied==2,"new upper limit clamps target")
  triple(400);`CHECK(target==20,"far boundary maps to configured minimum")
  triple(20);`CHECK(target==80,"valid close echoes clamp to configured maximum")
  sensitivity=5;version=3;cycles(5);triple(125);
  `CHECK(target==50 && bcd==12'h125,"high sensitivity 5..20cm has midpoint at 12.5cm")
  sample(500,1);`CHECK(target==50 && status==3,"outside 40cm is not a control sample")
  cycles(LOST_MS*1000+100);`CHECK(target==20 && status==4,"continuous loss returns to lower limit at configured deadline")
  triple(50);`CHECK(target==80 && status==2,"valid echoes recover after loss")
  for(integer s=1;s<=5;s=s+1)begin
   sensitivity=s;version=version+1'b1;cycles(4);
   for(integer d=50;d<=400;d=d+1)begin
    triple(d);
    `CHECK(target==20+((d>=450-s*50)?0:(((450-s*50-d)*60+(400-s*50)/2)/(400-s*50))),"all five sensitivity spans match independent integer mapping")
   end
  end
  minimum=80;maximum=80;version=version+1'b1;cycles(4);triple(100);
  `CHECK(target==80,"equal limits produce a constant volume")
  enabled=0;manual=37;version=version+1'b1;cycles(5);`CHECK(target==37 && status==0,"off leaves manual snapshot in control")
  enabled=1;version=version+1'b1;cycles(3);`CHECK(target==80 && applied==version,"new session uses new version and bounded manual start")
  rst=1;#1;`CHECK(status==0 && target==100,"reset defaults")
  $display("PASS tb_ultrasonic_volume checks=%0d lost_ms=%0d",checks,LOST_MS);$finish;
 end
 initial begin #2000000000;$fatal(1,"ultrasonic volume timeout");end
endmodule
