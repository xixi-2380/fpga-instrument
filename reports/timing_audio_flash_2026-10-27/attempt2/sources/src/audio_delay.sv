`timescale 1ns/1ps
// Feed-forward echo with a runtime tap. Two taps crossfade over 256 samples;
// new requests coalesce until that fade finishes. RAM reads/writes are exclusive.
module audio_delay #(parameter integer DELAY_SAMPLES=7200,MAX_SAMPLES=DELAY_SAMPLES)(
 input wire clk,rst,enable,in_valid,input wire signed [15:0] in_sample,
 output wire in_ready,output reg out_valid,output reg signed [15:0] out_sample,
 output reg signed [15:0] out_history,input wire [14:0] delay_samples);
 localparam integer AW=MAX_SAMPLES>1?$clog2(MAX_SAMPLES):1,FW=$clog2(MAX_SAMPLES+1);
 reg signed [15:0] memory[0:MAX_SAMPLES-1];
 reg [AW-1:0] pointer,read_b;
 reg [FW-1:0] filled;
 reg [14:0] current_length,next_length;
 reg [8:0] tap_fade,used_cross;
 reg cross_busy,valid_a,valid_b;
 reg [1:0] stage;
 reg signed [15:0] dry,old_raw,read_value,history;
 reg [6:0] wet_level,used_level;
 wire [14:0] requested=(^delay_samples===1'bx) ? 15'(DELAY_SAMPLES) :
  delay_samples<1 ? 15'd1 : delay_samples>MAX_SAMPLES ? 15'(MAX_SAMPLES) : delay_samples;
 function automatic [AW-1:0] address(input [AW-1:0] write_pointer,input [14:0] delay_length);
  reg [15:0] sum;
  begin sum={1'b0,write_pointer}+16'(MAX_SAMPLES)-{1'b0,delay_length};
   address=sum>=MAX_SAMPLES ? sum-16'(MAX_SAMPLES) : sum;
  end
 endfunction
 assign in_ready=!rst && stage==0;
 wire accept=in_valid && in_ready;
 wire signed [16:0] a_value=valid_a ? {old_raw[15],old_raw} : 17'sd0;
 wire signed [16:0] b_value=valid_b ? {read_value[15],read_value} : 17'sd0;
 wire signed [17:0] difference=$signed({b_value[16],b_value})-$signed({a_value[16],a_value});
 wire signed [27:0] tap_blend=($signed(a_value)<<<8)+difference*$signed({1'b0,used_cross});
 wire signed [31:0] blend=($signed(dry)*32'sd256)+($signed(history)-$signed(dry))*$signed({1'b0,used_level});
 // One synchronous RAM port, no read-during-write/old-data mode requirement.
 wire [AW-1:0] read_address=accept ? address(pointer,current_length) : read_b;
 always @(posedge clk)if(!rst)begin
  if(accept || stage==1)read_value<=memory[read_address];
  else if(stage==3)memory[pointer]<=dry;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   pointer<=0;filled<=0;stage<=0;current_length<=DELAY_SAMPLES;next_length<=DELAY_SAMPLES;
   tap_fade<=0;used_cross<=0;cross_busy<=0;valid_a<=0;valid_b<=0;read_b<=0;
   dry<=0;history<=0;wet_level<=0;used_level<=0;out_valid<=0;out_sample<=0;out_history<=0;
  end else begin
   out_valid<=0;
   if(accept)begin
    dry<=in_sample;valid_a<=filled>=current_length;valid_b<=filled>=next_length;
    read_b<=address(pointer,next_length);used_cross<=cross_busy ? tap_fade : 9'd0;
    used_level<=wet_level;stage<=1;
    if(enable===1'b1)begin if(wet_level<64)wet_level<=wet_level+1'b1;end
    else if(wet_level!=0)wet_level<=wet_level-1'b1;
    if(!cross_busy && requested!=current_length)begin next_length<=requested;tap_fade<=1;cross_busy<=1;end
    else if(cross_busy)begin
     if(tap_fade==255)begin current_length<=next_length;cross_busy<=0;tap_fade<=0;end
     else tap_fade<=tap_fade+1'b1;
    end
   end else if(stage==1)begin old_raw<=read_value;stage<=2;end
   else if(stage==2)begin history<=tap_blend>>>8;stage<=3;end
   else if(stage==3)begin
    out_sample<=blend>>>8;out_history<=history;out_valid<=1;stage<=0;
    if(pointer==MAX_SAMPLES-1)pointer<=0;else pointer<=pointer+1'b1;
    if(filled<MAX_SAMPLES)filled<=filled+1'b1;
   end
  end
 end
 // synthesis translate_off
 initial if(DELAY_SAMPLES<1 || MAX_SAMPLES<DELAY_SAMPLES || MAX_SAMPLES>32767)$fatal(1,"invalid delay capacity");
 // synthesis translate_on
endmodule
