`timescale 1ns/1ps
// Per-physical-voice release. No delayed PCM or shared note identity.
// phase_step/remainder describe exactly 2^24 / duration sample clocks.
module sustain_envelope_baseline(
 input wire clk,rst,sample_ce,note_on,note_off,enabled,
 input wire [16:0] base_level,input wire base_active,
 input wire [16:0] duration,phase_step,phase_remainder,
 input wire [8:0] strength,
 output wire [16:0] level,output wire active);
 reg owned,running;reg [8:0] held_age;reg [16:0] remaining,total,step_size,remainder,error;
 reg [24:0] phase;reg [16:0] peak,current;
 wire [17:0] error_sum={1'b0,error}+{1'b0,remainder};
 wire carry=error_sum>={1'b0,total};
 wire [17:0] phase_delta={1'b0,step_size}+carry;
 wire [33:0] product=peak*phase[24:8];
 wire [16:0] target=enabled ? product[32:16] : 17'd0;
 // One signed subtraction encodes both direction and distance.
 wire signed [17:0] slew_error=$signed({1'b0,target})-$signed({1'b0,current});
 // A very short tap must not disappear because it was released in Attack.
 // Approach this minimum smoothly; never jump the sample amplitude.
 wire [16:0] release_seed=base_level<16384 && held_age<480 ? 17'd16384 : base_level;
 wire [25:0] peak_product=release_seed*(strength>256?9'd256:strength);
 assign level=owned?current:base_level;
 assign active=owned?running:base_active;
 always @(posedge clk or posedge rst)begin
  if(rst)begin owned<=0;running<=0;held_age<=0;remaining<=0;total<=1;step_size<=0;remainder<=0;error<=0;phase<=0;peak<=0;current<=0;end
  else if(sample_ce)begin
   if(held_age<480)held_age<=held_age+1'b1;
   if(note_on)begin owned<=0;running<=0;current<=0;held_age<=0;end
   else if(note_off && enabled && strength!=0 && release_seed!=0)begin
    owned<=1;running<=1;remaining<=duration;total<=duration;
    phase<=25'd16777216;step_size<=phase_step;remainder<=phase_remainder;error<=0;
    peak<=peak_product[24:8];current<=base_level;
   end else if(owned && running)begin
    if(!enabled)begin
     if(current<=256)begin current<=0;running<=0;end else current<=current-17'd256;
    end else if(remaining<=1)begin current<=0;running<=0;remaining<=0;phase<=0;end
    else begin
     remaining<=remaining-1'b1;phase<=phase-phase_delta;
     error<=carry?error_sum-total:error_sum;
     if(slew_error>18'sd256)current<=current+17'd256;
     else if(slew_error < -18'sd256)current<=current-17'd256;
     else current<=target;
    end
   end
  end
 end
endmodule
