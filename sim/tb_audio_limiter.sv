`timescale 1ns/1ps
module tb_audio_limiter;
 reg clk=0,rst=1,valid=0;always #5 clk=~clk;
 reg signed [15:0] sample=0;
 wire ready,ov,clipped;wire signed [15:0] result;wire [16:0] gain;
 integer checks=0,elapsed=0,max_cycles=0,fd,scanned;reg [63:0] vectors[0:9999];reg [4095:0] file;
 audio_limiter dut(clk,rst,valid,sample,ready,ov,result,gain,clipped);
 task check(input bit yes,input string why);begin checks++;if(!yes)$fatal(1,"%s",why);end endtask
 initial begin
  if(!$value$plusargs("LIMITER_VECTORS=%s",file))$fatal(1,"Missing limiter vectors");
  fd=$fopen(file,"r");scanned=$fscanf(fd,"%h",vectors[0]);$fclose(fd);
  if(scanned!=1 || vectors[0]>=10000)$fatal(1,"Invalid vector count");
  $readmemh(file,vectors,0,integer'(vectors[0]));repeat(3)@(negedge clk);rst=0;
  for(integer i=1;i<=vectors[0];i++)begin
   if(vectors[i][49])begin
    // Cancel a real transaction mid-scan, then invalidate old RAM by count.
    @(negedge clk);valid=1;sample=32767;@(negedge clk);valid=0;
    repeat(9)@(negedge clk);rst=1;repeat(2)@(negedge clk);rst=0;#1;
    check(!ov && ready,"reset cancels pending sample without clearing whole RAM");
   end
   repeat(i%7)@(negedge clk);
   check(ready,"one sample offered only when ready");valid=1;sample=vectors[i][48:33];
   @(negedge clk);valid=0;elapsed=1;
   while(!ov)begin @(negedge clk);elapsed++;check(elapsed<=128,"bounded <=128-cycle limiter calculation");end
   if(elapsed>max_cycles)max_cycles=elapsed;
   if(result!==vectors[i][15:0] || gain!==vectors[i][32:16])
    $fatal(1,"vector %0d input=%0d result=%0d expected=%0d gain=%0d expectedgain=%0d",i,sample,result,$signed(vectors[i][15:0]),gain,vectors[i][32:16]);
   check(!clipped && result<=29204 && result>=-29204,"window-bound limiter does not rely on hard clipping");
   @(negedge clk);check(!ov,"one output per accepted sample");
  end
  $display("PASS tb_audio_limiter checks=%0d vectors=%0d max_cycles=%0d",checks,vectors[0],max_cycles);$finish;
 end
 initial begin #10000000;$fatal(1,"limiter timeout");end
endmodule
