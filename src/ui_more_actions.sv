`timescale 1ns/1ps
// Audio-domain adapter only. Delete requires two released activations.
module ui_more_actions(
 input wire clk,rst,menu_mode,action_valid,input wire [6:0] action,
 output reg open,delete_confirm,output reg command_valid,input wire command_ready,output reg [3:0] command,output reg info);
 `include "config/ui_layout.svh"
 always @(posedge clk or posedge rst)begin
  if(rst)begin open<=0;delete_confirm<=0;command_valid<=0;command<=0;info<=0;end
  else begin
   if(command_valid && command_ready)command_valid<=0;
   if(!menu_mode)begin open<=0;delete_confirm<=0;info<=0;end
   else if(action_valid)begin
    if(action==UI_OPEN_MORE)begin open<=1;delete_confirm<=0;info<=0;end
    else if(open && action==UI_MORE_BACK)begin open<=0;delete_confirm<=0;end
    else if(open && !command_valid)begin
     if(action>=UI_SONG_PREV && action<=UI_SONG_SAVE)begin command<=action-UI_SONG_PREV;command_valid<=1;delete_confirm<=0;end
     else if(action==UI_SONG_DELETE)begin
      if(delete_confirm)begin command<=8;command_valid<=1;delete_confirm<=0;end else delete_confirm<=1;
     end else begin delete_confirm<=0;if(action==UI_FLASH_INFO)info<=!info;end
    end
   end
  end
 end
endmodule
