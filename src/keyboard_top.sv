`timescale 1ns/1ps
`include "config/keyboard_config.svh"
`include "config/run_leds_config.svh"
module keyboard_top #(
    parameter integer BT_ENABLE=1,FLASH_WRITES=1,OUTPUT_ENABLE=1,OUTPUT_GAIN=24,LIMITER_LOG2=6,LIMITER_HOLD_SAMPLES=240,
    ULTRA_PERIOD_US=60000,ULTRA_TIMEOUT_US=30000,ULTRA_LOST_MS=1000,ULTRA_SLEW_CYCLES=(`AUDIO_HZ/500),
    parameter integer KEYPAD_AUX_ENABLE=0,KEYPAD_BOOT_CYCLES=500000,KEYPAD_POLL_CYCLES=150000,KEYPAD_I2C_HALF=250,
    KEYPAD_TIMEOUT_CYCLES=50000,KEYPAD_RETRY_CYCLES=500000,
    KEYPAD_STALE_CYCLES=2500000,PCB_COMMAND_TIMEOUT_CYCLES=150000000,
    EC11_MS_CYCLES=(`AUDIO_HZ/1000),EC11_FILTER_CYCLES=(`AUDIO_HZ/20000),
    EC11_DEBOUNCE_MS=10,EC11_DOUBLE_MS=250,EC11_LONG_MS=600,EC11_STEPS=4,
    parameter [2:0] EC11_REVERSE=3'b000,
    parameter integer STEREO_ENABLE=1,LCD_ENABLE=1,LCD_TEST_PATTERN=0,LCD_PCLK_INVERT=1,
    TOUCH_ENABLE=1,TOUCH_UI_ENABLE=1,TOUCH_RESET_CYCLES=1000000,TOUCH_STRAP_CYCLES=300000,
    TOUCH_BOOT_CYCLES=2500000,TOUCH_POLL_CYCLES=500000,TOUCH_I2C_HALF=250,
    parameter SCORE_FILE="src/scores/twinkle.hex",
    parameter integer SCORE_WORDS=512,SCORE_ENABLE=0,SCORE_BEAT_FRAMES=(`SAMPLE_HZ/2),
    BUTTON_DEBOUNCE_CYCLES=(`AUDIO_HZ/100),BUTTON_LONG_PRESS_CYCLES=(`AUDIO_HZ*4/5),
    LED_STEP_CYCLES=`RUN_LED_STEP_CYCLES,LED_DIAG_STEPS=`RUN_LED_DIAG_STEPS,
    LOCK_N=`LOCK_CYCLES,
    MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES,ATTACK=`ADSR_ATTACK_FRAMES,
    DECAY=`ADSR_DECAY_FRAMES,SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES)(
    input wire bt_rx,output wire bt_tx,input wire ultrasonic_echo,output wire ultrasonic_trig,
    input wire clk,rst,input wire [3:0] board_buttons_n,inout wire [2:0] keypad_sda,keypad_scl,input wire [2:0] keypad_int_n,
    input wire [2:0] ec11_a,ec11_b,ec11_sw_n,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,
    output wire MAX_BCLK,MAX_LRCLK,MAX_DIN,MAX_SD_MODE,
    output wire [4:0] led_n,
    output wire lcd_clk,lcd_hs,lcd_vs,lcd_en,output wire [5:0] lcd_r,lcd_g,lcd_b,
    inout wire touch_scl,touch_sda,touch_int,touch_rst_n,
    output wire flash_cs_n,flash_sck,flash_mosi,input wire flash_miso,output wire flash_wp_n,flash_hold_n);
    wire effects_enabled;
    wire synth_pa_enable;
    reg [1:0] max_clock_frames;
    wire visual_sample_valid;wire signed [15:0] visual_sample;wire [35:0] visual_notes;
    wire latency_valid;wire [19:0] latency_bcd;
    wire [1:0] effect_mode;
    wire [2:0] selected_timbre,event_timbre,key_timbre,score_timbre;
    wire key_valid,key_on,score_valid,score_on,score_busy,score_done,score_error;
    wire [6:0] key_id,score_id;
    wire [31:0] key_fcw,score_fcw;
    wire mid_clk,audio_clk,lock1,lock2,pll1_reset,pll2_reset,audio_reset;
    wire [5:0] last_key;
    wire [35:0] keys,note_keys;
    wire [11:0] auxiliary_keys;
    wire [2:0] keypad_online;
    wire keypad_snapshot_valid,keypad_snapshot_update;
    wire [16:0] envelope_level;
    wire ghost=1'b0;
    wire underrun,gate,key_gate,frame_ce,input_ready,note_ready,note_valid,note_on;
    wire [6:0] note_id;
    wire [31:0] note_fcw;
    wire [`VOICE_COUNT-1:0] voice_active,voice_held;
    wire menu_mode,cfg_valid,cfg_ready,cfg_applied;
    wire [8:0] echo_wet,room_wet,tremolo_depth;
    wire [6:0] echo_percent,room_percent,depth_percent,volume_percent;
    wire ultrasonic_page,ultrasonic_enabled;
    wire [2:0] ultrasonic_sensitivity;
    wire [6:0] ultrasonic_min,ultrasonic_max;
    wire [7:0] ultrasonic_version;
    wire [32:0] ultrasonic_cfg;
    wire ultrasonic_cfg_valid,ultrasonic_result_valid;
    wire [29:0] ultrasonic_result;
    wire ultrasonic_reset=pll1_reset || audio_reset;
    wire ultrasonic_ref_reset;
    reset_sync ultrasonic_reset_sync(clk,ultrasonic_reset,ultrasonic_ref_reset);
    rgb_status_cdc #(.WIDTH(33)) ultrasonic_config_bridge(audio_clk,clk,ultrasonic_reset,
        {ultrasonic_version,ultrasonic_enabled,ultrasonic_sensitivity,ultrasonic_min,ultrasonic_max,volume_percent},
        ultrasonic_cfg,ultrasonic_cfg_valid,);
    wire range_report,range_valid;wire [12:0] range_mm;
    wire [6:0] ultrasonic_target;wire [2:0] ultrasonic_state;
    wire [11:0] ultrasonic_distance_bcd;wire [7:0] ultrasonic_applied_version;
    ultrasonic_range #(.CLOCK_HZ(`REF_HZ),.PERIOD_US(ULTRA_PERIOD_US),.TIMEOUT_US(ULTRA_TIMEOUT_US)) range_reader(
        .clk(clk),.rst(ultrasonic_ref_reset),.enabled(ultrasonic_cfg_valid && ultrasonic_cfg[24]),
        .echo(ultrasonic_echo),.trig(ultrasonic_trig),.report(range_report),.valid(range_valid),.distance_mm(range_mm));
    ultrasonic_volume #(.CLOCK_HZ(`REF_HZ),.LOST_MS(ULTRA_LOST_MS)) range_volume(
        .clk(clk),.rst(ultrasonic_ref_reset),.cfg_valid(ultrasonic_cfg_valid),.enabled(ultrasonic_cfg[24]),
        .sensitivity(ultrasonic_cfg[23:21]),.minimum(ultrasonic_cfg[20:14]),.maximum(ultrasonic_cfg[13:7]),
        .manual_percent(ultrasonic_cfg[6:0]),.version(ultrasonic_cfg[32:25]),
        .report(range_report),.valid(range_valid),.distance_mm(range_mm),.target(ultrasonic_target),
        .status(ultrasonic_state),.distance_bcd(ultrasonic_distance_bcd),.applied_version(ultrasonic_applied_version));
    rgb_status_cdc #(.WIDTH(30)) ultrasonic_status_bridge(clk,audio_clk,ultrasonic_reset,
        {ultrasonic_applied_version,ultrasonic_target,ultrasonic_state,ultrasonic_distance_bcd},
        ultrasonic_result,ultrasonic_result_valid,);
    wire ultrasonic_current=ultrasonic_result_valid && ultrasonic_result[29:22]==ultrasonic_version;
    reg [2:0] ultrasonic_ui_state;
    always @(posedge audio_clk or posedge audio_reset)
        if(audio_reset)ultrasonic_ui_state<=0;
        else ultrasonic_ui_state<=!ultrasonic_enabled ? 3'd0 : ultrasonic_current ? ultrasonic_result[14:12] : 3'd1;
    wire [33:0] ultrasonic_ui={ultrasonic_page,ultrasonic_enabled,ultrasonic_sensitivity,
        ultrasonic_min,ultrasonic_max,ultrasonic_ui_state,ultrasonic_result[11:0]};
    wire [3:0] tremolo_rate_hz,cfg_rate_hz;
    wire [2:0] effect_mask,cfg_effect_mask,encoder_up,encoder_down,encoder_single,encoder_double;
    wire echo_edit_strength,tremolo_edit_rate;wire [8:0] echo_time_ms;
    wire [11:0] echo_time_bcd;wire [14:0] cfg_echo_samples;
    wire [383:0] encoder_diagnostics;wire [2:0] encoder_clear;
    localparam integer ECW=EC11_MS_CYCLES>1?$clog2(EC11_MS_CYCLES):1;
    reg [ECW-1:0] encoder_ms_count;
    wire encoder_ms_ce=encoder_ms_count==EC11_MS_CYCLES-1;
    wire encoder_ms_pre_ce=EC11_MS_CYCLES==1 || encoder_ms_count==EC11_MS_CYCLES-2;
    wire [2:0] encoder_ms_ticks;
    always @(posedge audio_clk or posedge audio_reset)
        if(audio_reset)encoder_ms_count<=0;
        else if(encoder_ms_ce)encoder_ms_count<=0;else encoder_ms_count<=encoder_ms_count+1'b1;
    for(genvar e=0;e<3;e=e+1)begin: encoders
        // Register the same tick in each controller's neighborhood, one count
        // ahead. No comparator/long timer chain follows the counter in one clk.
        (* syn_preserve=1, syn_keep=1 *) reg ms_tick;
        always @(posedge audio_clk or posedge audio_reset)begin
            if(audio_reset)ms_tick<=EC11_MS_CYCLES==1;
            else ms_tick<=encoder_ms_pre_ce;
        end
        assign encoder_ms_ticks[e]=ms_tick;
        ec11_encoder #(.FILTER_CYCLES(EC11_FILTER_CYCLES),.DEBOUNCE_MS(EC11_DEBOUNCE_MS),
            .DOUBLE_MS(EC11_DOUBLE_MS),.LONG_MS(EC11_LONG_MS),.STEPS_PER_DETENT(EC11_STEPS),.REVERSE(EC11_REVERSE[e])) control(
            .clk(audio_clk),.rst(audio_reset),.ms_ce(ms_tick),.a(ec11_a[e]),.b(ec11_b[e]),.sw_n(ec11_sw_n[e]),
            .step_up(encoder_up[e]),.step_down(encoder_down[e]),.single_click(encoder_single[e]),.double_click(encoder_double[e]),
            .clear_stats(encoder_clear[e]),.diagnostic(encoder_diagnostics[e*128+:128]));
    end
    // synthesis translate_off
    always @(posedge audio_clk)if(!audio_reset && encoder_ms_ticks!=={3{encoder_ms_ce}})
        $fatal(1,"Distributed EC11 tick changed millisecond phase");
    // synthesis translate_on
    wire pcb_mute,pcb_muted,pcb_page,pcb_display_visible;
    wire [2591:0] pcb_display;
    wire [159:0] pcb_control,pcb_ref_control;wire pcb_control_valid,pcb_control_update;
    reg [1023:0] pcb_ref_status;wire [1023:0] pcb_ref_live_status,pcb_audio_status;wire pcb_status_valid,pcb_status_update;
    wire [319:0] pcb_audio_trace;wire [35:0] keypad_armed;
    wire [2:0] keypad_data_valid;
    wire aux_action_valid,touch_action_valid;
    wire [5:0] aux_action,touch_action;
    wire ui_action_valid=aux_action_valid || touch_action_valid;
    wire [5:0] ui_action=aux_action_valid?aux_action:touch_action;
    wire more_open,delete_confirm,more_command_valid,more_command_ready,more_info;
    wire [3:0] more_command;
    wire [79:0] service_status,service_audio;wire service_audio_valid,service_update;
    wire [95:0] service_bundle;
    wire [15:0] bt_source_ids,bt_audio_ids;
    ui_more_actions more_controls(audio_clk,audio_reset,menu_mode,ui_action_valid,ui_action,
        more_open,delete_confirm,more_command_valid,more_command_ready,more_command,more_info);
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
    reg bt_flush_d,bt_restore;
    wire effect_cfg_request=cfg_valid || bt_restore;
    always @(posedge audio_clk or posedge audio_reset)begin
        if(audio_reset)begin bt_flush_d<=0;bt_restore<=0;end
        else begin bt_flush_d<=bt_flush;bt_restore<=bt_flush_d && !bt_flush;end
    end
    wire local_score_busy=score_busy && !score_cancelled;
    wire take_bt=bt_inhibit || bt_valid || bt_flush;
    always @(posedge audio_clk or posedge audio_reset)begin
        if(audio_reset)score_cancelled<=0;
        else if(bt_inhibit || bt_valid)score_cancelled<=1;
    end
    if(BT_ENABLE)begin: bluetooth_on
        wire ev_valid,ev_ready;wire [1:0] kind;
        wire [6:0] ident,pitch,velocity;
        wire source_valid,source_ready,source_inhibit,source_reset;
        wire [1:0] source_kind;wire [6:0] source_id,source_pitch,source_velocity;
        wire song_valid,upload_active;wire [1:0] play_state;wire [15:0] total_notes;
        wire [31:0] song_duration,song_crc;
        wire local_valid,local_ready,local_done;wire [1:0] local_command;wire [7:0] local_error;
        wire storage_lock,storage_ready,storage_write,storage_invalidate,storage_import,storage_done;
        wire [11:0] storage_address;wire [63:0] storage_wdata,storage_rdata;
        wire [15:0] storage_count;wire [31:0] storage_crc;wire [7:0] storage_error;
        wire extension_valid,extension_ready,extension_response_valid,extension_response_ready;
        wire [7:0] extension_command;wire [8:0] extension_length;wire [63:0] extension_payload;
        wire [4:0] extension_response_length;wire [159:0] extension_response;
        wire action_valid,action_ready;wire [3:0] action;
        wire channel_reset=pll1_reset || audio_reset;
        reset_sync bt_reset(clk,channel_reset,source_reset);
        (* syn_async_reg=1, async_reg="true" *) reg inhibit_meta,inhibit_sync;
        always @(posedge audio_clk or posedge audio_reset)begin
            if(audio_reset)begin inhibit_meta<=0;inhibit_sync<=0;end
            else begin inhibit_meta<=source_inhibit;inhibit_sync<=inhibit_meta;end
        end
        assign bt_inhibit=inhibit_sync;
        bluetooth_score_link #(.CLOCK_HZ(`REF_HZ),.MAX_NOTES(4096),.MAX_VOICES(16),.LIBRARY_EXTENSION(1)) link(
            .clk(clk),.rst(source_reset),.uart_rx_pin(bt_rx),.uart_tx_pin(bt_tx),
            .event_valid(source_valid),.event_ready(source_ready),.event_kind(source_kind),.event_id(source_id),
            .event_pitch(source_pitch),.event_velocity(source_velocity),.manual_inhibit(source_inhibit),
            .song_valid(song_valid),.upload_active(upload_active),.play_state(play_state),.total_notes(total_notes),.song_duration(song_duration),.song_crc(song_crc),
            .local_valid(local_valid),.local_ready(local_ready),.local_command(local_command),.local_done(local_done),.local_error(local_error),
            .storage_lock(storage_lock),.storage_ready(storage_ready),.storage_write(storage_write),.storage_invalidate(storage_invalidate),
            .storage_address(storage_address),.storage_wdata(storage_wdata),.storage_rdata(storage_rdata),
            .storage_import(storage_import),.storage_count(storage_count),.storage_crc(storage_crc),.storage_done(storage_done),.storage_error(storage_error),
            .extension_valid(extension_valid),.extension_ready(extension_ready),.extension_command(extension_command),.extension_length(extension_length),.extension_payload(extension_payload),
            .extension_response_valid(extension_response_valid),.extension_response_ready(extension_response_ready),.extension_response_length(extension_response_length),.extension_response(extension_response));
        bt_event_cdc #(.WIDTH(4)) local_actions(audio_clk,clk,channel_reset,more_command_valid,more_command_ready,more_command,action_valid,action_ready,action);
        score_services #(.FLASH_WRITES(FLASH_WRITES)) services(.clk(clk),.rst(source_reset),.action_valid(action_valid),.action_ready(action_ready),.action(action),.status(service_status),
            .song_valid(song_valid),.upload_active(upload_active),.play_state(play_state),.total_notes(total_notes),.song_duration(song_duration),.song_crc(song_crc),
            .local_valid(local_valid),.local_ready(local_ready),.local_command(local_command),.local_done(local_done),.local_error(local_error),
            .storage_lock(storage_lock),.storage_ready(storage_ready),.storage_write(storage_write),.storage_invalidate(storage_invalidate),
            .storage_address(storage_address),.storage_wdata(storage_wdata),.storage_rdata(storage_rdata),
            .storage_import(storage_import),.storage_count(storage_count),.storage_crc(storage_crc),.storage_done(storage_done),.storage_error(storage_error),
            .extension_valid(extension_valid),.extension_ready(extension_ready),.extension_command(extension_command),.extension_length(extension_length),.extension_payload(extension_payload),
            .extension_response_valid(extension_response_valid),.extension_response_ready(extension_response_ready),.extension_response_length(extension_response_length),.extension_response(extension_response),
            .flash_cs_n(flash_cs_n),.flash_sck(flash_sck),.flash_mosi(flash_mosi),.flash_miso(flash_miso),.flash_wp_n(flash_wp_n),.flash_hold_n(flash_hold_n));
        // Automatic IDs 0..15; manual keyboard IDs 60..95 remain separate.
        bt_event_cdc #(.WIDTH(23)) events(clk,audio_clk,channel_reset,
            source_valid,source_ready,{source_kind,source_id,source_pitch,source_velocity},
            ev_valid,ev_ready,{kind,ident,pitch,velocity});
        bt_identity_monitor source_id_monitor(clk,source_reset,source_valid,source_ready,source_kind,source_id,bt_source_ids);
        bluetooth_audio_bridge #(.DRAIN_FRAMES(OUTPUT_ENABLE ? (1<<LIMITER_LOG2)+2 : 2)) bridge(.clk(audio_clk),.rst(audio_reset),.frame_ce(frame_ce),
            .event_valid(ev_valid),.event_ready(ev_ready),.event_kind(kind),
            .event_id(ident),.event_pitch(pitch),.event_velocity(velocity),.inhibit(bt_inhibit),
            .note_valid(bt_valid),.note_ready(bt_ready),.note_on(bt_note_on),
            .note_id(bt_note_id),.note_fcw(bt_fcw),.note_velocity(bt_velocity),.flush(bt_flush),
            .selected_timbre(selected_timbre),.note_timbre(bt_timbre),.note_pitch(bt_pitch),.audio_ready(input_ready),.output_flush(bt_output_flush));
    end else begin: bluetooth_off
        assign bt_tx=1;assign bt_inhibit=0;assign bt_valid=0;assign bt_flush=0;assign bt_output_flush=0;
        assign bt_note_on=0;assign bt_note_id=0;assign bt_fcw=0;assign bt_velocity=127;assign bt_pitch=0;assign bt_timbre=0;
        assign service_status=0;assign more_command_ready=1;
        assign bt_source_ids=0;
        assign flash_cs_n=1;assign flash_sck=0;assign flash_mosi=0;assign flash_wp_n=1;assign flash_hold_n=1;
    end
    rgb_status_cdc #(.WIDTH(96)) service_bridge(clk,audio_clk,pll1_reset || audio_reset,
        {bt_source_ids,service_status},service_bundle,service_audio_valid,service_update);
    assign service_audio=service_bundle[79:0];
    bt_identity_monitor audio_id_monitor(audio_clk,audio_reset || bt_flush,
        bt_valid,bt_ready,{1'b0,bt_note_on},bt_note_id,bt_audio_ids);
    assign bt_ready=note_ready && take_bt && !bt_flush;
    // Start the external amplifier only after I2S clocks have crossed two
    // frame boundaries. The existing production mute interval then supplies
    // more than 7.5 ms of digital silence before audio is admitted.
    always @(posedge audio_clk or posedge audio_reset)begin
        if(audio_reset)max_clock_frames<=0;
        else if(frame_ce && max_clock_frames!=2)max_clock_frames<=max_clock_frames+1'b1;
    end
    assign MAX_SD_MODE=!audio_reset && max_clock_frames==2;
    // Retired onboard PT8211/PA pads remain parked low; former debug pads
    // are reassigned to keypad buses and interrupts.
    assign HP_BCK=0;assign HP_WS=0;assign HP_DIN=0;assign PA_EN=0;

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
        .action_valid(touch_action_valid),.action(touch_action),.more_mode(more_open),.ultrasonic_page(ultrasonic_page),.pcb_page(pcb_page));
    // AUX shortcuts stay disabled during touch-board fault diagnosis.
    touch_keyboard_router #(.AUX_ENABLE(KEYPAD_AUX_ENABLE)) menu_keys(.clk(audio_clk),.rst(audio_reset),
        .blocked(menu_mode || take_bt || local_score_busy),.menu_mode(menu_mode),
        .more_mode(more_open),.ultrasonic_page(ultrasonic_page),.snapshot_valid(keypad_snapshot_valid),
        .piano(keys),.aux(auxiliary_keys),.online(keypad_online & keypad_data_valid),.note_keys(note_keys),
        .action_valid(aux_action_valid),.action(aux_action),.qualified_keys(keypad_armed));
    if(LCD_ENABLE)begin: lcd_on
        rgb_display #(.VOICES(`VOICE_COUNT),.TEST_PATTERN(LCD_TEST_PATTERN),
            .PCLK_INVERT(LCD_PCLK_INVERT)) display_driver(
            .ref_clk(clk),.pll_reset(pll1_reset),.audio_clk(audio_clk),.audio_reset(audio_reset),
            .voice_active(voice_active),.voice_held(voice_held),.selected_timbre(selected_timbre),
            .visual_sample_valid(visual_sample_valid),.visual_sample(visual_sample),.visual_notes(visual_notes),
            .latency_valid(latency_valid),.latency_bcd(latency_bcd),
            .ultrasonic_status(ultrasonic_ui),
            .encoder_status({echo_time_bcd,tremolo_edit_rate,echo_edit_strength,effect_mask}),.keypad_online(keypad_online),
            .score_busy(local_score_busy || bt_inhibit),.audio_ready(input_ready),.score_error(score_error),
            .underrun(underrun),.ghost(ghost),.lcd_clk(lcd_clk),.lcd_hs(lcd_hs),
            .lcd_vs(lcd_vs),.lcd_en(lcd_en),.lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b),
            .menu_mode(menu_mode),.effects_enabled(effects_enabled),.effect_mode(effect_mode),
            .echo_percent(echo_percent),.room_percent(room_percent),.depth_percent(depth_percent),
            .volume_percent(volume_percent),.tremolo_rate_hz(tremolo_rate_hz),.touch_enabled(TOUCH_ENABLE!=0),
            .touch_ui_enabled(TOUCH_UI_ENABLE!=0 && touch_audio_valid && touch_audio[70:55]==800 && touch_audio[54:39]==480),.touch_ready_status(touch_audio[38]),.touch_error_status(touch_audio[37]),
            .more_status({voice_held,bt_audio_ids,service_bundle[95:80],more_open,delete_confirm,more_info,service_audio[78:0]}),.pcb_status(pcb_display),.pcb_visible(pcb_display_visible));
    end else begin: lcd_off
        assign pcb_display_visible=0;
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
    timbre_control #(.DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES),.LONG_PRESS_CYCLES(BUTTON_LONG_PRESS_CYCLES),
        .ULTRA_SLEW_CYCLES(ULTRA_SLEW_CYCLES)) timbre_buttons(
        .clk(audio_clk),.rst(audio_reset),.buttons_n(board_buttons_n),
        .encoder_up(encoder_up),.encoder_down(encoder_down),.encoder_single(encoder_single),.encoder_double(encoder_double),
        .effect_mask(effect_mask),.cfg_effect_mask(cfg_effect_mask),.cfg_echo_samples(cfg_echo_samples),
        .echo_edit_strength(echo_edit_strength),.tremolo_edit_rate(tremolo_edit_rate),
        .echo_time_ms(echo_time_ms),.echo_time_bcd(echo_time_bcd),
        .selected(selected_timbre),.effects_enabled(effects_enabled),.effect_mode(effect_mode),
        .ui_action_valid(ui_action_valid),.ui_action(ui_action),.cfg_ready(cfg_ready),
        .menu_mode(menu_mode),.cfg_valid(cfg_valid),.cfg_tremolo_rate_hz(cfg_rate_hz),.echo_wet(echo_wet),.room_wet(room_wet),
        .tremolo_depth(tremolo_depth),.echo_percent(echo_percent),.room_percent(room_percent),
        .depth_percent(depth_percent),.tremolo_rate_hz(tremolo_rate_hz),.volume_percent(volume_percent),
        .ultrasonic_page(ultrasonic_page),.ultrasonic_enabled(ultrasonic_enabled),
        .ultrasonic_sensitivity(ultrasonic_sensitivity),.ultrasonic_min(ultrasonic_min),.ultrasonic_max(ultrasonic_max),
        .ultrasonic_version(ultrasonic_version),.auto_valid(ultrasonic_result_valid && ultrasonic_result[14:12]!=0),
        .auto_version(ultrasonic_result[29:22]),.auto_target(ultrasonic_result[21:15]));
    wire [5:0] diagnostic_leds;
    assign led_n={diagnostic_leds[5],diagnostic_leds[3:0]};
    run_leds #(.STEP_CYCLES(LED_STEP_CYCLES),.DIAG_STEPS(LED_DIAG_STEPS)) status_leds(
        .clk(clk),.audio_ready_async(!audio_reset),.key_active_async(gate),
        .pll1_lock_async(lock1),.pll2_lock_async(lock2),.reset_active_async(rst),.led_n(diagnostic_leds));
    pll_pair clocks(clk,pll1_reset,pll2_reset,mid_clk,audio_clk,lock1,lock2);
    clock_reset #(.LOCK_N(LOCK_N)) reset_control(clk,rst,lock1,lock2,audio_clk,
        pll1_reset,pll2_reset,audio_reset);
    wire [47:0] keypad_ref_keys;
    wire [2:0] keypad_ref_online,keypad_ref_valid,keypad_fault,keypad_report;
    wire [53:0] keypad_snapshot;
    wire [1919:0] keypad_diagnostics;
    wire [395:0] keypad_applied,keypad_observed;
    wire [2:0] keypad_cfg_ready,keypad_cfg_done;wire [23:0] keypad_cfg_error;
    reg [7:0] command_seen,command_ack,command_result,clear_seen;
    reg queued,inflight;reg [1:0] command_board;reg [131:0] command_data;
    localparam integer PCW=$clog2(PCB_COMMAND_TIMEOUT_CYCLES+1);
    reg [PCW-1:0] command_timeout;
    reg [2:0] keypad_clear;
    wire [2:0] keypad_cfg_valid=(queued && command_timeout<PCB_COMMAND_TIMEOUT_CYCLES-1) ? (3'b001<<command_board) : 3'd0;
    wire [1:0] diagnostic_board=pcb_ref_control[1:0]<3 ? pcb_ref_control[1:0] : 2'd0;
    assign pcb_ref_live_status={96'd0,command_result,command_ack,keypad_ref_valid,keypad_ref_online,
        diagnostic_board,keypad_observed[diagnostic_board*132+:132],
        keypad_applied[diagnostic_board*132+:132],keypad_diagnostics[diagnostic_board*640+:640]};
    reg [15:0] pcb_diag_counter;
    always @(posedge clk or posedge ultrasonic_ref_reset)begin
        if(ultrasonic_ref_reset)begin pcb_ref_status<=0;pcb_diag_counter<=0;end
        else if(pcb_diag_counter==49999 ||
            pcb_ref_live_status[927:904]!=pcb_ref_status[927:904])begin
            pcb_ref_status<=pcb_ref_live_status;pcb_diag_counter<=0;
        end else pcb_diag_counter<=pcb_diag_counter+1'b1;
    end
    rgb_status_cdc #(.WIDTH(160)) pcb_command_bridge(audio_clk,clk,ultrasonic_reset,
        pcb_control,pcb_ref_control,pcb_control_valid,pcb_control_update);
    rgb_status_cdc #(.WIDTH(1024)) pcb_diagnostic_bridge(clk,audio_clk,ultrasonic_reset,
        pcb_ref_status,pcb_audio_status,pcb_status_valid,pcb_status_update);
    always @(posedge clk or posedge ultrasonic_ref_reset)begin
        if(ultrasonic_ref_reset)begin command_seen<=0;command_ack<=0;command_result<=0;clear_seen<=0;
            queued<=0;inflight<=0;command_board<=0;command_data<=0;command_timeout<=0;keypad_clear<=0;end
        else begin
            keypad_clear<=0;
            if(pcb_control_valid && pcb_ref_control[151:144]!=clear_seen)begin
                clear_seen<=pcb_ref_control[151:144];
                if(pcb_ref_control[153:152]<3)keypad_clear[pcb_ref_control[153:152]]<=1;
            end
            if(!queued && !inflight && pcb_control_valid && pcb_ref_control[11:4]!=command_seen)begin
                command_seen<=pcb_ref_control[11:4];command_board<=pcb_ref_control[3:2];
                command_data<=pcb_ref_control[143:12];queued<=1;command_timeout<=0;
            end else if(queued || inflight)begin
                if(command_timeout==PCB_COMMAND_TIMEOUT_CYCLES-1)begin
                    queued<=0;inflight<=0;command_ack<=command_seen;command_result<=8'h31;
                end else begin
                    command_timeout<=command_timeout+1'b1;
                    if(queued && keypad_cfg_ready[command_board])begin queued<=0;inflight<=1;end
                    if(inflight && keypad_cfg_done[command_board])begin
                        inflight<=0;command_ack<=command_seen;command_result<=keypad_cfg_error[command_board*8+:8];
                    end
                end
            end
        end
    end
    for(genvar b=0;b<3;b=b+1)begin: touch_keyboards
        aip5916_keyboard #(.BOOT_CYCLES(KEYPAD_BOOT_CYCLES),.POLL_CYCLES(KEYPAD_POLL_CYCLES),
            .I2C_HALF_CYCLES(KEYPAD_I2C_HALF),.TIMEOUT_CYCLES(KEYPAD_TIMEOUT_CYCLES),
            .RETRY_CYCLES(KEYPAD_RETRY_CYCLES),.STALE_CYCLES(KEYPAD_STALE_CYCLES)) reader(
            .clk(clk),.rst(ultrasonic_ref_reset),.intr_n(keypad_int_n[b]),
            .scl(keypad_scl[b]),.sda(keypad_sda[b]),.keys(keypad_ref_keys[b*16+:16]),
            .online(keypad_ref_online[b]),.report(keypad_report[b]),.fault(keypad_fault[b]),
            .cfg_valid(keypad_cfg_valid[b]),.cfg_data(command_data),.cfg_ready(keypad_cfg_ready[b]),
            .cfg_done(keypad_cfg_done[b]),.cfg_error(keypad_cfg_error[b*8+:8]),.data_valid(keypad_ref_valid[b]),
            .applied_config(keypad_applied[b*132+:132]),.observed_config(keypad_observed[b*132+:132]),
            .diagnostic(keypad_diagnostics[b*640+:640]),.clear_stats(keypad_clear[b]));
        assign keys[b*12+:12]=keypad_snapshot[b*16+:12];
        assign auxiliary_keys[b*4+:4]=keypad_snapshot[b*16+12+:4];
    end
    rgb_status_cdc #(.WIDTH(54)) keypad_bridge(clk,audio_clk,ultrasonic_reset,
        {keypad_ref_online,keypad_ref_valid,keypad_ref_keys},keypad_snapshot,keypad_snapshot_valid,keypad_snapshot_update);
    assign keypad_online=keypad_snapshot[53:51];
    assign keypad_data_valid=keypad_snapshot[50:48];
    key_note_events #(.KEYS(36)) key_events(
        .clk(audio_clk),.rst(audio_reset || take_bt || local_score_busy),
        .enabled(input_ready && !take_bt && !local_score_busy),.keys(note_keys),
        .note_ready(note_ready && !take_bt && !local_score_busy),
        .note_valid(key_valid),.note_on(key_on),.note_id(key_id),.note_fcw(key_fcw),
        .gate(key_gate),.last_key(last_key),.selected_timbre(selected_timbre),.note_timbre(key_timbre));
    synth_core #(.STEREO_ENABLE(STEREO_ENABLE),.VISUAL_KEYS(36),.OUTPUT_ENABLE(OUTPUT_ENABLE),.OUTPUT_GAIN(OUTPUT_GAIN),.LIMITER_LOG2(LIMITER_LOG2),.LIMITER_HOLD_SAMPLES(LIMITER_HOLD_SAMPLES),
        .MUTE(MUTE),.FADE(FADE),.ATTACK(ATTACK),.DECAY(DECAY),
        .SUSTAIN(SUSTAIN),.RELEASE(RELEASE)) sound(
        .clk(audio_clk),.rst(audio_reset),.note_valid(note_valid),.note_on(note_on),
        .note_pitch(take_bt ? bt_pitch : note_id),.volume_percent(volume_percent),.flush(bt_flush),.output_flush(bt_output_flush),.velocity_valid(take_bt),.note_velocity(bt_velocity),
        .note_id(note_id),.note_fcw(note_fcw),.note_timbre(event_timbre),.effects_enable(effects_enabled),.effect_mode(effect_mode),
        .effect_mask(cfg_effect_mask),.effect_echo_samples(cfg_echo_samples),
        .effect_cfg_valid(effect_cfg_request),.effect_echo_wet(echo_wet),.effect_room_wet(room_wet),
        .effect_tremolo_depth(tremolo_depth),.effect_tremolo_rate_hz(cfg_rate_hz),
        .effect_cfg_ready(cfg_ready),.effect_cfg_applied(cfg_applied),
        .bck(MAX_BCLK),.ws(MAX_LRCLK),.din(MAX_DIN),.pa_enable(synth_pa_enable),.underrun(underrun),
        .frame_ce(frame_ce),.note_ready(note_ready),.input_ready(input_ready),
        .gate(gate),.voice_active(voice_active),.voice_held(voice_held),.envelope_level(envelope_level),
        .visual_sample_valid(visual_sample_valid),.visual_sample(visual_sample),.visual_notes(visual_notes),
        .latency_valid(latency_valid),.latency_bcd(latency_bcd),.debug_mute(pcb_mute),.debug_muted(pcb_muted));
    assign pcb_audio_trace={28'd0,keypad_armed,16'd0,visual_sample,20'd0,note_fcw,7'd0,note_id,voice_active,voice_held,
        echo_time_ms,volume_percent,tremolo_rate_hz,depth_percent,room_percent,echo_percent,
        tremolo_edit_rate,echo_edit_strength,effect_mask,input_ready,underrun,visual_sample_valid,
        cfg_applied,cfg_ready,effect_cfg_request,menu_mode,local_score_busy,take_bt,note_ready,note_on,note_valid,note_keys};
    pcb_debug_ui pcb_controls(.clk(audio_clk),.rst(audio_reset),.ms_ce(encoder_ms_ticks[0]),
        .menu_mode(menu_mode),.mute_ack(pcb_muted),.action_valid(touch_action_valid),.action(touch_action),
        .hardware_valid(pcb_status_valid),.hardware(pcb_audio_status),.encoder_diag(encoder_diagnostics),
        .encoder_events({encoder_double,encoder_single,encoder_down,encoder_up}),.audio_status(pcb_audio_trace),
        .mute_request(pcb_mute),.page_active(pcb_page),.control(pcb_control),.encoder_clear(encoder_clear),.display(pcb_display),.display_visible(pcb_display_visible));
endmodule


