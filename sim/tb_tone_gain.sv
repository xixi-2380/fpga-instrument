`timescale 1ns/1ps
`include "check.svh"
module tb_tone_gain;
 reg clk=0,rst=1,iv=0;always #5 clk=~clk;
 reg signed [15:0] s;reg [16:0] level;wire ov;wire signed [15:0] q;
 integer checks=0,i,j,e;reg signed [63:0] reference_product;
 tone_gain dut(clk,rst,iv,s,level,ov,q);
 initial begin
  #12 rst=0;
  for(i=0;i<500;i=i+1) begin
   for(j=0;j<4;j=j+1) begin
    @(negedge clk);iv=1;
    case(i) 0:s=0;1:s=32767;2:s=-32768;default:s=$random;endcase
    case(j) 0:level=0;1:level=1;2:level=32768;3:level=65536;endcase
    reference_product=$signed(s)*$signed({1'b0,level});e=reference_product>>>21;
    @(posedge clk);#1;`CHECK(ov && q==e,"signed fixed point gain")
   end
  end
  @(negedge clk);iv=0;@(posedge clk);#1;`CHECK(!ov,"gain valid latency")
  $display("PASS tb_tone_gain checks=%0d",checks);$finish;
 end
endmodule
