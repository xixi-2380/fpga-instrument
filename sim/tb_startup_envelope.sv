`timescale 1ns/1ps
`include "check.svh"
module tb_startup_envelope;
 reg clk=0,rst=1,ce=0;always #5 clk=~clk;wire pa;wire [16:0] level;
 integer checks=0,i;
 startup_envelope #(.MUTE(480),.FADE(240)) dut(clk,rst,ce,pa,level);
 initial begin
  #12 rst=0;
  for(i=1;i<=725;i=i+1) begin
   @(negedge clk);ce=1;@(posedge clk);#1;
   if(i<=480) begin `CHECK(!pa && level==0,"480 complete muted frames") end
   else if(i<=721) begin `CHECK(pa && level==((i-481)*65536/240),"fade reference") end
   else begin `CHECK(pa && level==65536,"full gain hold") end
   @(negedge clk);ce=0;
  end
  rst=1;#1;`CHECK(!pa && level==0,"mute on reset")
  $display("PASS tb_startup_envelope checks=%0d",checks);$finish;
 end
endmodule
