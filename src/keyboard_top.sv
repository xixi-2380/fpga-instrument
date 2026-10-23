`timescale 1ns/1ps
`include "config/keyboard_config.svh"
`include "config/run_leds_config.svh"
module keyboard_top #(
    parameter SCORE_FILE="src/scores/twinkle.hex",
    parameter integer LCD_ENABLE=1,LCD_TEST_PATTERN=0,LCD_PCLK_INVERT=1,
    TOUCH_ENABLE=0,TOUCH_RESET_CYCLES=1000000,TOUCH_STRAP_CYCLES=300000,
    TOUCH_BOOT_CYCLES=2500000,TOUCH_POLL_CYCLES=500000,TOUCH_I2C_HALF=250,
    parameter integer SCORE_WORDS=512,SCORE_ENABLE=1,SCORE_BEAT_FRAMES=(`SAMPLE_HZ/2),
    LED_STEP_CYCLES=`RUN_LED_STEP_CYCLES,LED_DIAG_STEPS=`RUN_LED_DIAG_STEPS,
    LOCK_N=`LOCK_CYCLES,SLOT_CYCLES=`KEY_SLOT_CYCLES,
    SETTLE_CYCLES=`KEY_SETTLE_CYCLES,DEBOUNCE_SCANS=`KEY_DEBOUNCE_SCANS,
    MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES,ATTACK=`ADSR_ATTACK_FRAMES,
    DECAY=`ADSR_DECAY_FRAMES,SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES)(
    input wire clk,rst,input wire [3:0] key_row,inout wire [3:0] key_col,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,DBG_BCK,DBG_WS,DBG_DIN,DBG_PA_EN,
    output wire MAX_BCLK,MAX_LRCLK,MAX_DIN,MAX_SD_MODE,
    output wire [5:0] led_n,
    output wire lcd_clk,lcd_hs,lcd_vs,lcd_en,
    output wire [5:0] lcd_r,lcd_g,lcd_b,
    inout wire touch_scl,touch_sda,touch_int,touch_rst_n);
    wire [1:0] selected_timbre,event_timbre,key_timbre,score_timbre;
    wire synth_pa_enable;
    reg [1:0] max_clock_frames;
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
    wire touch_ready,touch_error,touch_down,touch_report;
    wire [3:0] touch_count;
    wire [15:0] touch_x,touch_y,touch_size,touch_resolution_x,touch_resolution_y;
    wire [7:0] touch_track_id;
    wire [31:0] touch_product_id;
    wire [38:0] touch_status={touch_ready,touch_error,touch_down,touch_count,touch_x,touch_y};
    // Bring MAX98357A out of shutdown after two running-clock frame boundaries.
    // Production MUTE=480 leaves >7.5ms of digital silence for device turn-on
    // before the existing startup fade or score/keyboard admission begins.
    always @(posedge audio_clk or posedge audio_reset)begin
        if(audio_reset)max_clock_frames<=0;
        else if(frame_ce && max_clock_frames!=2)max_clock_frames<=max_clock_frames+1'b1;
    end
    assign MAX_SD_MODE=!audio_reset && max_clock_frames==2;
    // Existing constrained board pads are deliberately parked. New MAX_* pads
    // have NO CST/SDC assignment yet; user requested pin planning separately.
    assign HP_BCK=0;assign HP_WS=0;assign HP_DIN=0;assign PA_EN=0;
    assign DBG_BCK=0;assign DBG_WS=0;assign DBG_DIN=0;assign DBG_PA_EN=0;

    if(TOUCH_ENABLE)begin: touch_on
        gt9110_touch #(.RESET_CYCLES(TOUCH_RESET_CYCLES),.STRAP_CYCLES(TOUCH_STRAP_CYCLES),
            .BOOT_CYCLES(TOUCH_BOOT_CYCLES),.POLL_CYCLES(TOUCH_POLL_CYCLES),
            .I2C_HALF_CYCLES(TOUCH_I2C_HALF)) touch_reader(
            .clk(clk),.rst(pll1_reset),.touch_scl(touch_scl),.touch_sda(touch_sda),
            .touch_int(touch_int),.touch_rst_n(touch_rst_n),.ready(touch_ready),
            .error(touch_error),.touch_down(touch_down),.report_pulse(touch_report),
            .touch_count(touch_count),.touch_x(touch_x),.touch_y(touch_y),.touch_size(touch_size),
            .track_id(touch_track_id),.product_id(touch_product_id),
            .resolution_x(touch_resolution_x),.resolution_y(touch_resolution_y));
    end else begin: touch_off
        assign touch_scl=1'bz;assign touch_sda=1'bz;assign touch_int=1'bz;assign touch_rst_n=1'bz;
        assign touch_ready=0;assign touch_error=0;assign touch_down=0;assign touch_report=0;
        assign touch_count=0;assign touch_x=0;assign touch_y=0;assign touch_size=0;
        assign touch_track_id=0;assign touch_product_id=0;assign touch_resolution_x=0;assign touch_resolution_y=0;
    end
    if(LCD_ENABLE)begin: lcd_on
        rgb_display #(.VOICES(`VOICE_COUNT),.TEST_PATTERN(LCD_TEST_PATTERN),
            .PCLK_INVERT(LCD_PCLK_INVERT)) display_driver(
            .ref_clk(clk),.pll_reset(pll1_reset),.audio_clk(audio_clk),.audio_reset(audio_reset),
            .voice_active(voice_active),.voice_held(voice_held),.selected_timbre(selected_timbre),
            .score_busy(score_busy),.audio_ready(input_ready),.score_error(score_error),
            .underrun(underrun),.ghost(ghost),.lcd_clk(lcd_clk),.lcd_hs(lcd_hs),
            .lcd_vs(lcd_vs),.lcd_en(lcd_en),.lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b),
            .touch_status(touch_status));
    end else begin: lcd_off
        assign lcd_clk=0;assign lcd_hs=1;assign lcd_vs=1;assign lcd_en=0;
        assign lcd_r=0;assign lcd_g=0;assign lcd_b=0;
    end
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
    timbre_control timbre_buttons(audio_clk,audio_reset,score_busy?16'b0:keys,selected_timbre);
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
        .note_id(note_id),.note_fcw(note_fcw),.note_timbre(event_timbre),
        .bck(MAX_BCLK),.ws(MAX_LRCLK),.din(MAX_DIN),.pa_enable(synth_pa_enable),.underrun(underrun),
        .frame_ce(frame_ce),.note_ready(note_ready),.input_ready(input_ready),
        .gate(gate),.voice_active(voice_active),.voice_held(voice_held),.envelope_level(envelope_level));
endmodule

