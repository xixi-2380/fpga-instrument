`timescale 1ns/1ps
`include "keyboard_config.svh"
`include "run_leds_config.svh"
module keyboard_top #(
    parameter integer LED_STEP_CYCLES=`RUN_LED_STEP_CYCLES,LOCK_N=`LOCK_CYCLES,SLOT_CYCLES=`KEY_SLOT_CYCLES,
    SETTLE_CYCLES=`KEY_SETTLE_CYCLES,DEBOUNCE_SCANS=`KEY_DEBOUNCE_SCANS,
    MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES,ATTACK=`ADSR_ATTACK_FRAMES,
    DECAY=`ADSR_DECAY_FRAMES,SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES)(
    input wire clk,rst,input wire [3:0] key_row,inout wire [3:0] key_col,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,DBG_BCK,DBG_WS,DBG_DIN,DBG_PA_EN,
    output wire [5:0] led_n);
    wire mid_clk,audio_clk,lock1,lock2,pll1_reset,pll2_reset,audio_reset;
    wire [3:0] col_enable,selected_key;
    wire [15:0] keys;
    wire [16:0] envelope_level;
    wire underrun,ghost,gate;
    run_leds #(.STEP_CYCLES(LED_STEP_CYCLES)) status_leds(clk,!audio_reset,gate,led_n);
    pll_pair clocks(clk,pll1_reset,pll2_reset,mid_clk,audio_clk,lock1,lock2);
    clock_reset #(.LOCK_N(LOCK_N)) reset_control(clk,rst,lock1,lock2,audio_clk,
        pll1_reset,pll2_reset,audio_reset);
    for(genvar c=0;c<4;c=c+1)begin: columns
        assign key_col[c]=col_enable[c]?1'b0:1'bz;
    end
    keyboard_core #(.SLOT_CYCLES(SLOT_CYCLES),.SETTLE_CYCLES(SETTLE_CYCLES),
        .DEBOUNCE_SCANS(DEBOUNCE_SCANS),.MUTE(MUTE),.FADE(FADE),
        .ATTACK(ATTACK),.DECAY(DECAY),.SUSTAIN(SUSTAIN),.RELEASE(RELEASE))
        core(audio_clk,audio_reset,key_row,col_enable,HP_BCK,HP_WS,HP_DIN,PA_EN,underrun,
             keys,ghost,gate,selected_key,envelope_level);
    assign DBG_BCK=HP_BCK;assign DBG_WS=HP_WS;
    assign DBG_DIN=HP_DIN;assign DBG_PA_EN=PA_EN;
endmodule
