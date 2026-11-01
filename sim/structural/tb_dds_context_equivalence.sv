`timescale 1ns/1ps
module tb_dds_context_equivalence;
 parameter integer VOICES=32,INDEX_W=VOICES>1?$clog2(VOICES):1;
 reg clk=0,rst=1,ce=0,restart=0;always #5 clk=~clk;
 reg [31:0] fcw=0;reg [INDEX_W-1:0] index=0;reg [4:0] timbre=0;
 wire signed [15:0] a,b;wire va,vb;wire [VOICES*32-1:0] pa,pb;
 dds_sine #(.VOICES(VOICES),.PREPARE_CONTEXT(1)) dut(clk,rst,ce,fcw,a,va,pa,restart,index,timbre);
 reference_dds_sine_c6352fa #(.VOICES(VOICES)) ref_dut(clk,rst,ce,fcw,b,vb,pb,restart,index,timbre);
 integer checks=0,seed=32'h2380dade;
 always @(posedge clk or posedge rst)begin
  #0.001;checks++;
  if({a,va,pa}!=={b,vb,pb})$fatal(1,"DDS context mismatch voice=%0d tone=%0d checks=%0d",index,timbre,checks);
 end
 task transaction(input integer slot,input integer tone,input bit reset_phase,input [31:0] frequency,input integer gap);
 begin
  @(negedge clk);ce=0;index=INDEX_W'(slot);
  // One idle rising edge captures the new context. Other parameters may
  // change immediately before the original sample edge, as in synth_core.
  repeat(gap)@(negedge clk);
  fcw=frequency;timbre=5'(tone);restart=reset_phase;ce=1;
  @(negedge clk);ce=0;
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;
  for(integer n=0;n<10000;n++)begin
   transaction($unsigned($random(seed))%VOICES,n%26,n%79==0,$random(seed),1+n%5);
   if(n%2011==7)begin rst=1;repeat(2)@(negedge clk);rst=0;end
  end
  // Both percussion age boundaries and saturation, with phase wrap and
  // variable timbre/frequency over a single long-lived physical voice.
  for(integer n=0;n<97010;n++)transaction(0,n%2==0?16:25,0,n%2==0?32'hffffffff:32'd1234567,1);
  $display("PASS tb_dds_context_equivalence voices=%0d checks=%0d",VOICES,checks);$finish;
 end
endmodule
