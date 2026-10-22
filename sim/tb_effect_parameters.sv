`timescale 1ns/1ps
`include "check.svh"
module tb_effect_parameters;
 parameter integer PROD=0;
 reg clk=0,rst=1,en=0,valid=0,cfg_valid=0;
 reg [1:0] mode=0;
 reg signed [15:0] sample=0;
 reg [8:0] echo_wet=64,room_wet=64,depth=128;
 reg [3:0] rate_hz=5;
 wire ready,out_valid,cfg_ready,cfg_applied;
 wire signed [15:0] result;
 integer checks=0,fd,scan,lines=0,latency,op,e,r,d,hz,m,onoff,x,expected;
 reg [4095:0] filename;
 always #5 clk=~clk;
 audio_effects #(.DELAY_SAMPLES(PROD?7200:8),.D0(PROD?1499:3),.D1(PROD?1601:5),
  .D2(PROD?1867:7),.D3(PROD?2053:11),.LFO_STEP(PROD?32'd447392:32'h10000000)) dut(
  .clk(clk),.rst(rst),.enable(en),.mode(mode),.in_valid(valid),.in_sample(sample),
  .in_ready(ready),.out_valid(out_valid),.out_sample(result),.cfg_valid(cfg_valid),
  .cfg_echo_wet(echo_wet),.cfg_room_wet(room_wet),.cfg_tremolo_depth(depth),
  .cfg_tremolo_rate_hz(rate_hz),.cfg_ready(cfg_ready),.cfg_applied(cfg_applied));
 task command;begin
  cfg_valid=1;echo_wet=e;room_wet=r;depth=d;rate_hz=hz;
  `CHECK(cfg_ready,"configuration interface accepts complete snapshot")
 end endtask
 initial begin
  if(!$value$plusargs("PARAM_VECTORS=%s",filename))$fatal(1,"Generate runtime vectors first");
  fd=$fopen(filename,"r");if(!fd)$fatal(1,"Missing vectors");
  #12 rst=0;
  while(!$feof(fd))begin
   scan=$fscanf(fd,"%d %d %d %d %d %d %d %d %d\n",op,e,r,d,hz,m,onoff,x,expected);
   if(scan==9)begin
    lines=lines+1;
    if(op==3)begin
     @(negedge clk);valid=1;sample=32767;
     @(posedge clk);@(negedge clk);rst=1;valid=0;cfg_valid=0;#1;
     `CHECK(!out_valid && !cfg_ready && !cfg_applied,"reset cancels work and configuration acknowledgement")
     repeat(2)@(negedge clk);rst=0;
    end else begin
     @(negedge clk);cfg_valid=0;
     if(op==1)begin
      command;@(posedge clk);#1;`CHECK(cfg_applied,"acknowledge configuration on acceptance")
      @(negedge clk);cfg_valid=0;
     end
     valid=1;sample=x;mode=m;en=onoff;
     `CHECK(ready,"accept runtime audio sample")
     @(posedge clk);#1;`CHECK(!out_valid && !ready,"sample ownership unchanged")
     @(negedge clk);valid=0;sample=~sample;mode=~mode;en=~en;
     if(op==2)command;
     latency=0;
     while(!out_valid && latency<5)begin
      @(posedge clk);#1;latency=latency+1;
      if(op==2 && latency==1)begin
       `CHECK(cfg_applied,"configuration accepted during audio processing")
      end
      if(latency==1)begin
       @(negedge clk);cfg_valid=0;echo_wet=0;room_wet=0;depth=0;rate_hz=0;
      end
     end
     `CHECK(out_valid && latency==3,"runtime controls preserve fixed audio latency")
     if($signed(result)!==expected)begin
      $display("RUNTIME line=%0d op=%0d mode=%0d x=%0d expected=%0d got=%0d",lines,op,m,x,expected,$signed(result));
      $fatal(1,"runtime independent model mismatch");
     end
     checks=checks+1;
     `CHECK(ready,"ready after result")
     @(posedge clk);#1;`CHECK(!out_valid && !cfg_applied,"no spurious output or config acknowledgement")
    end
   end else if(scan!=-1)$fatal(1,"Malformed runtime vector after line %0d",lines);
  end
  $fclose(fd);$display("PASS tb_effect_parameters checks=%0d vectors=%0d production=%0d",checks,lines,PROD);$finish;
 end
 initial begin #100000000;$fatal(1,"runtime effects timeout");end
endmodule
