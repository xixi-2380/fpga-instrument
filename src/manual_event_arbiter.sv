`timescale 1ns/1ps
// Lock a complete source through allocator search/backpressure. Round-robin
// between physical keys and touch plucks; no note payload may change mid-offer.
module manual_event_arbiter(
 input wire clk,rst,a_valid,a_on,b_valid,b_on,input wire [6:0] a_id,b_id,
 input wire [31:0] a_fcw,b_fcw,input wire [4:0] a_timbre,b_timbre,
 input wire [6:0] b_pitch,b_velocity,input wire ready,
 output wire a_ready,b_ready,valid,on,output wire [6:0] id,pitch,velocity,
 output wire [31:0] fcw,output wire [4:0] timbre,output wire expressive);
 reg locked,owner,prefer_b;
 wire choose_b=locked?owner:(b_valid && (!a_valid || prefer_b));
 assign valid=choose_b?b_valid:a_valid;
 assign on=choose_b?b_on:a_on;assign id=choose_b?b_id:a_id;
 assign fcw=choose_b?b_fcw:a_fcw;assign timbre=choose_b?b_timbre:a_timbre;
 assign pitch=choose_b?b_pitch:a_id;assign velocity=choose_b?b_velocity:7'd127;
 assign expressive=choose_b;
 assign a_ready=ready && !choose_b;assign b_ready=ready && choose_b;
 always @(posedge clk or posedge rst)
  if(rst)begin locked<=0;owner<=0;prefer_b<=0;end
  else if(valid)begin
   if(ready)begin locked<=0;prefer_b<=!choose_b;end
   else begin locked<=1;owner<=choose_b;end
  end
endmodule
