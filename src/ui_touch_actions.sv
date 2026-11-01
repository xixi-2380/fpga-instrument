`timescale 1ns/1ps
// Atomic touch reports; one command per release/rearmed contact. No stale drag.
module ui_touch_actions(
 input wire clk,rst,enabled,snapshot_valid,ready,error,down,
 input wire [3:0] count,input wire [15:0] x,y,resolution_x,resolution_y,
 input wire [1:0] effect_mode,input wire menu_mode,
 output reg action_valid,output reg [6:0] action,
 input wire more_mode,ultrasonic_page,harp_active,sensitivity_open);
 `include "config/ui_layout.svh"
 reg armed;
 wire [6:0] hit=sensitivity_open===1'b1 ? sensitivity_hit(integer'(x),integer'(y)) :
  more_mode===1'b1 ? more_hit(integer'(x),integer'(y)) :
  (menu_mode && ultrasonic_page===1'b1) ? ultrasonic_hit(integer'(x),integer'(y)) :
  harp_active===1'b1 ? harp_hit(integer'(x),integer'(y)) : ui_hit(integer'(x),integer'(y),effect_mode,menu_mode);
 always @(posedge clk or posedge rst)begin
  if(rst)begin armed<=0;action_valid<=0;action<=UI_NONE;end
  else begin
   action_valid<=0;
   if(!enabled || !snapshot_valid || !ready || error || resolution_x!=800 || resolution_y!=480)armed<=0;
   else if(!down)armed<=1;
   else begin
    armed<=0;
    if(armed && count==1 && x<800 && y<480 && hit!=UI_NONE)begin action_valid<=1;action<=hit;end
   end
  end
 end
endmodule
