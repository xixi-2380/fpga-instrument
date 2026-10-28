`timescale 1ns/1ps
// Control-to-digital-output latency, not acoustic onset. Start: accepted On.
// End: the tagged first applied PCM frame's LEFT LSB sampled on rising BCLK.
// New On supersedes a still-pending measurement (last note of a chord burst).
module audio_latency_meter #(parameter integer CLOCK_HZ=61440000)(
 input wire clk,rst,cancel,note_accept,input wire [6:0] note_id,
 input wire frame_ce,voice_valid,input wire [6:0] voice_id,
 input wire serial_complete,input wire [16:0] serial_tag,
 output reg [16:0] render_tag,output reg latency_valid,output reg [19:0] latency_bcd);
 function automatic integer gcd(input integer a,b);
  integer x,y,t;begin x=a;y=b;while(y!=0)begin t=x%y;x=y;y=t;end gcd=x;end
 endfunction
 localparam integer GCD=gcd(CLOCK_HZ,100000),STEP=100000/GCD,MODULUS=CLOCK_HZ/GCD;
 localparam integer FW=$clog2(MODULUS+STEP+1);
 reg [FW-1:0] fraction;wire [FW:0] next_fraction={1'b0,fraction}+STEP;
 reg [23:0] ticks,started;reg [15:0] epoch,frame_epoch;
 reg [6:0] tracked_id,frame_id;reg awaiting,frame_pending;
 wire [23:0] elapsed=ticks-started;
 reg [16:0] binary;reg [19:0] bcd_work;reg [4:0] remaining;
 reg [19:0] adjusted;
 always @*begin
  adjusted=bcd_work;
  for(integer d=0;d<5;d=d+1)if(bcd_work[d*4+:4]>=5)adjusted[d*4+:4]=bcd_work[d*4+:4]+4'd3;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   ticks<=0;fraction<=0;started<=0;epoch<=0;frame_epoch<=0;tracked_id<=0;frame_id<=0;
   awaiting<=0;frame_pending<=0;render_tag<=0;latency_valid<=0;latency_bcd<=0;
   binary<=0;bcd_work<=0;remaining<=0;
  end else begin
   if(next_fraction>=MODULUS)begin fraction<=next_fraction-MODULUS;ticks<=ticks+1'b1;end
   else fraction<=next_fraction[FW-1:0];
   if(remaining!=0)begin
    bcd_work<={adjusted[18:0],binary[16]};binary<=binary<<1;remaining<=remaining-1'b1;
    if(remaining==1)begin latency_bcd<={adjusted[18:0],binary[16]};latency_valid<=1;end
   end
   if(cancel)begin awaiting<=0;frame_pending<=0;render_tag<=0;remaining<=0;end
   else begin
    if(frame_ce)begin
     frame_epoch<=epoch;frame_id<=tracked_id;frame_pending<=awaiting;render_tag<=0;
    end
    if(voice_valid && frame_pending && frame_epoch==epoch && voice_id==frame_id)
     render_tag<={1'b1,frame_epoch};
    if(serial_complete && serial_tag[16] && serial_tag[15:0]==epoch && awaiting)begin
     binary<=elapsed>99999 ? 17'd99999 : elapsed[16:0];bcd_work<=0;remaining<=17;awaiting<=0;
    end
    // A simultaneous new event is the next measurement, never the old tag.
    if(note_accept)begin epoch<=epoch+1'b1;tracked_id<=note_id;started<=ticks;awaiting<=1;end
   end
  end
 end
 // synthesis translate_off
 initial if(CLOCK_HZ<100000)$fatal(1,"Latency clock must be >=100kHz");
 // synthesis translate_on
endmodule
