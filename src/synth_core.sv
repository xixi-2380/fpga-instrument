`timescale 1ns/1ps
`include "config/synth_config.svh"
// Generic note-event synthesis. No matrix dimensions, key map or scan logic.
module synth_core #(
    parameter integer VOICES=`VOICE_COUNT,MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES,
    ATTACK=`ADSR_ATTACK_FRAMES,DECAY=`ADSR_DECAY_FRAMES,
    SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES)(
    input wire clk,rst,note_valid,note_on,input wire [6:0] note_id,input wire [31:0] note_fcw,
    output wire note_ready,input_ready,bck,ws,din,pa_enable,underrun,frame_ce,gate,
    output wire [VOICES-1:0] voice_active,voice_held,output reg [16:0] envelope_level);
    wire rise_ce,fall_ce;
    wire [4:0] bit_index;
    wire [16:0] startup_level;
    wire [VOICES-1:0] voice_start,voice_stop,voice_restart,raw_valid,gain_valid;
    wire [VOICES*32-1:0] voice_fcw;
    wire [VOICES*7-1:0] voice_ids;
    wire [16:0] voice_level [0:VOICES-1];
    wire [VOICES*`VOICE_W-1:0] voice_samples;
    wire mix_valid,ready;
    wire signed [15:0] mix_sample;
    wire [15:0] frame_l,frame_r;
    audio_timing timing(clk,rst,bck,rise_ce,fall_ce,frame_ce,bit_index);
    startup_envelope #(.MUTE(MUTE),.FADE(FADE)) startup(clk,rst,frame_ce,input_ready,startup_level);
    assign pa_enable=input_ready;
    assign gate=|voice_held;
    voice_allocator #(.VOICES(VOICES)) allocator(
        .clk(clk),.rst(rst),.enabled(input_ready),.frame_ce(frame_ce),
        .note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(note_fcw),
        .voice_active(voice_active),.note_ready(note_ready),.voice_start(voice_start),
        .voice_stop(voice_stop),.voice_restart(voice_restart),.voice_held(voice_held),
        .voice_fcw(voice_fcw),.voice_ids(voice_ids));
    for(genvar v=0;v<VOICES;v=v+1)begin: voices
        wire signed [15:0] raw_sample;
        wire [31:0] phase;
        wire [33:0] level_product=voice_level[v]*startup_level;
        reg [16:0] combined_level;
        reg gain_request;
        adsr_envelope #(.ATTACK(ATTACK),.DECAY(DECAY),.SUSTAIN(SUSTAIN),.RELEASE(RELEASE)) envelope(
            .clk(clk),.rst(rst),.sample_ce(frame_ce),.note_on(voice_start[v]),.note_off(voice_stop[v]),
            .level(voice_level[v]),.active(voice_active[v]),.restart(voice_restart[v]));
        dds_sine dds(.clk(clk),.rst(rst),.sample_ce(frame_ce),.fcw(voice_fcw[v*32+:32]),
            .sample(raw_sample),.valid(raw_valid[v]),.phase(phase),.restart(voice_restart[v]));
        always @(posedge clk or posedge rst)begin
            if(rst)begin combined_level<=0;gain_request<=0;end
            else begin
                gain_request<=raw_valid[v];
                if(raw_valid[v])combined_level<=level_product[32:16];
            end
        end
        tone_gain #(.OUTPUT_W(`VOICE_W)) gain(clk,rst,gain_request,raw_sample,combined_level,
            gain_valid[v],voice_samples[v*`VOICE_W+:`VOICE_W]);
    end
    always @* begin
        envelope_level=0;
        for(integer v=0;v<VOICES;v=v+1)
            if(voice_level[v]>envelope_level)envelope_level=voice_level[v];
    end
    voice_mixer #(.VOICES(VOICES)) mixer(clk,rst,&gain_valid,voice_samples,mix_valid,mix_sample);
    frame_buffer buffer(clk,rst,frame_ce,mix_valid,ready,mix_sample,mix_sample,frame_l,frame_r,underrun);
    pt8211_tx tx(clk,rst,fall_ce,bit_index,frame_l,frame_r,ws,din);
endmodule
