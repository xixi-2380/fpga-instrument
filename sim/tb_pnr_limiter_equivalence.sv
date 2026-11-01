`timescale 1ns/1ps
module tb_pnr_limiter_equivalence;
 parameter integer FIXED=1,HOLD=240;
 reg clk=0,rst=1,valid=0;always #5 clk=~clk;
 reg signed [15:0] sample=0;reg [16:0] tag=0;
 wire ready_a,ready_b,ov_a,ov_b,clip_a,clip_b;
 wire signed [15:0] out_a,out_b;wire [16:0] gain_a,gain_b,tag_a,tag_b;
 integer checks=0,outputs=0,cycles=0;reg [31:0] random_state=32'h13579bdf;
 audio_limiter #(.FIXED_LATENCY(FIXED),.HOLD_SAMPLES(HOLD)) a(
 .clk(clk),.rst(rst),.in_valid(valid),.in_sample(sample),.in_ready(ready_a),
 .out_valid(ov_a),.out_sample(out_a),.applied_gain(gain_a),.clipped(clip_a),.in_tag(tag),.out_tag(tag_a));
 reference_audio_limiter_c6352fa #(.FIXED_LATENCY(FIXED),.HOLD_SAMPLES(HOLD)) b(
 .clk(clk),.rst(rst),.in_valid(valid),.in_sample(sample),.in_ready(ready_b),
 .out_valid(ov_b),.out_sample(out_b),.applied_gain(gain_b),.clipped(clip_b),.in_tag(tag),.out_tag(tag_b));
 always @(posedge clk)begin
  #1;checks=checks+1;
  if({ready_a,ov_a,out_a,gain_a,clip_a,tag_a} !== {ready_b,ov_b,out_b,gain_b,clip_b,tag_b})
   $fatal(1,"limiter mismatch cycle=%0d",cycles);
  if(ov_a)outputs=outputs+1;
 end
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(integer i=0;i<320000;i=i+1)begin
   @(negedge clk);cycles=i;
   random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
   rst=(i==70001 || i==190021 || i==250031);
   valid=!rst && ready_a && random_state[0];
   case(i%13)
    0:sample=-32768;1:sample=32767;2:sample=-1;3:sample=1;4:sample=0;
    default:sample=random_state[15:0];
   endcase
   tag={1'b1,random_state[31:16]};
  end
  valid=0;repeat(150)@(negedge clk);
  if(outputs<2000)$fatal(1,"insufficient accepted audio samples");
  $display("PASS tb_pnr_limiter_equivalence checks=%0d outputs=%0d fixed=%0d hold=%0d",checks,outputs,FIXED,HOLD);$finish;
 end
endmodule
