
`timescale 1ns/1ps
module timing_case #(parameter H=20)(output reg done=0,output integer checks=0);
 reg clk=0,rst=1;always #5 clk=~clk;
 wire ab,ar,af,at,eb,er,ef,et,pre;wire [4:0] ai,ei;reg replica;
 audio_timing #(.HALF_CYCLES(H)) actual(clk,rst,ab,ar,af,at,ai,pre);
 always @(posedge clk or posedge rst)if(rst)replica<=H==1;else replica<=pre;
 baseline_audio_timing #(.HALF_CYCLES(H)) baseline(clk,rst,eb,er,ef,et,ei);
 always @(clk)begin #1;if({ab,ar,af,at,ai}!=={eb,er,ef,et,ei} || (H==1?(!rst && replica):replica)!==at)$fatal(1,"phase/replica differs H=%0d",H);checks=checks+1;end
 initial begin #12;rst=0;#7491;rst=1;#1;
  if({ab,ar,af,at,ai}!=={eb,er,ef,et,ei})$fatal(1,"async reset phase H=%0d",H);
  #18;rst=0;repeat(500000)@(negedge clk);done=1;
 end
endmodule
module tb_phase;
 wire [4:0] done;wire [31:0] count[0:4];
 for(genvar n=0;n<5;n=n+1)begin:c
  localparam H=n==0?1:n==1?2:n==2?4:n==3?20:31;
  timing_case #(.H(H)) dut(done[n],count[n]);
 end
 initial begin wait(&done);#2;$display("PASS audio timing phase checks=%0d HALF=1,2,4,20,31",count[0]+count[1]+count[2]+count[3]+count[4]);$finish;end
endmodule
