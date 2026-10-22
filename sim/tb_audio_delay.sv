`timescale 1ns/1ps
`include "check.svh"
module delay_case #(parameter integer N=3)(output reg done=0,output integer checks=0);
 reg clk=0,rst=1,en=0,valid=0;reg signed [15:0] sample=0;
 wire ready,out_valid;wire signed [15:0] result;
 integer history[0:N-1],pointer=0,filled=0,weight=0,old,expected;
 reg signed [63:0] wide;
 reg [31:0] random_state=32'h12345678;
 always #5 clk=~clk;
 audio_delay #(.DELAY_SAMPLES(N)) dut(clk,rst,en,valid,sample,ready,out_valid,result,);
 task send(input integer x,input bit enabled,input integer gaps);begin
  @(negedge clk);sample=x;en=enabled;valid=1;
  `CHECK(ready,"effect can accept the next frame")
  old=filled>=N?history[pointer]:0;
  wide=(256-weight)*x+weight*old;expected=wide>>>8;
  history[pointer]=x;pointer=(pointer+1)%N;if(filled<N)filled=filled+1;
  if(enabled && weight<64)weight=weight+1;else if(!enabled && weight>0)weight=weight-1;
  @(posedge clk);#1;`CHECK(!out_valid && !ready,"RAM read occurs before write/output")
  @(negedge clk);valid=0;
  @(posedge clk);#1;
  `CHECK(out_valid && result==expected,"signed output matches independent delay history")
  `CHECK(result>=-32768 && result<=32767,"full-scale blend does not wrap")
  `CHECK(ready,"effect finishes within two clocks")
  repeat(gaps)begin @(posedge clk);#1;`CHECK(!out_valid,"idle gaps do not duplicate output") end
 end endtask
 task reset_model;begin
  @(negedge clk);rst=1;valid=0;#1;
  `CHECK(!out_valid && result==0 && !ready,"reset cancels output and blocks acceptance")
  pointer=0;filled=0;weight=0;
  @(negedge clk);rst=0;
 end endtask
 initial begin
  #12 rst=0;
  // Warm up with silence, then a single impulse: one echo exactly N samples later.
  repeat(70)send(0,1,0);
  send(20000,1,0);
  for(integer i=1;i<=N+1;i=i+1)begin
   send(0,1,0);
   if(i==N)begin `CHECK(result==5000,"impulse echo is exactly 150ms at production length") end
   else begin `CHECK(result==0,"no early or repeated impulse echo") end
  end
  for(integer i=0;i<N+100;i=i+1)begin
   random_state=random_state*1664525+1013904223;
   send($signed(random_state[15:0]),(i%173)<90,i%3);
  end
  // Preserve dirty RAM across reset; fill masking must exclude every stale sample.
  reset_model();for(integer i=0;i<N+80;i=i+1)begin
   send(0,1,0);`CHECK(result==0,"no pre-reset echo leaks into restart")
  end
  // Force positive/negative endpoints and bypass after fade-out.
  repeat(70)send(-32768,0,0);`CHECK(result==-32768,"bypass preserves negative full scale")
  send(32767,0,0);`CHECK(result==32767,"bypass preserves positive full scale")
  @(negedge clk);sample=12345;valid=1;@(posedge clk);#1;rst=1;valid=0;#1;
  `CHECK(!out_valid && result==0,"reset cancels an in-flight memory transaction")
  done=1;
 end
endmodule
module tb_audio_delay;
 wire d1,d3,dp;wire integer c1,c3,cp;
 delay_case #(.N(1)) a(d1,c1);
 delay_case #(.N(3)) b(d3,c3);
 delay_case #(.N(7200)) production(dp,cp);
 initial begin wait(d1 && d3 && dp);$display("PASS tb_audio_delay checks=%0d",c1+c3+cp);$finish;end
 initial begin #3000000;$fatal(1,"delay unit timeout");end
endmodule
