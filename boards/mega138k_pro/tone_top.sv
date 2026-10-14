`timescale 1ns/1ps
`include "synth_config.svh"
module tone_top #(parameter [31:0] FCW=`TONE_FCW,
    parameter [1:0] CHANNEL_MODE=0,
    parameter integer LOCK_N=`LOCK_CYCLES,MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES)(
    input wire clk,rst,output wire HP_BCK,HP_WS,HP_DIN,PA_EN);
    wire mid_clk,audio_clk,lock1,lock2,pll1_reset,pll2_reset,audio_reset,underrun;
    pll_pair clocks(clk,pll1_reset,pll2_reset,mid_clk,audio_clk,lock1,lock2);
    clock_reset #(.LOCK_N(LOCK_N)) reset_control(clk,rst,lock1,lock2,audio_clk,
        pll1_reset,pll2_reset,audio_reset);
    tone_core #(.MUTE(MUTE),.FADE(FADE)) core(audio_clk,audio_reset,FCW,CHANNEL_MODE,
        HP_BCK,HP_WS,HP_DIN,PA_EN,underrun);
endmodule
