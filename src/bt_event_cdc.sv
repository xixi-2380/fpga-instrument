`timescale 1ns/1ps
// One outstanding full event. Source data stays frozen until the AUDIO
// consumer has really accepted it, including completed silence requests.
module bt_event_cdc #(parameter integer WIDTH=23)(
 input wire source_clk,audio_clk,rst,
 input wire source_valid,output wire source_ready,input wire [WIDTH-1:0] source_data,
 output wire audio_valid,input wire audio_ready,output wire [WIDTH-1:0] audio_data);
 wire sr,ar;reset_sync s_reset(source_clk,rst,sr);reset_sync a_reset(audio_clk,rst,ar);
 reg [WIDTH-1:0] held;
 reg request,ack,busy;
 (* syn_async_reg=1, async_reg="true" *) reg req_meta,req_sync,ack_meta,ack_sync;
 assign source_ready=!sr && busy && ack_sync==request;
 assign audio_valid=!ar && req_sync!=ack;
 assign audio_data=held;
 always @(posedge source_clk or posedge sr)begin
  if(sr)begin held<=0;request<=0;busy<=0;ack_meta<=0;ack_sync<=0;end
  else begin
   ack_meta<=ack;ack_sync<=ack_meta;
   if(source_ready)busy<=0;
   else if(source_valid && !busy)begin held<=source_data;request<=!request;busy<=1;end
  end
 end
 always @(posedge audio_clk or posedge ar)begin
  if(ar)begin req_meta<=0;req_sync<=0;ack<=0;end
  else begin
   req_meta<=request;req_sync<=req_meta;
   if(audio_valid && audio_ready)ack<=req_sync;
  end
 end
endmodule
