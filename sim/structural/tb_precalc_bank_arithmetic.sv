`timescale 1ns/1ps
module tb_precalc_bank_arithmetic;
 parameter integer VOICES=32,ATTACK=480,DECAY=4800,RELEASE=9600;
 localparam integer MAX_AD=ATTACK>DECAY?ATTACK:DECAY,MAX_N=MAX_AD>RELEASE?MAX_AD:RELEASE,CW=MAX_N>0?$clog2(MAX_N+1):1;
 localparam integer A_DEN=ATTACK>0?ATTACK:1,R_DEN=RELEASE>0?RELEASE:1;
 reg clk=0,rst=1,ce=0;always #5 clk=~clk;
 reg [17*VOICES-1:0] seeds=0,levels=0;wire [17*VOICES-1:0] aq,rq;wire [CW*VOICES-1:0] ar,rr;
 reg [16:0] numerator;integer checks=0;
 envelope_precalc_bank #(.VOICES(VOICES),.ATTACK(ATTACK),.DECAY(DECAY),.RELEASE(RELEASE)) bank(clk,rst,ce,seeds,levels,aq,rq,ar,rr);
 initial begin
  repeat(3)@(negedge clk);rst=0;repeat(VOICES+6)@(negedge clk);
  for(integer base=0;base<131072;base=base+VOICES)begin
   ce=1;@(posedge clk);#0.001;
   for(integer v=0;v<VOICES;v=v+1)begin seeds[v*17+:17]=base+v;levels[v*17+:17]=base+v;end
   @(negedge clk);ce=0;repeat(VOICES+5)@(negedge clk);
   for(integer v=0;v<VOICES;v=v+1)begin
    numerator=17'd65536-seeds[v*17+:17];checks=checks+1;
    if(aq[v*17+:17]!==17'(numerator/A_DEN) || ar[v*CW+:CW]!==CW'(numerator%A_DEN) ||
       rq[v*17+:17]!==17'(levels[v*17+:17]/R_DEN) || rr[v*CW+:CW]!==CW'(levels[v*17+:17]%R_DEN))
     $fatal(1,"arithmetic mismatch seed=%0d",seeds[v*17+:17]);
   end
  end
  $display("PASS tb_precalc_bank_arithmetic checks=%0d",checks);$finish;
 end
endmodule
