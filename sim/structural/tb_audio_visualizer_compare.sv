`timescale 1ns/1ps
`include "check.svh"
module tb_audio_visualizer_compare;
 reg clk=0,rst=1,valid=0;reg signed [15:0] sample=0;
 wire [1023:0] wave;wire [7:0] peak;wire pulse;
 integer checks=0,index=0,pubs=0,expected_peak=0,mag,val,scaled;
 reg [1023:0] reference=0,previous=0;
 always #5 clk=~clk;
 audio_visualizer dut(clk,rst,valid,sample,wave,peak,pulse);
 wire [1023:0] reference_wave;wire [7:0] reference_peak;wire reference_pulse;
 reference_audio_visualizer_94030a ref_dut(clk,rst,valid,sample,reference_wave,reference_peak,reference_pulse);
 always @(posedge clk)begin #1.001;
  `CHECK(wave===reference_wave && peak===reference_peak && pulse===reference_pulse,"candidate and frozen original outputs match every cycle")
 end
 initial begin
  #12 rst=0;
  // Abort three partial windows at different acquisition positions.
  for(integer abort_case=0;abort_case<3;abort_case=abort_case+1)begin
   repeat(53+abort_case*137)begin
    @(negedge clk);valid=1;sample=$random;
    @(negedge clk);valid=0;
    repeat(abort_case+1)@(negedge clk);
   end
   #2;rst=1;#1;
   `CHECK(wave==0 && peak==0 && !pulse,"mid-window reset clears both window copies")
   repeat(3)@(negedge clk);rst=0;
  end
  for(integer window=0;window<20;window=window+1)begin
   expected_peak=0;
   for(integer n=0;n<512;n=n+1)begin
    @(negedge clk);valid=1;
    case(window)
     0:sample=0;
     1:sample=(n-256)*32;
     2:sample=n==7 ? -32768 : 100;
     default:sample=$random;
    endcase
    val=$signed(sample);mag=val<0 ? -val : val;
    if(mag/128>expected_peak)expected_peak=mag/128>255 ? 255 : mag/128;
    if(n%4==3)begin
     scaled=val>>>8;
     reference[(n/4)*8+:8]=scaled;
    end
    @(posedge clk);#1;
    if(n==511)begin
     `CHECK(pulse && wave===reference && peak==expected_peak,"complete real PCM window and all-sample peak are atomic")
     previous=wave;pubs=pubs+1;
    end else `CHECK(!pulse && wave===previous,"partial windows never leak")
    @(negedge clk);valid=0;
    repeat(n%3+1)begin @(posedge clk);#1;`CHECK(!pulse && wave===previous,"sample-valid gaps cannot advance visual acquisition") end
   end
  end
  @(negedge clk);rst=1;#1;`CHECK(wave==0 && peak==0 && !pulse,"reset clears held display window")
  $display("PASS tb_audio_visualizer_compare checks=%0d windows=%0d",checks,pubs);$finish;
 end
endmodule
