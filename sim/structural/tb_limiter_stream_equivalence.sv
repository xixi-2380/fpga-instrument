`timescale 1ns/1ps
module tb_limiter_stream_equivalence;
 parameter integer FIXED=1,HOLD=48,PRE_GAIN=24,WINDOW_LOG2=6;
 reg clk=0,rst=1,valid=0;always #5 clk=~clk;
 reg signed [15:0] sample=0;reg [16:0] tag=0;
 wire ra,rb,va,vb,ca,cb;wire signed [15:0] sa,sb;wire [16:0] ga,gb,ta,tb;
 audio_limiter #(.FIXED_LATENCY(FIXED),.HOLD_SAMPLES(HOLD),.PRE_GAIN(PRE_GAIN),.WINDOW_LOG2(WINDOW_LOG2)) dut(clk,rst,valid,sample,ra,va,sa,ga,ca,tag,ta);
 reference_audio_limiter_c6352fa #(.FIXED_LATENCY(FIXED),.HOLD_SAMPLES(HOLD),.PRE_GAIN(PRE_GAIN),.WINDOW_LOG2(WINDOW_LOG2)) ref_dut(clk,rst,valid,sample,rb,vb,sb,gb,cb,tag,tb);
 integer checks=0,outputs=0,offered=0,seed=32'hf00d2380,cycle=0;
 always @(posedge clk or posedge rst)begin
  #0.001;checks++;
  if({ra,va,ca,sa,ga,ta}!=={rb,vb,cb,sb,gb,tb})$fatal(1,"stream mismatch cycle=%0d offered=%0d",cycle,offered);
  if(!rst && va)outputs++;
 end
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(cycle=0;cycle<180000;cycle++)begin
   @(negedge clk);valid=ra && ($unsigned($random(seed))%4!=0);tag=$random(seed);
   if(valid)begin
    offered++;
    case(offered%13)
     0:sample=-32768;1:sample=32767;2:sample=0;3:sample=1;4:sample=-1;default:sample=$random(seed);
    endcase
    if(offered%1200>=600)sample=0;
   end
   if(cycle%7001==91)begin rst=1;valid=0;end
   else if(cycle%7001==93)rst=0;
  end
  valid=0;repeat(200)@(negedge clk);
  if(outputs<100)$fatal(1,"insufficient outputs");
  $display("PASS tb_limiter_stream_equivalence checks=%0d outputs=%0d offered=%0d",checks,outputs,offered);$finish;
 end
endmodule
