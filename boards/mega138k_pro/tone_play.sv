`timescale 1ns/1ps
`include "synth_config.svh"
module tone_play_board #(
    parameter [1:0] CHANNEL_MODE=0,
    parameter integer LOCK_N=`LOCK_CYCLES,MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES)(
    input wire clk,rst,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,
    output wire DBG_BCK,DBG_WS,DBG_DIN,DBG_PA_EN);
    tone_top #(.CHANNEL_MODE(CHANNEL_MODE),.LOCK_N(LOCK_N),.MUTE(MUTE),.FADE(FADE))
        engine(clk,rst,HP_BCK,HP_WS,HP_DIN,PA_EN);
    assign DBG_BCK=HP_BCK;
    assign DBG_WS=HP_WS;
    assign DBG_DIN=HP_DIN;
    assign DBG_PA_EN=PA_EN;
endmodule

// The three build entry points differ only in the constant channel mode.
`define PLAY_ENTRY(NAME,MODE) \
module NAME #(parameter integer LOCK_N=`LOCK_CYCLES,MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES)( \
    input wire clk,rst,output wire HP_BCK,HP_WS,HP_DIN,PA_EN, \
    output wire DBG_BCK,DBG_WS,DBG_DIN,DBG_PA_EN); \
    tone_play_board #(.CHANNEL_MODE(MODE),.LOCK_N(LOCK_N),.MUTE(MUTE),.FADE(FADE)) \
        board(clk,rst,HP_BCK,HP_WS,HP_DIN,PA_EN,DBG_BCK,DBG_WS,DBG_DIN,DBG_PA_EN); \
endmodule
`PLAY_ENTRY(tone_play_stereo,2'd0)
`PLAY_ENTRY(tone_play_left,2'd1)
`PLAY_ENTRY(tone_play_right,2'd2)
`undef PLAY_ENTRY
