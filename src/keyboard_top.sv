`timescale 1ns/1ps
`include "config/keyboard_config.svh"
`include "config/run_leds_config.svh"
module keyboard_top #(
    parameter integer BT_ENABLE=1,BT_EN_ACTIVE_HIGH=1,OUTPUT_ENABLE=1,OUTPUT_GAIN=24,LIMITER_LOG2=6,
    parameter integer LCD_ENABLE=1,LCD_TEST_PATTERN=0,LCD_PCLK_INVERT=1,
    TOUCH_ENABLE=1,TOUCH_UI_ENABLE=1,TOUCH_RESET_CYCLES=1000000,TOUCH_STRAP_CYCLES=300000,
    TOUCH_BOOT_CYCLES=2500000,TOUCH_POLL_CYCLES=500000,TOUCH_I2C_HALF=250,
    parameter SCORE_FILE="src/scores/twinkle.hex",
    parameter integer SCORE_WORDS=512,SCORE_ENABLE=0,SCORE_BEAT_FRAMES=(`SAMPLE_HZ/2),
    BUTTON_DEBOUNCE_CYCLES=(`AUDIO_HZ/100),BUTTON_LONG_PRESS_CYCLES=(`AUDIO_HZ*4/5),
    LED_STEP_CYCLES=`RUN_LED_STEP_CYCLES,LED_DIAG_STEPS=`RUN_LED_DIAG_STEPS,
    LOCK_N=`LOCK_CYCLES,SLOT_CYCLES=`KEY_SLOT_CYCLES,
    SETTLE_CYCLES=`KEY_SETTLE_CYCLES,DEBOUNCE_SCANS=`KEY_DEBOUNCE_SCANS,
    MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES,ATTACK=`ADSR_ATTACK_FRAMES,
    DECAY=`ADSR_DECAY_FRAMES,SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES)(
    input wire bt_rx,output wire bt_tx,bt_en,
    input wire clk,rst,input wire [3:0] board_buttons_n,input wire [3:0] key_row,inout wire [3:0] key_col,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,DBG_BCK,DBG_WS,DBG_DIN,DBG_PA_EN,
    output wire MAX_BCLK,MAX_LRCLK,MAX_DIN,MAX_SD_MODE,
    output wire [5:0] led_n,
    output wire lcd_clk,lcd_hs,lcd_vs,lcd_en,output wire [5:0] lcd_r,lcd_g,lcd_b,
    inout wire touch_scl,touch_sda,touch_int,touch_rst_n);
    wire effects_enabled;
    wire synth_pa_enable;
    reg [1:0] max_clock_frames;
    wire visual_sample_valid;wire signed [15:0] visual_sample;wire [15:0] visual_notes;
    wire latency_valid;wire [19:0] latency_bcd;
    wire [1:0] effect_mode;
    wire [2:0] selected_timbre,event_timbre,key_timbre,score_timbre;
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
    wire menu_mode,inhibit_notes,cfg_valid,cfg_ready,cfg_applied;
    wire [8:0] echo_wet,room_wet,tremolo_depth;
    wire [6:0] echo_percent,room_percent,depth_percent,volume_percent;
    wire [3:0] tremolo_rate_hz,cfg_rate_hz;
    wire matrix_action_valid,touch_action_valid;
    wire [5:0] matrix_action,touch_action;
    wire ui_action_valid=matrix_action_valid || touch_action_valid;
    wire [5:0] ui_action=matrix_action_valid?matrix_action:touch_action;
    wire touch_ready,touch_error,touch_down,touch_report;
    wire [3:0] touch_count;
    wire [15:0] touch_x,touch_y,touch_size,touch_resolution_x,touch_resolution_y;
    wire [7:0] touch_track_id;wire [31:0] touch_product_id;
    wire [38:0] touch_status={touch_ready,touch_error,touch_down,touch_count,touch_x,touch_y};
    wire [70:0] touch_audio;
    wire touch_audio_valid,touch_update;
    wire bt_inhibit,bt_valid,bt_ready,bt_flush,bt_output_flush,bt_note_on;
    wire [6:0] bt_note_id,bt_velocity,bt_pitch;
    wire [2:0] bt_timbre;
    wire [31:0] bt_fcw;
    reg score_cancelled;
    reg bt_flush_d;
    always @(posedge audio_clk or posedge audio_reset)begin
        if(audio_reset)bt_flush_d<=0;else bt_flush_d<=bt_flush;
    end
    wire local_score_busy=score_busy && !score_cancelled;
    wire take_bt=bt_inhibit || bt_valid || bt_flush;
    assign bt_en=BT_EN_ACTIVE_HIGH ? 1'b1 : 1'b0;
    always @(posedge audio_clk or posedge audio_reset)begin
        if(audio_reset)score_cancelled<=0;
        else if(bt_inhibit || bt_valid)score_cancelled<=1;
    end
    if(BT_ENABLE)begin: bluetooth_on
        wire ev_valid,ev_ready;wire [1:0] kind;
        wire [6:0] ident,pitch,velocity;
        wire source_valid,source_ready,source_inhibit,source_reset;
        wire [1:0] source_kind;wire [6:0] source_id,source_pitch,source_velocity;
        wire channel_reset=pll1_reset || audio_reset;
        reset_sync bt_reset(clk,channel_reset,source_reset);
        (* syn_async_reg=1, async_reg="true" *) reg inhibit_meta,inhibit_sync;
        always @(posedge audio_clk or posedge audio_reset)begin
            if(audio_reset)begin inhibit_meta<=0;inhibit_sync<=0;end
            else begin inhibit_meta<=source_inhibit;inhibit_sync<=inhibit_meta;end
        end
        assign bt_inhibit=inhibit_sync;
        bluetooth_score_link #(.CLOCK_HZ(`REF_HZ),.MAX_VOICES(1)) link(
            .clk(clk),.rst(source_reset),.uart_rx_pin(bt_rx),.uart_tx_pin(bt_tx),
            .event_valid(source_valid),.event_ready(source_ready),.event_kind(source_kind),.event_id(source_id),
            .event_pitch(source_pitch),.event_velocity(source_velocity),.manual_inhibit(source_inhibit));
        // event_id remains in the atomic payload; one-voice capability only.
        bt_event_cdc #(.WIDTH(23)) events(clk,audio_clk,channel_reset,
            source_valid,source_ready,{source_kind,source_id,source_pitch,source_velocity},
            ev_valid,ev_ready,{kind,ident,pitch,velocity});
        bluetooth_audio_bridge #(.DRAIN_FRAMES(OUTPUT_ENABLE ? (1<<LIMITER_LOG2)+2 : 2)) bridge(.clk(audio_clk),.rst(audio_reset),.frame_ce(frame_ce),
            .event_valid(ev_valid),.event_ready(ev_ready),.event_kind(kind),
            .event_pitch(pitch),.event_velocity(velocity),.inhibit(bt_inhibit),
            .note_valid(bt_valid),.note_ready(bt_ready),.note_on(bt_note_on),
            .note_id(bt_note_id),.note_fcw(bt_fcw),.note_velocity(bt_velocity),.flush(bt_flush),
            .selected_timbre(selected_timbre),.note_timbre(bt_timbre),.note_pitch(bt_pitch),.audio_ready(input_ready),.output_flush(bt_output_flush));
    end else begin: bluetooth_off
        assign bt_tx=1;assign bt_inhibit=0;assign bt_valid=0;assign bt_flush=0;assign bt_output_flush=0;
        assign bt_note_on=0;assign bt_note_id=0;assign bt_fcw=0;assign bt_velocity=127;assign bt_pitch=0;assign bt_timbre=0;
    end
    assign bt_ready=note_ready && take_bt && !bt_flush;
    // Start the external amplifier only after I2S clocks have crossed two
    // frame boundaries. The existing production mute interval then supplies
    // more than 7.5 ms of digital silence before audio is admitted.
    always @(posedge audio_clk or posedge audio_reset)begin
        if(audio_reset)max_clock_frames<=0;
        else if(frame_ce && max_clock_frames!=2)max_clock_frames<=max_clock_frames+1'b1;
    end
    assign MAX_SD_MODE=!audio_reset && max_clock_frames==2;
    // Retired onboard PT8211/PA and scope-mirror pads remain parked low.
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
        rgb_status_cdc #(.WIDTH(71)) touch_bridge(clk,audio_clk,pll1_reset || audio_reset,
            {touch_resolution_x,touch_resolution_y,touch_status},touch_audio,touch_audio_valid,touch_update);
    end else begin: touch_off
        assign touch_scl=1'bz;assign touch_sda=1'bz;assign touch_int=1'bz;assign touch_rst_n=1'bz;
        assign touch_ready=0;assign touch_error=0;assign touch_down=0;assign touch_report=0;
        assign touch_count=0;assign touch_x=0;assign touch_y=0;assign touch_size=0;
        assign touch_track_id=0;assign touch_product_id=0;assign touch_resolution_x=0;assign touch_resolution_y=0;
        assign touch_audio=0;assign touch_audio_valid=0;assign touch_update=0;
    end
    ui_touch_actions touch_commands(.clk(audio_clk),.rst(audio_reset),
        .enabled(TOUCH_ENABLE!=0 && TOUCH_UI_ENABLE!=0),.snapshot_valid(touch_audio_valid),
        .ready(touch_audio[38]),.error(touch_audio[37]),.down(touch_audio[36]),.count(touch_audio[35:32]),
        .x(touch_audio[31:16]),.y(touch_audio[15:0]),.resolution_x(touch_audio[70:55]),
        .resolution_y(touch_audio[54:39]),.effect_mode(effect_mode),.menu_mode(menu_mode),
        .action_valid(touch_action_valid),.action(touch_action));
    ui_keypad_router #(.RELEASE_CYCLES(SLOT_CYCLES*4*(DEBOUNCE_SCANS+1))) menu_keys(.clk(audio_clk),.rst(audio_reset),.menu_mode(menu_mode || take_bt),
        .ghost(ghost),.keys(keys),.inhibit_notes(inhibit_notes),
        .action_valid(matrix_action_valid),.action(matrix_action));
    if(LCD_ENABLE)begin: lcd_on
        rgb_display #(.VOICES(`VOICE_COUNT),.TEST_PATTERN(LCD_TEST_PATTERN),
            .PCLK_INVERT(LCD_PCLK_INVERT)) display_driver(
            .ref_clk(clk),.pll_reset(pll1_reset),.audio_clk(audio_clk),.audio_reset(audio_reset),
            .voice_active(voice_active),.voice_held(voice_held),.selected_timbre(selected_timbre),
            .visual_sample_valid(visual_sample_valid),.visual_sample(visual_sample),.visual_notes(visual_notes),
            .latency_valid(latency_valid),.latency_bcd(latency_bcd),
            .score_busy(local_score_busy || bt_inhibit),.audio_ready(input_ready),.score_error(score_error),
            .underrun(underrun),.ghost(ghost),.lcd_clk(lcd_clk),.lcd_hs(lcd_hs),
            .lcd_vs(lcd_vs),.lcd_en(lcd_en),.lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b),
            .menu_mode(menu_mode),.effects_enabled(effects_enabled),.effect_mode(effect_mode),
            .echo_percent(echo_percent),.room_percent(room_percent),.depth_percent(depth_percent),
            .volume_percent(volume_percent),.tremolo_rate_hz(tremolo_rate_hz),.touch_enabled(TOUCH_ENABLE!=0),
            .touch_ui_enabled(TOUCH_UI_ENABLE!=0 && touch_audio_valid && touch_audio[70:55]==800 && touch_audio[54:39]==480),.touch_ready_status(touch_audio[38]),.touch_error_status(touch_audio[37]));
    end else begin: lcd_off
        assign lcd_clk=0;assign lcd_hs=1;assign lcd_vs=1;assign lcd_en=0;
        assign lcd_r=0;assign lcd_g=0;assign lcd_b=0;
    end
    // A source owns the event interface through its final release/tail. The
    // keyboard is admitted only after the one-shot score has fully completed.
    assign note_valid=bt_flush ? 1'b0 : take_bt ? bt_valid : local_score_busy ? score_valid : key_valid;
    assign note_on=take_bt?bt_note_on:local_score_busy?score_on:key_on;
    assign note_id=take_bt?bt_note_id:local_score_busy?score_id:key_id;
    assign note_fcw=take_bt?bt_fcw:local_score_busy?score_fcw:key_fcw;
    assign event_timbre=take_bt?bt_timbre:local_score_busy?score_timbre:key_timbre;
    score_player #(.SCORE_FILE(SCORE_FILE),.SCORE_WORDS(SCORE_WORDS),.ENABLE(SCORE_ENABLE),
        .BEAT_FRAMES(SCORE_BEAT_FRAMES),.TAIL_FRAMES(RELEASE+4))
        score(.clk(audio_clk),.rst(audio_reset),.input_ready(input_ready),.frame_ce(frame_ce),
        .note_ready(score_cancelled || (note_ready && local_score_busy && !take_bt)),.note_valid(score_valid),.note_on(score_on),
        .note_id(score_id),.note_fcw(score_fcw),.note_timbre(score_timbre),.busy(score_busy),.done(score_done),.error(score_error));
    timbre_control #(.DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES),.LONG_PRESS_CYCLES(BUTTON_LONG_PRESS_CYCLES)) timbre_buttons(
        .clk(audio_clk),.rst(audio_reset),.buttons_n(board_buttons_n),
        .selected(selected_timbre),.effects_enabled(effects_enabled),.effect_mode(effect_mode),
        .ui_action_valid(ui_action_valid),.ui_action(ui_action),.cfg_ready(cfg_ready),
        .menu_mode(menu_mode),.cfg_valid(cfg_valid),.cfg_tremolo_rate_hz(cfg_rate_hz),.echo_wet(echo_wet),.room_wet(room_wet),
        .tremolo_depth(tremolo_depth),.echo_percent(echo_percent),.room_percent(room_percent),
        .depth_percent(depth_percent),.tremolo_rate_hz(tremolo_rate_hz),.volume_percent(volume_percent));
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
        .clk(audio_clk),.rst(audio_reset),.input_ready(input_ready && !local_score_busy && !take_bt),.note_ready(note_ready && !local_score_busy && !take_bt),
        .key_row(key_row),.col_enable(col_enable),.keys(keys),.ghost(ghost),
        .note_valid(key_valid),.note_on(key_on),.note_id(key_id),.note_fcw(key_fcw),
        .gate(key_gate),.last_key(last_key),
        .selected_timbre(selected_timbre),.note_timbre(key_timbre),.inhibit_notes(inhibit_notes));
    synth_core #(.OUTPUT_ENABLE(OUTPUT_ENABLE),.OUTPUT_GAIN(OUTPUT_GAIN),.LIMITER_LOG2(LIMITER_LOG2),
        .MUTE(MUTE),.FADE(FADE),.ATTACK(ATTACK),.DECAY(DECAY),
        .SUSTAIN(SUSTAIN),.RELEASE(RELEASE)) sound(
        .clk(audio_clk),.rst(audio_reset),.note_valid(note_valid),.note_on(note_on),
        .note_pitch(take_bt ? bt_pitch : note_id),.volume_percent(volume_percent),.flush(bt_flush),.output_flush(bt_output_flush),.velocity_valid(take_bt),.note_velocity(bt_velocity),
        .note_id(note_id),.note_fcw(note_fcw),.note_timbre(event_timbre),.effects_enable(effects_enabled),.effect_mode(effect_mode),
        .effect_cfg_valid(cfg_valid || bt_flush_d),.effect_echo_wet(echo_wet),.effect_room_wet(room_wet),
        .effect_tremolo_depth(tremolo_depth),.effect_tremolo_rate_hz(cfg_rate_hz),
        .effect_cfg_ready(cfg_ready),.effect_cfg_applied(cfg_applied),
        .bck(MAX_BCLK),.ws(MAX_LRCLK),.din(MAX_DIN),.pa_enable(synth_pa_enable),.underrun(underrun),
        .frame_ce(frame_ce),.note_ready(note_ready),.input_ready(input_ready),
        .gate(gate),.voice_active(voice_active),.voice_held(voice_held),.envelope_level(envelope_level),
        .visual_sample_valid(visual_sample_valid),.visual_sample(visual_sample),.visual_notes(visual_notes),
        .latency_valid(latency_valid),.latency_bcd(latency_bcd));
endmodule


