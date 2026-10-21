`timescale 1ns/1ps
`include "config/keyboard_config.svh"
`include "config/run_leds_config.svh"
module keyboard_top #(
    parameter SCORE_FILE="src/scores/twinkle.hex",
    parameter integer SCORE_WORDS=512,SCORE_ENABLE=1,SCORE_BEAT_FRAMES=(`SAMPLE_HZ/2),
    BUTTON_DEBOUNCE_CYCLES=(`AUDIO_HZ/100),
    LED_STEP_CYCLES=`RUN_LED_STEP_CYCLES,LED_DIAG_STEPS=`RUN_LED_DIAG_STEPS,
    LOCK_N=`LOCK_CYCLES,SLOT_CYCLES=`KEY_SLOT_CYCLES,
    SETTLE_CYCLES=`KEY_SETTLE_CYCLES,DEBOUNCE_SCANS=`KEY_DEBOUNCE_SCANS,
    MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES,ATTACK=`ADSR_ATTACK_FRAMES,
    DECAY=`ADSR_DECAY_FRAMES,SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES)(
    input wire clk,rst,input wire [3:0] board_buttons_n,input wire [3:0] key_row,inout wire [3:0] key_col,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,DBG_BCK,DBG_WS,DBG_DIN,DBG_PA_EN,
    output wire [5:0] led_n);
    wire effects_enabled;
    wire [1:0] selected_timbre,event_timbre,key_timbre,score_timbre;
    wire key_valid,key_on,score_valid,score_on,score_busy,score_done,score_error;
    wire [6:0] key_id,score_id;
    wire [31:0] key_fcw,score_fcw;
    wire mid_clk,audio_clk,lock1,lock2,pll1_reset,pll2_reset,audio_reset;
    wire [3:0] col_enable,last_key;
    wire [15:0] keys;
    wire [16:0] envelope_level;
    wire underrun,ghost,gate,key_gate,frame_ce,input_ready,note_ready,note_valid,note_on;
    wire [6:0] note_id;
    wire [31:0] note_fcw;
    wire [`VOICE_COUNT-1:0] voice_active,voice_held;
    // A source owns the event interface through its final release/tail. The
    // keyboard is admitted only after the one-shot score has fully completed.
    assign note_valid=score_busy?score_valid:key_valid;
    assign note_on=score_busy?score_on:key_on;
    assign note_id=score_busy?score_id:key_id;
    assign note_fcw=score_busy?score_fcw:key_fcw;
    assign event_timbre=score_busy?score_timbre:key_timbre;
    score_player #(.SCORE_FILE(SCORE_FILE),.SCORE_WORDS(SCORE_WORDS),.ENABLE(SCORE_ENABLE),
        .BEAT_FRAMES(SCORE_BEAT_FRAMES),.TAIL_FRAMES(RELEASE+4))
        score(.clk(audio_clk),.rst(audio_reset),.input_ready(input_ready),.frame_ce(frame_ce),
        .note_ready(note_ready && score_busy),.note_valid(score_valid),.note_on(score_on),
        .note_id(score_id),.note_fcw(score_fcw),.note_timbre(score_timbre),.busy(score_busy),.done(score_done),.error(score_error));
    timbre_control #(.DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES)) timbre_buttons(
        .clk(audio_clk),.rst(audio_reset),.buttons_n(board_buttons_n),
        .selected(selected_timbre),.effects_enabled(effects_enabled));
    run_leds #(.STEP_CYCLES(LED_STEP_CYCLES),.DIAG_STEPS(LED_DIAG_STEPS)) status_leds(
        .clk(clk),.audio_ready_async(!audio_reset),.key_active_async(gate),
        .pll1_lock_async(lock1),.pll2_lock_async(lock2),.reset_active_async(rst),.led_n(led_n));
    pll_pair clocks(clk,pll1_reset,pll2_reset,mid_clk,audio_clk,lock1,lock2);
    clock_reset #(.LOCK_N(LOCK_N)) reset_control(clk,rst,lock1,lock2,audio_clk,
        pll1_reset,pll2_reset,audio_reset);
    for(genvar c=0;c<4;c=c+1)begin: columns
        assign key_col[c]=col_enable[c]?1'b0:1'bz;
    end
    keyboard_core #(.SLOT_CYCLES(SLOT_CYCLES),.SETTLE_CYCLES(SETTLE_CYCLES),
        .DEBOUNCE_SCANS(DEBOUNCE_SCANS)) core(
        .clk(audio_clk),.rst(audio_reset),.input_ready(input_ready && !score_busy),.note_ready(note_ready && !score_busy),
        .key_row(key_row),.col_enable(col_enable),.keys(keys),.ghost(ghost),
        .note_valid(key_valid),.note_on(key_on),.note_id(key_id),.note_fcw(key_fcw),
        .gate(key_gate),.last_key(last_key),
        .selected_timbre(selected_timbre),.note_timbre(key_timbre));
    synth_core #(.MUTE(MUTE),.FADE(FADE),.ATTACK(ATTACK),.DECAY(DECAY),
        .SUSTAIN(SUSTAIN),.RELEASE(RELEASE)) sound(
        .clk(audio_clk),.rst(audio_reset),.note_valid(note_valid),.note_on(note_on),
        .note_id(note_id),.note_fcw(note_fcw),.note_timbre(event_timbre),.effects_enable(effects_enabled),
        .bck(HP_BCK),.ws(HP_WS),.din(HP_DIN),.pa_enable(PA_EN),.underrun(underrun),
        .frame_ce(frame_ce),.note_ready(note_ready),.input_ready(input_ready),
        .gate(gate),.voice_active(voice_active),.voice_held(voice_held),.envelope_level(envelope_level));
    assign DBG_BCK=HP_BCK;assign DBG_WS=HP_WS;
    assign DBG_DIN=HP_DIN;assign DBG_PA_EN=PA_EN;
endmodule


