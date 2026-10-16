`timescale 1ns/1ps
`include "check.svh"
module tb_dds_sine;
 reg clk=0,rst=1,ce=0,restart=0;reg [31:0] fcw=0;always #5 clk=~clk;
 wire signed [15:0] sample;wire valid;wire [31:0] phase;
 reg multi_ce=0,multi_restart=0;reg [4:0] index=0;reg [31:0] multi_fcw=0;
 wire signed [15:0] multi_sample;wire multi_valid;wire [1023:0] multi_phase;
 reg [31:0] models[0:31];
 dds_sine #(.VOICES(32)) shared(clk,rst,multi_ce,multi_fcw,multi_sample,multi_valid,multi_phase,multi_restart,index);
 integer checks=0,i,j,a,expected;reg [31:0] model=0;real x;
 dds_sine dut(clk,rst,ce,fcw,sample,valid,phase,restart,1'b0);
 initial begin
  #12 rst=0;
  for(j=0;j<5;j=j+1) begin
   case(j) 0:fcw=0;1:fcw=32'h0258bf26;2:fcw=1;3:fcw=32'h7fffffff;4:fcw=32'hffffffff;endcase
   for(i=0;i<1000;i=i+1) begin
    @(negedge clk);ce=1;a=model[31:20];x=$sin(6.283185307179586*a/4096.0)*32767.0;
    expected=x>=0?$rtoi(x+0.5):$rtoi(x-0.5);model=model+fcw;
    @(posedge clk);#1;`CHECK(valid && phase==model && sample==expected,"DDS phase/sample")
    @(negedge clk);ce=0;@(posedge clk);#1;`CHECK(!valid && phase==model,"DDS CE hold")
   end
  end
  @(negedge clk);ce=0;restart=1;@(posedge clk);#1;
  `CHECK(!valid && phase==model,"synchronous phase restart still respects sample CE")
  @(negedge clk);ce=1;fcw=32'h0258bf26;@(posedge clk);#1;
  `CHECK(valid && sample==0 && phase==fcw,"reassigned voice starts phase at zero")
  @(negedge clk);ce=0;restart=0;
  for(integer v=0;v<32;v=v+1)models[v]=0;
  for(integer n=0;n<1024;n=n+1)begin
   @(negedge clk);index=5'((n*13)%32);multi_ce=1;multi_restart=(n%71==0);
   multi_fcw=32'h0258bf26+n*32'h00012345;
   if(multi_restart)models[index]=0;
   a=models[index][31:20];x=$sin(6.283185307179586*a/4096.0)*32767.0;
   expected=x>=0?$rtoi(x+0.5):$rtoi(x-0.5);models[index]=models[index]+multi_fcw;
   @(posedge clk);#1;
   `CHECK(multi_valid && multi_sample==expected,"shared ROM uses selected independent phase")
   for(integer v=0;v<32;v=v+1)begin
    `CHECK(multi_phase[v*32+:32]==models[v],"only selected DDS context advances or restarts")
   end
   @(negedge clk);multi_ce=0;@(posedge clk);#1;
   `CHECK(!multi_valid,"shared DDS valid respects CE bubbles")
  end
  rst=1;#1;`CHECK(multi_phase==0 && !multi_valid,"reset clears all phase contexts")
`CHECK(phase==0 && !valid,"DDS reset")
  $display("PASS tb_dds_sine checks=%0d",checks);$finish;
 end
endmodule
