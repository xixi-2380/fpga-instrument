`timescale 1ns/1ps
`include "check.svh"
module tb_timbres;
 reg clk=0,rst=1,ce=0;reg [31:0] fcw=32'h00100000;reg [1:0] timbre=0;
 wire signed [15:0] sample;wire valid;wire [31:0] phase;integer checks=0;
 real angle,x,peak;integer expected;
 always #5 clk=~clk;
 dds_sine dut(clk,rst,ce,fcw,sample,valid,phase,1'b0,1'b0,timbre);
 function real wave(input integer t,input real a);
  case(t)
   1:wave=$sin(a)+0.20*$sin(2*a)+0.08*$sin(3*a);
   2:wave=$sin(a)+0.60*$sin(3*a)+0.30*$sin(5*a)+0.15*$sin(7*a);
   default:wave=$sin(a);
  endcase
 endfunction
 initial begin
  #12 rst=0;
  for(integer t=0;t<3;t=t+1)begin
   peak=0;
   for(integer n=0;n<4096;n=n+1)begin
    x=wave(t,6.283185307179586*n/4096.0);if(x<0)x=-x;if(x>peak)peak=x;
   end
   for(integer n=0;n<4096;n=n+1)begin
    @(negedge clk);ce=1;timbre=t;
    angle=6.283185307179586*n/4096.0;x=wave(t,angle)/peak*32767.0;
    expected=x>=0?$rtoi(x+0.5):$rtoi(x-0.5);
    @(posedge clk);#1;
    `CHECK(valid && sample==expected,"all preset samples match independent harmonic equation")
   end
   @(negedge clk);ce=0;@(posedge clk);#1;`CHECK(!valid,"valid preserves CE bubbles")
  end
  $display("PASS tb_timbres checks=%0d",checks);$finish;
 end
endmodule
