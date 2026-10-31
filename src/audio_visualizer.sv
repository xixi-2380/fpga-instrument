`timescale 1ns/1ps
// Passive tap on actual post-effect PCM. The audio producer is never stalled.
// 128 points, one per four accepted48kHz samples:10.667ms rolling windows.
// Complete windows publish atomically; rgb_status_cdc captures a stable copy.
module audio_visualizer(
 input wire clk,rst,sample_valid,input wire signed [15:0] sample,
 output reg [1023:0] waveform,output reg [7:0] peak,output reg window_valid);
 reg [1023:0] working;
 reg [6:0] index;
 reg [1:0] decimate;
 reg [7:0] peak_work;
 wire [15:0] magnitude=sample[15] ? (~sample+16'd1) : sample;
 wire [7:0] amplitude=magnitude[15] ? 8'd255 : magnitude[14:7];
 wire [7:0] display_sample=sample[15:8];
 wire [7:0] max_peak=amplitude>peak_work ? amplitude : peak_work;
 always @(posedge clk or posedge rst)begin
  if(rst)begin waveform<=0;working<=0;peak<=0;window_valid<=0;index<=0;decimate<=0;peak_work<=0;end
  else begin
   window_valid<=0;
   if(sample_valid)begin
    decimate<=decimate+1'b1;
    peak_work<=max_peak;
    if(decimate==3)begin
     // A common shift enable avoids 128 separately decoded byte enables.
     working<={display_sample,working[1023:8]};
     if(index==127)begin
      waveform<={display_sample,working[1023:8]};peak<=max_peak;
      index<=0;peak_work<=0;window_valid<=1;
     end else index<=index+1'b1;
    end
   end
  end
 end
endmodule
