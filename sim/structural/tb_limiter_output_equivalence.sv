`timescale 1ns/1ps
module tb_limiter_output_equivalence;
 parameter integer CEILING=29204;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg signed [41:0] injected=0;
 wire ready_a,ready_b,valid_a,valid_b,clip_a,clip_b;
 wire signed [15:0] sample_a,sample_b;
 wire [16:0] gain_a,gain_b,tag_a,tag_b;
 audio_limiter #(.CEILING(CEILING)) dut(clk,rst,1'b0,16'sd0,ready_a,valid_a,sample_a,gain_a,clip_a,17'd0,tag_a);
 reference_audio_limiter_c6352fa #(.CEILING(CEILING)) ref_dut(clk,rst,1'b0,16'sd0,ready_b,valid_b,sample_b,gain_b,clip_b,17'd0,tag_b);
 integer checks=0,seed=32'h2380fabe;
 task probe(input reg signed [41:0] value);
 begin
  @(negedge clk);injected=value;
  @(posedge clk);#0.001;checks++;
  if({sample_a,clip_a,valid_a}!=={sample_b,clip_b,valid_b})
   $fatal(1,"output mismatch C=%0d product=%0d new=%0d/%b old=%0d/%b",CEILING,value,sample_a,clip_a,sample_b,clip_b);
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  force dut.state=4'd8;force ref_dut.state=4'd8;
  force dut.product=injected;force ref_dut.product=injected;
  // Every fractional value at zero, clipping boundaries, signed extremes,
  // and the original 42-bit minimum-negative wrap corner.
  for(integer mode=0;mode<12;mode++)begin
   for(integer frac=0;frac<65536;frac++)begin
    case(mode)
     0:probe(42'(frac));1:probe(-42'(frac));
     2:probe((42'(CEILING)<<16)+frac);3:probe(-((42'(CEILING)<<16)+frac));
     4:probe((42'(CEILING+1)<<16)+frac);5:probe(-((42'(CEILING+1)<<16)+frac));
     6:probe((42'(CEILING-1)<<16)+frac);7:probe(-((42'(CEILING-1)<<16)+frac));
     8:probe(42'sh1ffffff0000+frac);9:probe(-42'sh20000000000+frac);
     10:probe(42'sh0007fff0000+frac);11:probe(-42'sh00080000000+frac);
    endcase
   end
  end
  for(integer n=0;n<200000;n++)probe({10'($random(seed)),$random(seed)});
  $display("PASS tb_limiter_output_equivalence C=%0d checks=%0d",CEILING,checks);$finish;
 end
endmodule
