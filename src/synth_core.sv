`timescale 1ns/1ps
`include "config/synth_config.svh"
// Generic note-event synthesis; physical keyboard logic stays in its adapter.
module synth_core #(
    parameter integer MASTER_GAIN_ENABLE=0,MASTER_GAIN_SLEW_SAMPLES=4,
    VOICES=`VOICE_COUNT,MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES,
    ATTACK=`ADSR_ATTACK_FRAMES,DECAY=`ADSR_DECAY_FRAMES,
    SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES,
    DELAY_SAMPLES=7200,ROOM_D0=1499,ROOM_D1=1601,ROOM_D2=1867,ROOM_D3=2053)(
    input wire clk,rst,note_valid,note_on,input wire [6:0] note_id,input wire [31:0] note_fcw,
    output wire note_ready,input_ready,bck,ws,din,pa_enable,underrun,frame_ce,gate,
    output wire [VOICES-1:0] voice_active,voice_held,output reg [16:0] envelope_level,input wire [2:0] note_timbre,input wire effects_enable,input wire [1:0] effect_mode,
    input wire effect_cfg_valid,input wire [8:0] effect_echo_wet,effect_room_wet,effect_tremolo_depth,
    input wire [3:0] effect_tremolo_rate_hz,output wire effect_cfg_ready,effect_cfg_applied,
    output wire visual_sample_valid,output wire signed [15:0] visual_sample,
    output reg [15:0] visual_notes,
    input wire [8:0] master_gain);
    localparam integer INDEX_W=VOICES>1?$clog2(VOICES):1;
    localparam integer RENDER_BUDGET=32+16*VOICES;
    localparam integer CYCLE_W=$clog2(RENDER_BUDGET+1);
    wire rise_ce,fall_ce;
    wire [4:0] bit_index;
    wire [16:0] startup_level;
    wire [VOICES-1:0] voice_start,voice_stop,voice_restart;
    wire [VOICES*32-1:0] voice_fcw;
    wire [VOICES*7-1:0] voice_ids;
    wire [16:0] voice_level[0:VOICES-1];
    wire [VOICES*3-1:0] voice_timbres;
    reg [VOICES*3-1:0] frame_timbres;
    reg render_busy;
    reg [CYCLE_W-1:0] render_cycle;
    reg [VOICES*32-1:0] frame_fcw;
    reg [VOICES-1:0] frame_restart;
    wire in_slots=render_busy && render_cycle>=16 && render_cycle<16+16*VOICES;
    wire [INDEX_W-1:0] selected_voice=in_slots?((render_cycle >> 4)-1'b1):{INDEX_W{1'b0}};
    wire dds_ce=in_slots && render_cycle[3:0]==0;
    wire signed [15:0] raw_sample;
    wire raw_valid,gain_valid,mix_valid,ready;
    wire effect_ready,effect_valid;
    wire signed [15:0] effect_sample,output_sample;
    wire output_valid;
    wire [8:0] master_gain_current;
    wire [VOICES*32-1:0] phase;
    reg [33:0] level_product;
    reg [16:0] combined_level;
    reg gain_request,first_sample,last_sample;
    reg [INDEX_W-1:0] sample_voice;
    wire signed [`VOICE_W-1:0] gain_sample;
    wire signed [15:0] mix_sample;
    wire [15:0] frame_l,frame_r;
    // Monitor only: register context selection before decoding the note bit.
    // Audio rendering and allocator handshakes are not delayed.
    reg [15:0] note_scan;
    reg note_pending,monitor_held,monitor_first,monitor_last;
    reg [6:0] monitor_id;
    wire [15:0] note_bit=(monitor_held && monitor_id>=60 && monitor_id<76)
        ? (16'b1 << (monitor_id-7'd60)) : 16'd0;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            note_scan<=0;visual_notes<=0;note_pending<=0;monitor_held<=0;
            monitor_id<=0;monitor_first<=0;monitor_last<=0;
        end else begin
            note_pending<=dds_ce;
            if(dds_ce)begin
                monitor_id<=voice_ids[selected_voice*7+:7];
                monitor_held<=voice_held[selected_voice];
                monitor_first<=selected_voice==0;
                monitor_last<=selected_voice==VOICES-1;
            end
            if(note_pending)begin
                note_scan<=monitor_first ? note_bit : note_scan | note_bit;
                if(monitor_last)visual_notes<=monitor_first ? note_bit : note_scan | note_bit;
            end
        end
    end
    assign visual_sample_valid=effect_valid;
    assign visual_sample=effect_sample;
    audio_timing timing(clk,rst,bck,rise_ce,fall_ce,frame_ce,bit_index);
    startup_envelope #(.MUTE(MUTE),.FADE(FADE)) startup(clk,rst,frame_ce,input_ready,startup_level);
    assign pa_enable=input_ready;
    assign gate=|voice_held;
    // Freeze ownership while rendering; external producers retain valid/data.
    voice_allocator #(.VOICES(VOICES)) allocator(
        .clk(clk),.rst(rst),.enabled(input_ready && !render_busy),.frame_ce(frame_ce),
        .note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(note_fcw),
        .voice_active(voice_active),.note_ready(note_ready),.voice_start(voice_start),
        .voice_stop(voice_stop),.voice_restart(voice_restart),.voice_held(voice_held),
        .voice_fcw(voice_fcw),.voice_ids(voice_ids),
        .note_timbre(note_timbre),.voice_timbres(voice_timbres));
    for(genvar v=0;v<VOICES;v=v+1)begin: voices
        instrument_envelope #(.ATTACK(ATTACK),.DECAY(DECAY),.SUSTAIN(SUSTAIN),.RELEASE(RELEASE)) envelope(
            .clk(clk),.rst(rst),.sample_ce(frame_ce),.note_on(voice_start[v]),.note_off(voice_stop[v]),
            .level(voice_level[v]),.active(voice_active[v]),.restart(voice_restart[v]),.timbre(voice_timbres[v*3+:3]));
    end
    dds_sine #(.VOICES(VOICES)) dds(.clk(clk),.rst(rst),.sample_ce(dds_ce),
        .fcw(frame_fcw[selected_voice*32+:32]),.sample(raw_sample),.valid(raw_valid),
        .phase(phase),.restart(frame_restart[selected_voice]),.voice_index(selected_voice),.timbre(frame_timbres[selected_voice*3+:3]));
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            render_busy<=0;render_cycle<=0;frame_fcw<=0;frame_restart<=0;frame_timbres<=0;
            level_product<=0;combined_level<=0;gain_request<=0;
            first_sample<=0;last_sample<=0;sample_voice<=0;
        end else begin
            gain_request<=raw_valid;
            if(raw_valid)combined_level<=level_product[32:16];
            if(frame_ce)begin
                render_busy<=1;render_cycle<=0;
                frame_fcw<=voice_fcw;frame_restart<=voice_restart;frame_timbres<=voice_timbres;
            end else if(render_busy)begin
                if(render_cycle==RENDER_BUDGET-2)render_busy<=0;
                else render_cycle<=render_cycle+1'b1;
            end
            if(dds_ce)begin
                level_product<=voice_level[selected_voice]*startup_level;
                sample_voice<=selected_voice;
                first_sample<=selected_voice==0;
                last_sample<=selected_voice==VOICES-1;
            end
        end
    end
    tone_gain #(.OUTPUT_W(`VOICE_W)) gain(clk,rst,gain_request,raw_sample,combined_level,gain_valid,gain_sample);
    voice_mixer mixer(clk,rst,gain_valid,gain_sample,first_sample,last_sample,mix_valid,mix_sample);
    always @* begin
        envelope_level=0;
        for(integer v=0;v<VOICES;v=v+1)
            if(voice_level[v]>envelope_level)envelope_level=voice_level[v];
    end
    audio_effects #(.DELAY_SAMPLES(DELAY_SAMPLES),.D0(ROOM_D0),.D1(ROOM_D1),.D2(ROOM_D2),.D3(ROOM_D3)) effect(
        .clk(clk),.rst(rst),.enable(effects_enable),.mode(effect_mode),.in_valid(mix_valid),.in_sample(mix_sample),
        .in_ready(effect_ready),.out_valid(effect_valid),.out_sample(effect_sample),
        .cfg_valid(effect_cfg_valid),.cfg_echo_wet(effect_echo_wet),.cfg_room_wet(effect_room_wet),
        .cfg_tremolo_depth(effect_tremolo_depth),.cfg_tremolo_rate_hz(effect_tremolo_rate_hz),
        .cfg_ready(effect_cfg_ready),.cfg_applied(effect_cfg_applied));
    // Optional post-effect expression gain; core callers default to exact bypass.
    // The existing visual tap remains pre-master-gain; UI is unchanged.
    if(MASTER_GAIN_ENABLE)begin: master_on
        audio_master_gain #(.SAMPLE_BITS(16),.SLEW_SAMPLES(MASTER_GAIN_SLEW_SAMPLES)) expression(
            .clk(clk),.rst(rst),.gain_target(master_gain),.sample_ce(effect_valid),
            .sample_in(effect_sample),.sample_out(output_sample),.out_valid(output_valid),
            .gain_current(master_gain_current));
    end else begin: master_off
        assign output_sample=effect_sample;assign output_valid=effect_valid;
        assign master_gain_current=9'd256;
    end
    frame_buffer buffer(clk,rst,frame_ce,output_valid,ready,output_sample,output_sample,frame_l,frame_r,underrun);
    i2s_tx tx(clk,rst,fall_ce,bit_index,frame_l,frame_r,ws,din);
    // synthesis translate_off
    initial if(VOICES<1 || VOICES>32 || RENDER_BUDGET>=`FRAME_CYCLES)$fatal(1,"Invalid render budget");
    always @(posedge clk)if(!rst)begin
        if(frame_ce && render_busy)$fatal(1,"Frame renderer missed deadline");
        if(mix_valid && !effect_ready)$fatal(1,"Effect rejected render result");
        if(output_valid && !ready)$fatal(1,"Frame buffer rejected post-effect/master result");
    end
    // synthesis translate_on
endmodule


