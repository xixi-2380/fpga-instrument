`timescale 1ns/1ps
`include "config/synth_config.svh"
// Input is an already atomic audio-domain snapshot. One action per DOWN;
// no drag/repeat. First contact after reset/error/enable requires an UP first.
module ui_touch_actions #(parameter integer PCB_REPEAT_DELAY=(`AUDIO_HZ/2),PCB_REPEAT_PERIOD=(`AUDIO_HZ/10))(
 input wire clk,rst,enabled,snapshot_valid,ready,error,down,
 input wire [3:0] count,input wire [15:0] x,y,resolution_x,resolution_y,
 input wire [1:0] effect_mode,input wire menu_mode,output reg action_valid,output reg [5:0] action,input wire more_mode,ultrasonic_page,input wire pcb_page);
 `include "config/ui_layout.svh"
 reg armed,repeat_active;reg [5:0] repeat_action;
 localparam integer RCW=$clog2(PCB_REPEAT_DELAY+1);
 reg [RCW-1:0] repeat_count;
 wire calibrated=resolution_x==800 && resolution_y==480;
 wire valid_point=count==1 && x<800 && y<480;
 wire [5:0] hit=pcb_page===1'b1 ? pcb_hit(integer'(x),integer'(y)) : more_mode===1'b1 ? more_hit(integer'(x),integer'(y)) :
  (menu_mode && ultrasonic_page===1'b1) ? ultrasonic_hit(integer'(x),integer'(y)) :
  ui_hit(integer'(x),integer'(y),effect_mode,menu_mode);
 always @(posedge clk or posedge rst)begin
  if(rst)begin armed<=0;action_valid<=0;action<=UI_NONE;repeat_active<=0;repeat_action<=UI_NONE;repeat_count<=0;end
  else begin
   action_valid<=0;
   if(!enabled || !snapshot_valid || !ready || error || !calibrated)begin armed<=0;repeat_active<=0;end
   else if(!down)begin armed<=1;repeat_active<=0;end
   else begin
    armed<=0;
    if(armed && valid_point && hit!=UI_NONE)begin
     action_valid<=1;action<=hit;
     repeat_active<=pcb_page && (hit==UI_PCB_MINUS || hit==UI_PCB_PLUS);
     repeat_action<=hit;repeat_count<=PCB_REPEAT_DELAY-1;
    end else if(repeat_active)begin
     if(!pcb_page || !valid_point || hit!=repeat_action)repeat_active<=0;
     else if(repeat_count==0)begin action_valid<=1;action<=repeat_action;repeat_count<=PCB_REPEAT_PERIOD-1;end
     else repeat_count<=repeat_count-1'b1;
    end
   end
  end
 end
endmodule
