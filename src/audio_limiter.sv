`timescale 1ns/1ps
// Lookahead limiter: peak window -> conservative Q16 gain -> release -> box
// smoothing. Both windows contain W samples; audio delay is exactly W-1.
// For delayed x[n-W+1], every gain in the averaging window is <= its bound.
// Registered magnitude before peak comparison; a drain cycle preserves all W samples.
// A release hold delays recovery only; attack remains immediate. Audio delay is unchanged.
module audio_limiter #(
 parameter integer WINDOW_LOG2=6,PRE_GAIN=24,CEILING=29204,RELEASE_SHIFT=12,FIXED_LATENCY=0,HOLD_SAMPLES=0,
 parameter integer W=(1<<WINDOW_LOG2))(
 input wire clk,rst,in_valid,input wire signed [15:0] in_sample,
 output wire in_ready,output reg out_valid,output reg signed [15:0] out_sample,
 output reg [16:0] applied_gain,output reg clipped,
 input wire [16:0] in_tag,output reg [16:0] out_tag);
 localparam [3:0] IDLE=0,WAIT_RAM=1,SCAN=2,DIV_INIT=3,DIVIDE=4,
  RELEASE_GAIN=5,AVERAGE=6,MULTIPLY=7,EMIT=8,GAIN_READY=9,SCAN_DRAIN=10,SUM_ADD=11;
 reg [3:0] state;
 reg [40:0] audio_ram[0:W-1];reg [16:0] gain_ram[0:W-1];
 reg [40:0] audio_word;wire signed [23:0] audio_q=audio_word[23:0];
 reg signed [23:0] delayed;reg [16:0] delayed_tag;
 reg [16:0] gain_q,released,new_gain,target;
 reg [RELEASE_SHIFT-1:0] release_error;
 reg [WINDOW_LOG2-1:0] pointer,read_address,scan_address;
 reg [WINDOW_LOG2:0] filled,scan_count;
 reg [WINDOW_LOG2+17:0] gain_sum,updated_sum,added_sum;
 reg [23:0] peak,magnitude_q;reg magnitude_valid;
 localparam integer HW=HOLD_SAMPLES>0?$clog2(HOLD_SAMPLES+1):1;
 reg [HW-1:0] hold_count;
 reg [30:0] numerator;reg [24:0] remainder;
 reg [16:0] quotient;reg [5:0] bits_left;
 reg signed [41:0] product;
 wire signed [23:0] input_extended={{8{in_sample[15]}},in_sample};
 wire signed [23:0] amplified=input_extended*PRE_GAIN;
 // Reuse WAIT_RAM to separate pre-gain from absolute value. No state
 // or RAM access is added: peak is ready before the first SCAN comparison.
 reg signed [23:0] accepted_amplified;
 wire [23:0] input_mag=accepted_amplified[23] ? -accepted_amplified : accepted_amplified;
 wire [23:0] read_mag=audio_q[23] ? -audio_q : audio_q;
 wire read_initialized=filled==W || scan_address<filled;
 wire [24:0] trial={remainder[23:0],numerator[30]};
 // released remains in 0..65536 and release_error < 2**RELEASE_SHIFT.
 // RELEASE_SHIFT<=15 therefore bounds this nonnegative sum below 98304.
 // Seventeen bits preserve every reachable value; wider arithmetic only
 // extends the release subtract/add/compare path.
 wire [16:0] recovery_total=(17'd65536-released)+release_error;
 wire [16:0] release_step=recovery_total>>RELEASE_SHIFT;
 wire [17:0] release_candidate={1'b0,released}+release_step;
 wire [16:0] next_release=target<release_candidate ? target : release_candidate[16:0];
 wire [16:0] old_gain=filled<W ? 17'd65536 : gain_q;
 wire [WINDOW_LOG2+17:0] next_sum=added_sum-old_gain;
 wire [16:0] average_gain=updated_sum>>WINDOW_LOG2;
 // Split absolute value at the binary point: carry into the integer limb
 // occurs exactly when the fractional limb is zero. This is bit-identical
 // to abs42[40:16], including the original minimum-negative wrap behavior.
 // Compare the magnitude once, then restore the sign only on the 16-bit result.
 wire [24:0] magnitude_integer=product[41] ?
     (~product[40:16] + {24'd0,(product[15:0]==16'd0)}) : product[40:16];
 wire magnitude_over_ceiling=magnitude_integer>25'(CEILING);
 wire signed [15:0] emitted_magnitude=magnitude_over_ceiling ? 16'(CEILING) : magnitude_integer[15:0];
 wire signed [15:0] emitted_sample=product[41] ? -emitted_magnitude : emitted_magnitude;
 assign in_ready=!rst && state==IDLE;
 // Normal-mode RAM: read and write are mutually exclusive. The old gain
 // is fetched BEFORE AVERAGE; writing that address must not request Gowin's
 // unsupported SPX9 read-before-write mode (WRITE_MODE=2'b10).
 always @(posedge clk)begin
  if(!rst && in_valid && in_ready)
   audio_ram[pointer]<={(in_tag[16]===1'b1 ? in_tag : 17'd0),amplified};
  else audio_word<=audio_ram[read_address];
  if(!rst && state==AVERAGE)gain_ram[pointer]<=new_gain;
  else gain_q<=gain_ram[pointer];
 end
 task update_release;
 begin
  if(HOLD_SAMPLES>0 && target<=released)begin
   released<=target;new_gain<=target;release_error<=0;hold_count<=HOLD_SAMPLES;
  end else if(HOLD_SAMPLES>0 && hold_count!=0)begin
   new_gain<=released;hold_count<=hold_count-1'b1;
  end else begin
   released<=next_release;new_gain<=next_release;hold_count<=0;
   release_error<=target<release_candidate ? 0 : recovery_total[RELEASE_SHIFT-1:0];
  end
 end
 endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;pointer<=0;read_address<=0;scan_address<=0;filled<=0;scan_count<=0;
   accepted_amplified<=0;peak<=0;magnitude_q<=0;magnitude_valid<=0;hold_count<=0;added_sum<=0;delayed<=0;released<=65536;new_gain<=65536;target<=65536;
   gain_sum<=W*65536;updated_sum<=W*65536;numerator<=0;remainder<=0;quotient<=0;bits_left<=0;
   product<=0;out_valid<=0;out_sample<=0;applied_gain<=65536;clipped<=0;release_error<=0;delayed_tag<=0;out_tag<=0;
  end else begin
   out_valid<=0;clipped<=0;
   case(state)
    IDLE:if(in_valid)begin
     accepted_amplified<=amplified;read_address<=pointer+1'b1;scan_address<=pointer+1'b1;
     scan_count<=0;magnitude_valid<=0;state<=WAIT_RAM;
    end
    WAIT_RAM:begin peak<=input_mag;read_address<=read_address+1'b1;state<=SCAN;end
    SCAN:begin
     if(scan_count==0)begin
      delayed<=filled>=W-1 ? audio_q : 24'sd0;
      delayed_tag<=filled>=W-1 ? audio_word[40:24] : 17'd0;
     end
     magnitude_q<=read_mag;magnitude_valid<=read_initialized;
     if(magnitude_valid && magnitude_q>peak)peak<=magnitude_q;
     scan_address<=scan_address+1'b1;read_address<=read_address+1'b1;
     if(scan_count==W-2)state<=SCAN_DRAIN;else scan_count<=scan_count+1'b1;
    end
    SCAN_DRAIN:begin
     if(magnitude_valid && magnitude_q>peak)peak<=magnitude_q;
     magnitude_valid<=0;state<=DIV_INIT;
    end
    // Stereo lanes must emit together even when only one exceeds the ceiling.
    // The optional fixed path spends the same divider cycles below ceiling;
    // its quotient is ignored and the unity target is retained in that case.
    DIV_INIT:if(peak<=CEILING && !FIXED_LATENCY)begin target<=65536;state<=RELEASE_GAIN;end
     else begin
      if(peak<=CEILING)target<=65536;
      numerator<=CEILING*65536;remainder<=0;quotient<=0;bits_left<=31;state<=DIVIDE;
     end
    DIVIDE:begin
     numerator<=numerator<<1;bits_left<=bits_left-1'b1;
     if(trial>={1'b0,peak})begin remainder<=trial-{1'b0,peak};quotient<={quotient[15:0],1'b1};end
     else begin remainder<=trial;quotient<={quotient[15:0],1'b0};end
     if(bits_left==1)state<=RELEASE_GAIN;
     // target captures the final quotient on the next state, not a stale bit.
    end
    RELEASE_GAIN:begin
     if(peak>CEILING || FIXED_LATENCY)begin
      if(peak>CEILING)target<=quotient;
      state<=GAIN_READY;
     end
     else begin
      update_release();state<=SUM_ADD;
     end
    end
    GAIN_READY:begin
     update_release();state<=SUM_ADD;
    end
    SUM_ADD:begin added_sum<=gain_sum+new_gain;state<=AVERAGE;end
    AVERAGE:begin updated_sum<=next_sum;gain_sum<=next_sum;state<=MULTIPLY;end
    MULTIPLY:begin product<=delayed*$signed({1'b0,average_gain});applied_gain<=average_gain;state<=EMIT;end
    EMIT:begin
     out_valid<=1;out_tag<=delayed_tag;
     out_sample<=emitted_sample;
     clipped<=magnitude_over_ceiling;
     pointer<=pointer+1'b1;if(filled<W)filled<=filled+1'b1;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
 // synthesis translate_off
 initial if(WINDOW_LOG2<2 || WINDOW_LOG2>6 || PRE_GAIN<1 || PRE_GAIN>32 || CEILING<1 || CEILING>32767 || RELEASE_SHIFT<1 || RELEASE_SHIFT>15 || HOLD_SAMPLES<0 || HOLD_SAMPLES>48000)
  $fatal(1,"Invalid limiter parameters");
 always @(posedge clk)if(!rst && released>17'd65536)$fatal(1,"Limiter release invariant exceeded unity");
 always @(posedge clk)if(!rst && in_valid && !in_ready)$fatal(1,"Limiter input exceeded bounded processing budget");
 // synthesis translate_on
endmodule
