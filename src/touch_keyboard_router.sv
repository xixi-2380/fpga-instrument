`timescale 1ns/1ps
// Piano release qualification is per key. Entering menus/BT or disconnecting
// drains Note Off; held keys cannot start again until physically released.
module touch_keyboard_router #(parameter integer AUX_ENABLE=1)(
 input wire clk,rst,blocked,menu_mode,more_mode,ultrasonic_page,
 input wire snapshot_valid,input wire [35:0] piano,input wire [11:0] aux,
 input wire [2:0] online,output wire [35:0] note_keys,
 output reg action_valid,output reg [5:0] action,output wire [35:0] qualified_keys);
 `include "config/ui_layout.svh"
 reg [35:0] armed;
 assign qualified_keys=armed;reg [11:0] aux_armed;
 reg [2:0] was_online;
 wire [35:0] connected={{12{online[2]}},{12{online[1]}},{12{online[0]}}};
 wire [11:0] aux_connected={{4{online[2]}},{4{online[1]}},{4{online[0]}}};
 wire [11:0] aux_pressed=aux & aux_armed & aux_connected;
 assign note_keys=(!blocked && snapshot_valid)?(piano & armed & connected):36'd0;
 reg [3:0] index;
 always @*begin
  index=0;for(integer k=11;k>=0;k=k-1)if(aux_pressed[k])index=k;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin armed<=0;aux_armed<=0;was_online<=0;action_valid<=0;action<=UI_NONE;end
  else begin
   action_valid<=0;was_online<=online;
   for(integer b=0;b<3;b=b+1)begin
    if(!snapshot_valid || !online[b] || !was_online[b])begin armed[b*12+:12]<=0;aux_armed[b*4+:4]<=0;end
    else begin
     if(blocked)armed[b*12+:12]<=0;
     else armed[b*12+:12]<=armed[b*12+:12] | ~piano[b*12+:12];
     aux_armed[b*4+:4]<=~aux[b*4+:4];
    end
   end
   // AUX1..12 are settings controls, never note IDs.
   if(AUX_ENABLE!=0 && snapshot_valid && |aux_pressed)begin
    action_valid<=1;
    if(more_mode)case(index)
     0:action<=UI_SONG_PREV;1:action<=UI_SONG_NEXT;2:action<=UI_SONG_LOAD;3:action<=UI_SONG_PLAY;
     4:action<=UI_SONG_PAUSE;5:action<=UI_SONG_RESUME;6:action<=UI_SONG_STOP;7:action<=UI_SONG_SAVE;
     8:action<=UI_SONG_DELETE;9:action<=UI_FLASH_INFO;10,11:action<=UI_MORE_BACK;
    endcase
    else if(ultrasonic_page)case(index)
     0:action<=UI_ULTRA_TOGGLE;1:action<=UI_SENS_DOWN;2:action<=UI_SENS_UP;
     4:action<=UI_MIN_DOWN;5:action<=UI_MIN_UP;6:action<=UI_MAX_DOWN;7:action<=UI_MAX_UP;
     3,11:action<=UI_ULTRA_BACK;default:begin action<=UI_NONE;action_valid<=0;end
    endcase
    else case(index)
     0:action<=UI_PREV;1:action<=UI_NEXT;2:action<=UI_VOLUME_DOWN;3:action<=UI_VOLUME_UP;
     4:action<=UI_ECHO;5:action<=UI_ROOM;6:action<=UI_TREMOLO;7:action<=UI_FX;
     8:action<=UI_MODE;9:begin action<=UI_ULTRA_OPEN;action_valid<=menu_mode;end
     10:begin action<=UI_OPEN_MORE;action_valid<=menu_mode;end
     11:action<=UI_DEFAULTS;
    endcase
   end
  end
 end
endmodule
