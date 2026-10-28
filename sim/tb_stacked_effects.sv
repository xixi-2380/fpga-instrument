`timescale 1ns/1ps
`include "check.svh"
module tb_stacked_effects;
 parameter integer PROD=0;
 reg clk=0,rst=1,input_valid=0,cfg=0;always #5 clk=~clk;
 reg [2:0] mask=0;reg [14:0] delay_samples=0;
 reg [8:0] echo=64,room=64,depth=128;reg [3:0] rate=5;
 reg signed [15:0] sample=0;wire ready,valid;wire signed [15:0] result;
 integer checks=0,fd,scan,reset_op,config_op,m,n,e,r,d,h,x,expected,latency,max_latency=0,vectors=0;
 reg [4095:0] filename;
 audio_effects #(.DELAY_SAMPLES(PROD?7200:8),.MAX_DELAY_SAMPLES(PROD?24000:32),
  .D0(PROD?1499:3),.D1(PROD?1601:5),.D2(PROD?1867:7),.D3(PROD?2053:11)) dut(
  .clk(clk),.rst(rst),.enable(1'b0),.mode(2'd0),.in_valid(input_valid),.in_sample(sample),
  .in_ready(ready),.out_valid(valid),.out_sample(result),.cfg_valid(cfg),.cfg_echo_wet(echo),
  .cfg_room_wet(room),.cfg_tremolo_depth(depth),.cfg_tremolo_rate_hz(rate),
  .effect_mask(mask),.cfg_echo_samples(delay_samples));
 initial begin
  if(!$value$plusargs("STACKED_VECTORS=%s",filename))$fatal(1,"missing independent vectors");
  fd=$fopen(filename,"r");#12;rst=0;
  while(!$feof(fd))begin
   scan=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d\n",reset_op,config_op,m,n,e,r,d,h,x,expected);
   if(scan==10)begin
    vectors=vectors+1;
    if(reset_op)begin
     @(negedge clk);input_valid=1;sample=32767;@(posedge clk);#1;
     rst=1;input_valid=0;#1;`CHECK(!valid && result==0,"reset cancels staged effects and dirty history")
     @(negedge clk);rst=0;
    end else begin
     @(negedge clk);cfg=config_op;delay_samples=n;echo=e;room=r;depth=d;rate=h;mask=m;
     @(posedge clk);#1;@(negedge clk);cfg=0;sample=x;input_valid=1;
     `CHECK(ready,"full chain ready for new sample")
     @(posedge clk);#1;`CHECK(!ready && !valid,"exactly one owner for in-flight sample")
     @(negedge clk);input_valid=0;sample=~sample;mask=~mask;
     latency=0;
     while(!valid && latency<16)begin @(posedge clk);#1;latency=latency+1;end
     if(latency>max_latency)max_latency=latency;
     if(!valid || $signed(result)!==expected)begin
      $display("STACKED vector=%0d mask=%0d input=%0d got=%0d expected=%0d delay=%0d latency=%0d",vectors,m,x,$signed(result),expected,n,latency);
      $fatal(1,"independent serial effect model mismatch");
     end
     checks=checks+1;
     `CHECK(ready && latency<=12,"serial stages meet bounded sample budget")
     @(posedge clk);#1;`CHECK(!valid,"no duplicate output in idle gap")
    end
   end else if(scan!=-1)$fatal(1,"malformed vector");
  end
  $display("PASS tb_stacked_effects checks=%0d vectors=%0d max_cycles=%0d production=%0d",checks,vectors,max_latency,PROD);$finish;
 end
 initial begin #100000000;$fatal(1,"stacked effects timeout");end
endmodule
