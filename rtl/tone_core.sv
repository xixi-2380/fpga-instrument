`timescale 1ns/1ps
`include "synth_config.svh"
module tone_core #(parameter integer MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES)(
    input wire clk,rst,input wire [31:0] fcw,input wire [1:0] channel_mode,
    output wire bck,ws,din,pa_enable,underrun);
    wire rise_ce,fall_ce,frame_ce;
    wire [4:0] bit_index;
    wire signed [15:0] raw_sample,gain_sample;
    wire raw_valid,gain_valid,ready;
    wire [31:0] phase;
    wire [16:0] level;
    wire [15:0] frame_l,frame_r;
    audio_timing timing(clk,rst,bck,rise_ce,fall_ce,frame_ce,bit_index);
    dds_sine dds(clk,rst,frame_ce,fcw,raw_sample,raw_valid,phase);
    startup_envelope #(.MUTE(MUTE),.FADE(FADE)) startup(clk,rst,frame_ce,pa_enable,level);
    tone_gain gain(clk,rst,raw_valid,raw_sample,level,gain_valid,gain_sample);
    frame_buffer buffer(clk,rst,frame_ce,gain_valid,ready,
        channel_mode==2 ? 16'sd0 : gain_sample,
        channel_mode==1 ? 16'sd0 : gain_sample,frame_l,frame_r,underrun);
    pt8211_tx tx(clk,rst,fall_ce,bit_index,frame_l,frame_r,ws,din);
    // Core has a fixed two-cycle production latency, and 1280 cycles/frame.
    // Backpressure cannot occur in this closed path; verified by tb_tone_core.
endmodule
