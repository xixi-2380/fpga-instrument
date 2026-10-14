`timescale 1ns/1ps
`include "check.svh"
module tb_pt8211_tx;
 reg clk=0,rst=1;always #5 clk=~clk;wire bck,rise_ce,fall_ce,fc,ws,din;wire [4:0] idx;
 reg [15:0] l=0,r=0,decoded=0,expected=0;integer checks=0,n=0,bitn=0,ch=0,k;
 audio_timing timing(clk,rst,bck,rise_ce,fall_ce,fc,idx);
 pt8211_tx dut(clk,rst,fall_ce,idx,l,r,ws,din);
 // Independent pin-level decoder: WS defines the channel, BCK samples DIN.
 always @(posedge bck) if(!rst) begin
  decoded={decoded[14:0],din};
  `CHECK(ws==(ch==1),"WS polarity/alignment")
  if(bitn==15) begin
   expected=ch?l:r;`CHECK(decoded==expected,"serial word bit order")
   decoded=0;bitn=0;ch=1-ch;n=n+1;
  end else bitn=bitn+1;
 end
 task pair(input [15:0] a,b);begin
  @(negedge clk);l=a;r=b;
  wait(n>=k+2);k=n;
 end endtask
 initial begin
  #12 rst=0;k=0;pair(0,0);pair(16'h1234,16'hfedc);
  pair(16'h8000,16'h7fff);
  for(integer j=0;j<16;j=j+1) pair(16'h1<<j,~(16'h1<<j));
  $display("PASS tb_pt8211_tx checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
