`timescale 1ns/1ps
// Passive accepted-event ownership view; never adds backpressure or edits IDs.
// An ID is a live-note handle, including independent notes at the same pitch.
module bt_identity_monitor(
 input wire clk,rst,event_valid,event_ready,input wire [1:0] event_kind,
 input wire [6:0] event_id,output reg [15:0] held_ids);
 always @(posedge clk or posedge rst)begin
  if(rst)held_ids<=0;
  else if(event_valid && event_ready)begin
   if(event_kind==2)held_ids<=0;
   else if(event_kind<2)begin
    for(integer i=0;i<16;i=i+1)if(event_id==i)held_ids[i]<=event_kind==1;
   end
  end
 end
endmodule
