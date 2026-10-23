`timescale 1ns/1ps
// Audio-domain routing only. Raw matrix scanning continues in both modes.
// Sending zero keys to the note adapter drains Note Off instead of freezing it.
module ui_keypad_router #(parameter integer RELEASE_CYCLES=1)(
 input wire clk,rst,menu_mode,ghost,input wire [15:0] keys,
 output wire inhibit_notes,output reg action_valid,output reg [5:0] action);
 `include "config/ui_layout.svh"
 localparam integer RW=$clog2(RELEASE_CYCLES+1);
 reg [RW-1:0] release_count;
 wire all_released=release_count==RELEASE_CYCLES;
 reg play_armed,menu_armed,prior_menu;
 always @(posedge clk or posedge rst)begin
  if(rst)release_count<=0;
  else if(keys!=0 || ghost)release_count<=0;
  else if(!all_released)release_count<=release_count+1'b1;
 end
 reg [3:0] index;
 wire one_key=keys!=0 && (keys & (keys-16'd1))==0;
 assign inhibit_notes=menu_mode || !play_armed;
 always @*begin
  index=0;
  for(integer k=0;k<16;k=k+1)if(keys[k])index=k;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin play_armed<=0;menu_armed<=0;prior_menu<=0;action_valid<=0;action<=UI_NONE;end
  else begin
   action_valid<=0;prior_menu<=menu_mode;
   if(menu_mode)play_armed<=0;
   else if(all_released && !ghost)play_armed<=1;
   if(!menu_mode || !prior_menu || ghost)menu_armed<=0;
   else if(keys==0)menu_armed<=all_released;
   else begin
    menu_armed<=0;
    if(menu_armed && one_key)begin
     action_valid<=1;
     case(index)
      0:action<=UI_SINE;1:action<=UI_FLUTE;2:action<=UI_REED;3:action<=UI_MODE;
      4:action<=UI_ECHO;5:action<=UI_ROOM;6:action<=UI_TREMOLO;7:action<=UI_FX;
      8:action<=UI_LESS;9:action<=UI_MORE;10:action<=UI_SLOWER;11:action<=UI_FASTER;
      12:action<=UI_DEFAULTS;13:action<=UI_PREV;14:action<=UI_NEXT;15:action<=UI_MODE;
      default:begin action<=UI_NONE;action_valid<=0;end
     endcase
    end
   end
  end
 end
 // synthesis translate_off
 initial if(RELEASE_CYCLES<1)$fatal(1,"Invalid menu release qualification");
 // synthesis translate_on
endmodule
