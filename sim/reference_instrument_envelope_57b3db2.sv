`timescale 1ns/1ps
`include "../src/config/synth_config.svh"
// Legacy envelopes remain exact for IDs0..2. New profiles use constant shifts
// and bounded linear release, never variable division or generated clocks.
module instrument_envelope_baseline #(
 parameter integer ATTACK=`ADSR_ATTACK_FRAMES,DECAY=`ADSR_DECAY_FRAMES,
 SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES,PRECALC=0)(
 input wire clk,rst,sample_ce,note_on,note_off,restart,input wire [4:0] timbre,
 output wire [16:0] level,output wire active);
 wire [16:0] legacy_level;wire legacy_active;
 reg [4:0] profile;reg [16:0] drum_age;
 function automatic [16:0] drum_frames(input [4:0] t);begin case(t)
 16:drum_frames=12000;17:drum_frames=8640;18:drum_frames=6720;19:drum_frames=3840;20:drum_frames=21600;21:drum_frames=16800;22:drum_frames=14400;23:drum_frames=12000;24:drum_frames=72000;default:drum_frames=48000;endcase end endfunction
 reg [1:0] state;
 reg [16:0] musical_level,release_step;
 wire new_profile=timbre>=3 && timbre<=25;
 wire [16:0] attack_step=(profile==3 || profile==9 || profile==10 || profile==14) ? 17'd32 : profile==4 ? 17'd1024 : profile==5 ? 17'd2048 : 17'd512;
 wire [16:0] decay_step=profile==4 ? (musical_level>>13) : (profile==5 || profile==8) ? (musical_level>>12) : (musical_level>>14);
 wire [16:0] cello_decay=(musical_level-17'd49152)>>11;
 wire [16:0] release_amount=profile==5 ? (musical_level>>9)+17'd1 : profile==4 ? (musical_level>>10)+17'd1 : (musical_level>>11)+17'd1;
 assign level=profile==0 ? legacy_level : musical_level;
 assign active=profile==0 ? legacy_active : state!=0;
 adsr_envelope_baseline #(.ATTACK(ATTACK),.DECAY(DECAY),.SUSTAIN(SUSTAIN),.RELEASE(RELEASE),.PRECALC(PRECALC)) legacy(
  .clk(clk),.rst(rst),.sample_ce(sample_ce),.note_on(note_on && !new_profile),
  .note_off(note_off && profile==0),.restart(restart && !new_profile),
  .level(legacy_level),.active(legacy_active),.seed_valid(profile!=0),.seed_level(musical_level));
 always @(posedge clk or posedge rst)begin
  if(rst)begin profile<=0;drum_age<=0;state<=0;musical_level<=0;release_step<=1;end
  else if(sample_ce)begin
   if(note_on && (!note_off || restart))begin
    if(new_profile)begin
     profile<=timbre;state<=1;drum_age<=0;
     // New ownership starts at zero; retrigger continues its present level.
     if(timbre>=16)begin musical_level<=65536;state<=2;end
     else if(restart)musical_level<=0;
     else if(profile==0)musical_level<=legacy_level;
    end else begin profile<=0;state<=0;musical_level<=0;end
   end else if(note_off && profile!=0 && profile<16)begin
    if(musical_level==0)state<=0;
    else begin state<=3;release_step<=release_amount;end
   end else if(profile!=0)begin
    case(state)
     1:if(musical_level>=17'd65536-attack_step)begin musical_level<=65536;state<=2;end
       else musical_level<=musical_level+attack_step;
     2:if(profile>=16)begin
        drum_age<=drum_age+1'b1;if(drum_age>=drum_frames(profile)-1)begin musical_level<=0;state<=0;end
        else if(musical_level>1)musical_level<=musical_level-((musical_level>>(profile==19?10:profile==24?14:12))==0?1:(musical_level>>(profile==19?10:profile==24?14:12)));
       end else if(profile==3 || profile==7 || (profile>=9 && profile<=15))begin
        if(musical_level>49152)musical_level<=musical_level-(cello_decay==0 ? 17'd1 : cello_decay);
       end else if(musical_level<=1)begin musical_level<=0;state<=0;end
       else musical_level<=musical_level-(decay_step==0 ? 17'd1 : decay_step);
     3:if(musical_level<=release_step)begin musical_level<=0;state<=0;end
       else musical_level<=musical_level-release_step;
     default:musical_level<=0;
    endcase
   end
  end
 end
endmodule
