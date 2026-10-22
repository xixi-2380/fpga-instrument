`timescale 1ns/1ps
`include "check.svh"
module tb_audio_effects;
 parameter integer PROD=0;
 reg clk=0,rst=1,en=0,valid=0;
 reg [1:0] mode=0;
 reg signed [15:0] sample=0;
 wire ready,out_valid;wire signed [15:0] result;
 integer checks=0,fd,scan,lines=0,latency;
 reg [35:0] vector;reg [4095:0] filename;
 always #5 clk=~clk;
 audio_effects #(.DELAY_SAMPLES(PROD?7200:8),.D0(PROD?1499:3),.D1(PROD?1601:5),
  .D2(PROD?1867:7),.D3(PROD?2053:11),.LFO_STEP(PROD?32'd447392:32'h10000000))
  dut(clk,rst,en,mode,valid,sample,ready,out_valid,result);
 initial begin
  if(!$value$plusargs("EFFECT_VECTORS=%s",filename))$fatal(1,"Generate effects vectors first");
  fd=$fopen(filename,"r");if(!fd)$fatal(1,"Cannot open effect vectors");
  #12 rst=0;
  while(!$feof(fd))begin
   scan=$fscanf(fd,"%h\n",vector);
   if(scan==1)begin
    lines=lines+1;
    if(vector[35])begin
     // Cancel a sample after its read has started; old RAM must stay masked.
     @(negedge clk);valid=1;sample=32767;
     @(posedge clk);@(negedge clk);rst=1;valid=0;#1;
     `CHECK(!out_valid && result==0 && !ready,"mid-processing reset cancels output")
     repeat(2)@(negedge clk);rst=0;
    end else begin
     @(negedge clk);valid=1;sample=vector[31:16];mode=vector[34:33];en=vector[32];
     `CHECK(ready,"engine accepts every requested sample")
     @(posedge clk);#1;`CHECK(!out_valid && !ready,"engine captures and owns one sample")
     @(negedge clk);valid=0;sample=~sample;mode=~mode;en=~en;
     latency=0;
     while(!out_valid && latency<5)begin @(posedge clk);#1;latency=latency+1;end
     `CHECK(out_valid && latency==3,"fixed three-cycle post-accept latency")
     if(result!==vector[15:0])begin
      $display("VECTOR %0d expected=%0d result=%0d",lines,$signed(vector[15:0]),result);
      $fatal(1,"independent sample model mismatch");
     end
     checks=checks+1;
     `CHECK(ready,"engine is ready after output")
     @(posedge clk);#1;`CHECK(!out_valid,"no duplicate result during idle")
    end
   end
  end
  $fclose(fd);$display("PASS tb_audio_effects checks=%0d vectors=%0d production=%0d",checks,lines,PROD);$finish;
 end
 initial begin #100000000;$fatal(1,"effects vector timeout");end
endmodule
