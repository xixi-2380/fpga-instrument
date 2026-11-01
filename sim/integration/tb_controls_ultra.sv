`timescale 1ns/1ps
module tb_controls_ultra;
 reg clk=0,rst=1,cfg=1,en=1,report=0,valid=1;always #5 clk=~clk;
 reg [2:0] sensitivity=1;reg [6:0] minimum=5,maximum=40;reg [7:0] version=1;reg [12:0] distance=0;
 wire [17:0] ratio;wire [2:0] status;wire [11:0] bcd;wire [7:0] applied;
 ultrasonic_pitch #(.CLOCK_HZ(100000),.LOST_MS(10)) dut(clk,rst,cfg,en,sensitivity,minimum,maximum,version,report,valid,distance,ratio,status,bcd,applied);
 integer checks=0,seed=32'h2380a002,previous=0,older=0,wanted=65536;reg have=0;
 task clocks(input integer n);begin repeat(n)@(negedge clk);end endtask
 function automatic integer median(input integer a,b,c);begin
  if((a>=b && a<=c)||(a>=c && a<=b))median=a;
  else if((b>=a && b<=c)||(b>=c && b<=a))median=b;else median=c;
 end endfunction
 function automatic integer expected(input integer d);integer lo,hi,mid,dead,span,numer;begin
  lo=minimum*10;hi=maximum*10;mid=(lo+hi)/2;dead=(sensitivity>=1 && sensitivity<=5)?6-sensitivity:5;
  if(d<=lo)expected=73562;
  else if(d>=hi)expected=58386;
  else if(d>=mid-dead && d<=mid+dead)expected=65536;
  else if(d<mid)begin span=mid-lo;numer=(mid-d)*8026+span/2;expected=65536+numer/span;end
  else begin span=hi-mid;numer=(d-mid)*7150+span/2;expected=65536-numer/span;end
 end endfunction
 task configure(input integer lo,hi,s);begin
  minimum=lo;maximum=hi;sensitivity=s;version=version+1'b1;clocks(3);have=0;wanted=65536;
  if(ratio!=65536 || status!=1 || applied!=version)$fatal(1,"Changed version/range did not clear pitch history");checks++;
 end endtask
 task sample(input integer d,input bit v);integer filtered,raw,packed_bcd;begin
  distance=d;valid=v;report=1;
  if(v && d>=20 && d<=4000)begin
   filtered=have?median(d,previous,older):d;older=have?previous:d;previous=d;have=1;wanted=expected(filtered);
  end
  clocks(1);report=0;clocks(28);
  if(ratio!=wanted)$fatal(1,"Distance mapping mismatch d=%0d ratio=%0d wanted=%0d range=%0d/%0d",d,ratio,wanted,minimum,maximum);
  if(v && d>=20 && d<=4000)begin
   raw=d>999?999:d;packed_bcd=(raw/100)*256+((raw/10)%10)*16+raw%10;
   if(bcd!=packed_bcd || status!=2)$fatal(1,"Distance BCD or tracking status failed d=%0d bcd=%h",d,bcd);
  end
  checks++;
 end endtask
 initial begin
  clocks(3);rst=0;clocks(3);configure(5,40,1);
  sample(50,1);sample(225,1);sample(225,1);sample(400,1);sample(400,1);
  for(integer s=1;s<=5;s++)begin configure(5,40,s);for(integer d=20;d<=450;d++)sample(d,1);end
  // Large isolated spikes must not move a centered median history.
  configure(5,40,1);sample(225,1);sample(225,1);sample(50,1);if(ratio!=65536)$fatal(1,"Median failed isolated near spike");
  sample(225,1);sample(225,1);sample(400,1);if(ratio!=65536)$fatal(1,"Median failed isolated far spike");
  sample(225,1);sample(10,0);if(status!=3)$fatal(1,"Invalid report did not hold last value");
  clocks(1100);wanted=65536;if(ratio!=65536 || status!=4)$fatal(1,"Stale sensor did not return neutral");
  sample(50,1);sample(50,1);clocks(2);en=0;clocks(2);if(ratio!=65536 || status!=0)$fatal(1,"Disable did not return neutral");
  en=1;clocks(3);have=0;wanted=65536;if(status!=1)$fatal(1,"Reenable did not await fresh sample");sample(400,1);
  for(integer n=0;n<1000;n++)begin
   if(n%20==0)configure(($unsigned($random(seed))%18)*5,100,1+$unsigned($random(seed))%5);
   sample(20+$unsigned($random(seed))%3981,n%11!=0);
  end
  configure(0,5,5);sample(20,1);sample(25,1);sample(50,1);configure(95,100,1);sample(950,1);sample(975,1);sample(1000,1);
  version=255;clocks(3);version=0;clocks(3);if(applied!=0 || ratio!=65536)$fatal(1,"Version wrap did not reset ratio");
  // Cancel a serial mapping before it can publish a stale result.
  have=0;wanted=65536;distance=970;report=1;clocks(1);report=0;clocks(2);cfg=0;clocks(40);
  if(ratio!=65536 || status!=0)$fatal(1,"Cancelled divider published stale ratio");
  cfg=1;minimum=40;maximum=5;clocks(3);if(ratio!=65536 || status!=0)$fatal(1,"Invalid range was not disabled");
  $display("PASS tb_controls_ultra checks=%0d",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"Ultrasonic math timeout");end
endmodule
