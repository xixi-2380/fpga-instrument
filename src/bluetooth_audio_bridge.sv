`timescale 1ns/1ps
// Automatic IDs 0..15 are independent; ordinary note events preserve effects.
// Production natural EOF preserves tails; urgent Silence still clears promptly.
module bluetooth_audio_bridge #(parameter integer DRAIN_FRAMES=66,WAIT_FOR_TAIL=0,NATURAL_QUIET_FRAMES=2121)(
 input wire clk,rst,frame_ce,event_valid,input wire [1:0] event_kind,
 input wire [6:0] event_pitch,event_velocity,input wire inhibit,
 output wire event_ready,output wire note_valid,input wire note_ready,
 output wire note_on,output wire [6:0] note_id,
 output wire [31:0] note_fcw,output wire [6:0] note_velocity,output wire flush,
 input wire [2:0] selected_timbre,output reg [2:0] note_timbre,output wire [6:0] note_pitch,input wire audio_ready,
 input wire [6:0] event_id,output wire output_flush,input wire audio_quiet,output wire tail_pending);
 localparam [2:0] IDLE=0,CLEAR=1,SEND=2,ACK=3,DRAIN=4;
 localparam integer MAX_DRAIN=DRAIN_FRAMES>NATURAL_QUIET_FRAMES?DRAIN_FRAMES:NATURAL_QUIET_FRAMES;
 localparam integer CW=$clog2(MAX_DRAIN+3);
 reg [2:0] state;reg [CW-1:0] count;
 reg prior_inhibit,on_latched,has_event,silence_latched,end_acked;reg [6:0] pitch,velocity,ident;
 reg [31:0] fcw;
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
 assign flush=state==CLEAR || (state==DRAIN && !WAIT_FOR_TAIL);
 assign tail_pending=WAIT_FOR_TAIL && state==DRAIN;
 assign output_flush=state==CLEAR;
 assign note_valid=state==SEND;
 assign note_on=on_latched;
 assign note_id=ident;
 assign note_fcw=fcw;
 assign note_velocity=velocity;
 assign note_pitch=pitch;
 // Ack EOF once, so STOP/new PLAY can still interrupt a long release.
 assign event_ready=state==ACK || (state==SEND && note_ready) ||
                    (WAIT_FOR_TAIL && state==DRAIN && !end_acked);
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;count<=0;prior_inhibit<=0;has_event<=0;silence_latched<=0;end_acked<=0;on_latched<=0;pitch<=0;fcw<=0;velocity<=127;ident<=0;note_timbre<=0;end
  else begin
   prior_inhibit<=inhibit;
   if((state==IDLE || (WAIT_FOR_TAIL && state==DRAIN && end_acked)) && event_valid)begin
     has_event<=1;silence_latched<=event_kind>=2;on_latched<=event_kind==1;pitch<=event_pitch;velocity<=event_velocity;ident<=event_id;note_timbre<=selected_timbre;
     fcw<=frequency(event_pitch);
     if(event_kind==3)begin state<=DRAIN;count<=0;end_acked<=0;end
     else if(event_kind==2 || (inhibit && !prior_inhibit))begin state<=CLEAR;count<=0;end
     else state<=SEND;
   end else case(state)
    IDLE:if(inhibit && !prior_inhibit)begin has_event<=0;state<=CLEAR;count<=0;end
    DRAIN:if(WAIT_FOR_TAIL)begin
     if(!end_acked)begin end_acked<=1;has_event<=0;end
     if(frame_ce)begin
      // One entire longest delay line of exact stereo silence is required.
      // Isolated waveform zero crossings never qualify as the end of a tail.
      if(audio_quiet!==1'b1)count<=0;
      else if(count==NATURAL_QUIET_FRAMES-1)begin count<=0;state<=CLEAR;end
      else count<=count+1'b1;
     end
    end else if(frame_ce)begin
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
