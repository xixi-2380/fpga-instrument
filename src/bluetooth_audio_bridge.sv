`timescale 1ns/1ps
// Single scheduler voice. Reattacks cut the preceding automatic tail;
// stop/pause/upload also clear effects. I2S clock and startup stay running.
module bluetooth_audio_bridge(
 input wire clk,rst,frame_ce,event_valid,input wire [1:0] event_kind,
 input wire [6:0] event_pitch,event_velocity,input wire inhibit,
 output wire event_ready,output wire note_valid,input wire note_ready,
 output wire note_on,output wire [6:0] note_id,
 output wire [31:0] note_fcw,output wire [6:0] note_velocity,output wire flush,
 input wire [2:0] selected_timbre,output reg [2:0] note_timbre,output wire [6:0] note_pitch,input wire audio_ready);
 localparam [2:0] IDLE=0,CLEAR=1,SEND=2,ACK=3;
 reg [2:0] state;reg [2:0] count;
 reg prior_inhibit,on_latched,has_event;reg [6:0] pitch,velocity;
 function automatic [31:0] frequency(input [6:0] midi);
 begin case(midi)
            7'd48:frequency=32'd11704930;
            7'd49:frequency=32'd12400941;
            7'd50:frequency=32'd13138339;
            7'd51:frequency=32'd13919586;
            7'd52:frequency=32'd14747287;
            7'd53:frequency=32'd15624207;
            7'd54:frequency=32'd16553270;
            7'd55:frequency=32'd17537579;
            7'd56:frequency=32'd18580418;
            7'd57:frequency=32'd19685267;
            7'd58:frequency=32'd20855814;
            7'd59:frequency=32'd22095965;
            7'd60:frequency=32'd23409859;
            7'd61:frequency=32'd24801882;
            7'd62:frequency=32'd26276679;
            7'd63:frequency=32'd27839171;
            7'd64:frequency=32'd29494575;
            7'd65:frequency=32'd31248413;
            7'd66:frequency=32'd33106541;
            7'd67:frequency=32'd35075158;
            7'd68:frequency=32'd37160835;
            7'd69:frequency=32'd39370534;
            7'd70:frequency=32'd41711627;
            7'd71:frequency=32'd44191930;
            7'd72:frequency=32'd46819719;
            7'd73:frequency=32'd49603764;
            7'd74:frequency=32'd52553357;
            7'd75:frequency=32'd55678342;
            7'd76:frequency=32'd58989149;
            7'd77:frequency=32'd62496826;
            7'd78:frequency=32'd66213081;
            7'd79:frequency=32'd70150316;
            7'd80:frequency=32'd74321671;
            7'd81:frequency=32'd78741067;
            7'd82:frequency=32'd83423255;
            7'd83:frequency=32'd88383859;
            default:frequency=0;
 endcase end endfunction
 assign flush=state==CLEAR;
 assign note_valid=state==SEND;
 assign note_on=on_latched;
 assign note_id=0;
 assign note_fcw=frequency(pitch);
 assign note_velocity=velocity;
 assign note_pitch=pitch;
 assign event_ready=state==ACK || (state==SEND && note_ready);
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;count<=0;prior_inhibit<=0;has_event<=0;on_latched<=0;pitch<=0;velocity<=127;note_timbre<=0;end
  else begin
   prior_inhibit<=inhibit;
   case(state)
    IDLE:if(event_valid)begin
     has_event<=1;on_latched<=event_kind==1;pitch<=event_pitch;velocity<=event_velocity;note_timbre<=selected_timbre;
     if(event_kind==0)state<=SEND;else begin state<=CLEAR;count<=0;end
    end else if(inhibit && !prior_inhibit)begin has_event<=0;state<=CLEAR;count<=0;end
    // Two frame boundaries replace both serializer channels with silence
    // before acknowledging a clear, without disturbing BCLK/LRCLK.
    CLEAR:if(frame_ce)begin
     if(count==0)count<=1;
     else if(audio_ready)state<=has_event ? (on_latched?SEND:ACK) : IDLE;
    end
    SEND:if(note_ready)state<=IDLE;
    ACK:state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
