`timescale 1ns/1ps
// Automatic IDs 0..15 are independent; ordinary note events preserve effects.
// Only source takeover and explicit Silence clear the engine/serial buffers.
module bluetooth_audio_bridge #(parameter integer DRAIN_FRAMES=66)(
 input wire clk,rst,frame_ce,event_valid,input wire [1:0] event_kind,
 input wire [6:0] event_pitch,event_velocity,input wire inhibit,
 output wire event_ready,output wire note_valid,input wire note_ready,
 output wire note_on,output wire [6:0] note_id,
 output wire [31:0] note_fcw,output wire [6:0] note_velocity,output wire flush,
 input wire [4:0] selected_timbre,output reg [4:0] note_timbre,output wire [6:0] note_pitch,input wire audio_ready,
 input wire [6:0] event_id,output wire output_flush,input wire [4:0] event_timbre,input wire event_legacy);
 localparam [2:0] IDLE=0,CLEAR=1,SEND=2,ACK=3,DRAIN=4;
 localparam integer CW=$clog2(DRAIN_FRAMES+3);
 reg [2:0] state;reg [CW-1:0] count;
 reg prior_inhibit,on_latched,has_event,silence_latched;reg [6:0] pitch,velocity,ident;
 reg [31:0] fcw;
 `include "config/midi_frequency.svh"
 assign flush=state==CLEAR || state==DRAIN;
 assign output_flush=state==CLEAR;
 assign note_valid=state==SEND;
 assign note_on=on_latched;
 assign note_id=ident;
 assign note_fcw=fcw;
 assign note_velocity=velocity;
 assign note_pitch=pitch;
 assign event_ready=state==ACK || (state==SEND && note_ready);
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;count<=0;prior_inhibit<=0;has_event<=0;silence_latched<=0;on_latched<=0;pitch<=0;fcw<=0;velocity<=127;ident<=0;note_timbre<=0;end
  else begin
   prior_inhibit<=inhibit;
   case(state)
    IDLE:if(event_valid)begin
     has_event<=1;silence_latched<=event_kind>=2;on_latched<=event_kind==1;pitch<=event_pitch;velocity<=event_velocity;ident<=event_id;note_timbre<=event_legacy===1'b0 ?event_timbre:selected_timbre;
     fcw<=frequency(event_pitch);
     if(event_kind==3)begin state<=DRAIN;count<=0;end
     else if(event_kind==2 || (inhibit && !prior_inhibit))begin state<=CLEAR;count<=0;end
     else state<=SEND;
    end else if(inhibit && !prior_inhibit)begin has_event<=0;state<=CLEAR;count<=0;end
    DRAIN:if(frame_ce)begin
     if(count==DRAIN_FRAMES-1)begin count<=0;state<=CLEAR;end
     else count<=count+1'b1;
    end
    // Two frame boundaries replace both serializer channels with silence
    // before acknowledging a clear, without disturbing BCLK/LRCLK.
    CLEAR:if(frame_ce)begin
     if(count==0)count<=1;
     else if(audio_ready)state<=has_event ? (silence_latched?ACK:SEND) : IDLE;
    end
    SEND:if(note_ready)state<=IDLE;
    ACK:state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
