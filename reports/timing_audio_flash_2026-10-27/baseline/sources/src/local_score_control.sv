`timescale 1ns/1ps
// UI-independent song control. Pulsed action, held downstream requests.
// Actions: prev,next,play,pause,resume,stop,load,save,delete-confirmed.
module local_score_control(
 input wire clk,rst,action_valid,input wire [3:0] action,input wire [31:0] entries,
 input wire upload_active,library_busy,input wire song_valid,loaded_valid,input wire [4:0] loaded_index,
 output reg [4:0] selected,output wire busy,output reg done,output reg [7:0] error,
 output wire player_valid,input wire player_ready,output reg [1:0] player_command,
 input wire player_done,input wire [7:0] player_error,
 output wire library_valid,input wire library_ready,output reg [1:0] library_command,
 output reg [4:0] library_index,input wire library_done,input wire [7:0] library_error);
 localparam [2:0] IDLE=0,PLAYER_SEND=1,PLAYER_WAIT=2,LIB_SEND=3,LIB_WAIT=4;
 reg [2:0] state;reg play_after_load;
 assign busy=state!=IDLE;
 assign player_valid=state==PLAYER_SEND;
 assign library_valid=state==LIB_SEND;
 task automatic finish(input [7:0] e);begin error<=e;done<=1;state<=IDLE;end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin selected<=0;state<=IDLE;done<=0;error<=0;player_command<=0;library_command<=0;library_index<=0;play_after_load<=0;end
  else begin done<=0;
   case(state)
    IDLE:if(action_valid)begin
     error<=0;play_after_load<=0;
     if(action==0)begin selected<=selected-1'b1;done<=1;end
     else if(action==1)begin selected<=selected+1'b1;done<=1;end
     else if(upload_active || library_busy)finish(5);
     else if(action>=3 && action<=5)begin player_command<=action-2;state<=PLAYER_SEND;end
     else if(action==2 && loaded_valid && loaded_index==selected && song_valid)begin player_command<=0;state<=PLAYER_SEND;end
     else if(action==2 || action==6 || action==7 || action==8)begin
      if(action!=7 && !entries[selected])finish(8'h0e);
      else if(action==7 && !song_valid)finish(8'h0e);
      else begin
       library_command<=action==7?2'd0:action==8?2'd2:2'd1;library_index<=selected;
       play_after_load<=action==2;state<=LIB_SEND;
      end
     end else finish(6);
    end
    PLAYER_SEND:if(player_ready)state<=PLAYER_WAIT;
    PLAYER_WAIT:if(player_done)finish(player_error);
    LIB_SEND:if(library_ready)state<=LIB_WAIT;
    LIB_WAIT:if(library_done)begin
     if(library_error!=0)finish(library_error);
     else if(play_after_load)begin player_command<=0;state<=PLAYER_SEND;end
     else finish(0);
    end
    default:finish(8'h0d);
   endcase
  end
 end
endmodule
