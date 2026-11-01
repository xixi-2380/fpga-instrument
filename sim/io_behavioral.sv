`timescale 1ns/1ps
// Explicit logical substitute only; not vendor-cell, PLL or timing validation.
module ODDR(output reg Q0,output wire Q1,input wire D0,D1,TX,CLK,CLEAR);
 always @(posedge CLK or posedge CLEAR)if(CLEAR)Q0<=0;else Q0<=D0;
 always @(negedge CLK or posedge CLEAR)if(CLEAR)Q0<=0;else Q0<=D1;
 assign Q1=TX;
endmodule
module GSR(input wire GSRI);endmodule
