`timescale 1ns/1ps
// Final PCM conditioning at 48kHz: DC rejection (~1.87Hz), then a gentle
// low-pass (~15.74kHz). Coefficients are shifts/adds; no multiplier is needed.
// Input at edge N produces output at edge N+4. Histories advance only for
// accepted samples; tags follow exactly the same five-register pipeline.
module audio_output_filter #(parameter integer TAG_W=17)(
 input wire clk,rst,in_valid,input wire signed [15:0] in_sample,
 input wire [TAG_W-1:0] in_tag,input wire silence,
 output reg out_valid,output reg signed [15:0] out_sample,
 output reg [TAG_W-1:0] out_tag);
 localparam integer FRACTION=16;
 reg signed [31:0] dc_estimate;
 reg signed [32:0] ac_s0,previous_ac;
 reg signed [33:0] sum_s1;
 reg signed [36:0] weighted_s2;
 reg signed [33:0] lowpass_state;
 reg valid_s0,valid_s1,valid_s2,valid_s3;
 reg silence_s0,silence_s1,silence_s2,silence_s3;
 reg [TAG_W-1:0] tag_s0,tag_s1,tag_s2,tag_s3;

 // Truncation toward zero avoids a sign-dependent DC-estimator bias. A
 // stopped update is less than 4096 Q16 units (1/16 PCM LSB), which rounds
 // to digital zero at the output rather than creating a quantized tone.
 function automatic signed [32:0] trunc33(input signed [32:0] value,input integer bits);
  begin trunc33=value<0 ? -((-value)>>>bits) : value>>>bits;end
 endfunction
 function automatic signed [36:0] trunc37(input signed [36:0] value,input integer bits);
  begin trunc37=value<0 ? -((-value)>>>bits) : value>>>bits;end
 endfunction
 wire signed [32:0] input_q={in_sample[15],in_sample,16'd0};
 wire signed [32:0] dc_error=input_q-$signed({dc_estimate[31],dc_estimate});
 wire signed [32:0] next_estimate=$signed({dc_estimate[31],dc_estimate})+trunc33(dc_error,12);
 // Normalize the DC blocker to unity gain at Nyquist: alpha=8191/8192.
 wire signed [32:0] next_ac=dc_error-trunc33(dc_error,13);
 wire signed [33:0] ac_sum=$signed({ac_s0[32],ac_s0})+$signed({previous_ac[32],previous_ac});
 wire signed [36:0] extended_sum={{3{sum_s1[33]}},sum_s1};
 wire signed [36:0] extended_lowpass={{3{lowpass_state[33]}},lowpass_state};
 // y[n] = 5/8*(x[n]+x[n-1]) - 1/4*y[n-1]. Pole=-1/4, DC gain=1.
 wire signed [36:0] lowpass_numerator=weighted_s2-(extended_lowpass<<<1);
 wire signed [36:0] next_lowpass=trunc37(lowpass_numerator,3);
 wire signed [34:0] lowpass_extended={lowpass_state[33],lowpass_state};
 // Round symmetrically to nearest (ties away from zero), then saturate.
 wire signed [34:0] rounded=lowpass_state<0 ?
  -(((-lowpass_extended)+35'sd32768)>>>FRACTION) :
   ((lowpass_extended+35'sd32768)>>>FRACTION);
 wire signed [15:0] clipped=rounded>35'sd32767 ? 16'sh7fff :
  rounded < -35'sd32768 ? 16'sh8000 : rounded[15:0];

 always @(posedge clk or posedge rst)begin
  if(rst)begin
   dc_estimate<=0;ac_s0<=0;previous_ac<=0;sum_s1<=0;
   weighted_s2<=0;lowpass_state<=0;
   valid_s0<=0;valid_s1<=0;valid_s2<=0;valid_s3<=0;out_valid<=0;
   silence_s0<=0;silence_s1<=0;silence_s2<=0;silence_s3<=0;
   tag_s0<=0;tag_s1<=0;tag_s2<=0;tag_s3<=0;out_tag<=0;out_sample<=0;
  end else begin
   valid_s0<=in_valid;valid_s1<=valid_s0;valid_s2<=valid_s1;
   valid_s3<=valid_s2;out_valid<=valid_s3;
   // Explicit user mute clears histories in sample order; unlike rst it
   // preserves every valid/tag transaction and therefore cannot starve I2S.
   if(in_valid)begin
    if(silence)begin dc_estimate<=0;ac_s0<=0;end
    else begin dc_estimate<=next_estimate[31:0];ac_s0<=next_ac;end
    tag_s0<=in_tag;silence_s0<=silence;
   end
   if(valid_s0)begin
    sum_s1<=silence_s0?34'sd0:ac_sum;previous_ac<=silence_s0?33'sd0:ac_s0;
    tag_s1<=tag_s0;silence_s1<=silence_s0;
   end
   if(valid_s1)begin weighted_s2<=(extended_sum<<<2)+extended_sum;tag_s2<=tag_s1;silence_s2<=silence_s1;end
   if(valid_s2)begin lowpass_state<=silence_s2?34'sd0:next_lowpass[33:0];tag_s3<=tag_s2;silence_s3<=silence_s2;end
   if(valid_s3)begin out_sample<=clipped;out_tag<=tag_s3;end
  end
 end
 // synthesis translate_off
 initial if(TAG_W<1)$fatal(1,"audio_output_filter TAG_W must be positive");
 always @(posedge clk)if(!rst)begin
  if(in_valid && !silence && next_estimate!==$signed({next_estimate[31],next_estimate[31:0]}))
   $fatal(1,"DC estimator exceeded its signed Q16 state");
  if(valid_s2 && !silence_s2 && next_lowpass!==$signed({{3{next_lowpass[33]}},next_lowpass[33:0]}))
   $fatal(1,"Output low-pass exceeded its guarded Q16 state");
  if(valid_s3 && silence_s3 && clipped!==16'sd0)$fatal(1,"Explicit silence did not produce digital0");
 end
 // synthesis translate_on
endmodule
