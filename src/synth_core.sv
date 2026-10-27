`timescale 1ns/1ps
`include "config/synth_config.svh"
// Generic note-event synthesis; physical keyboard logic stays in its adapter.
module synth_core #(
    parameter integer OUTPUT_ENABLE=1,OUTPUT_GAIN=24,LIMITER_LOG2=6,
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
    input wire flush,input wire velocity_valid,input wire [6:0] note_velocity,
    input wire [6:0] volume_percent,input wire [6:0] note_pitch,input wire output_flush,
    output wire latency_valid,output wire [19:0] latency_bcd);
    wire engine_reset=rst || (flush===1'b1);
    // Legacy standalone callers can omit output_flush; top distinguishes an
    // Natural end drains before urgent output clear. Clocks/startup never use these resets.
    wire output_reset=rst || (output_flush===1'b1) ||
        ((output_flush!==1'b0 && output_flush!==1'b1) && (flush===1'b1));
    // Live automatic metadata; released physical voices retain their own gain.
    reg [8:0] velocities[0:15];
    reg [6:0] automatic_pitch[0:15];
    reg [8:0] velocity_scale;
    function automatic [8:0] velocity_gain(input [6:0] value);
    // Exact rounded value*256/127 for all 128 MIDI velocities.
    begin velocity_gain={1'b0,value,1'b0}+
        (value>=96 ? 9'd2 : value>=32 ? 9'd1 : 9'd0);end endfunction
    always @(posedge clk or posedge engine_reset)begin
        if(engine_reset)begin
            for(integer a=0;a<16;a=a+1)begin velocities[a]<=256;automatic_pitch[a]<=a;end
        end else if(note_valid && note_ready && note_on && note_id<16)begin
            for(integer a=0;a<16;a=a+1)if(note_id==a)begin
                velocities[a]<=velocity_valid===1'b1 ? velocity_gain(note_velocity) : 9'd256;
                automatic_pitch[a]<=velocity_valid===1'b1 ? note_pitch : note_id;
            end
        end
    end
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
    reg [8:0] voice_velocity[0:VOICES-1];
    reg [VOICES-1:0] frame_start;
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
    wire signed [15:0] effect_sample;
    wire [VOICES*32-1:0] phase;
    reg [33:0] level_product;
    reg [16:0] selected_level,selected_startup;
    wire [25:0] scaled_level=level_product[32:16]*velocity_scale;
    reg [16:0] combined_level;
    reg gain_request,first_sample,last_sample;
    reg [INDEX_W-1:0] sample_voice;
    wire signed [`VOICE_W-1:0] gain_sample;
    wire signed [15:0] mix_sample;
    wire [15:0] frame_l,frame_r;
    reg [15:0] note_scan;
    // Metadata read, automatic lookup, then bitmap update occupy separate clocks.
    // Avoid a render-counter -> context mux -> dynamic shift -> bitmap path.
    reg [6:0] scanning_id,scanning_pitch;
    reg scanning_held,scanning_first,scanning_last;
    wire [15:0] note_bit=(scanning_held && scanning_pitch>=60 && scanning_pitch<76) ? (16'b1 << (scanning_pitch-7'd60)) : 16'd0;
    always @(posedge clk or posedge engine_reset)begin
        if(engine_reset)begin note_scan<=0;visual_notes<=0;scanning_id<=0;scanning_pitch<=0;scanning_held<=0;scanning_first<=0;scanning_last<=0;end
        else begin
            if(dds_ce)begin
                scanning_id<=voice_ids[selected_voice*7+:7];scanning_held<=voice_held[selected_voice];
                scanning_first<=selected_voice==0;scanning_last<=selected_voice==VOICES-1;
            end
            if(in_slots && render_cycle[3:0]==1)scanning_pitch<=scanning_id<16 ? automatic_pitch[scanning_id[3:0]] : scanning_id;
            if(in_slots && render_cycle[3:0]==2)begin
                if(scanning_first)note_scan<=note_bit;else note_scan<=note_scan | note_bit;
                if(scanning_last)visual_notes<=scanning_first ? note_bit : note_scan | note_bit;
            end
        end
    end
    wire output_valid;wire signed [15:0] output_sample;
    wire limited_valid;wire signed [15:0] limited_sample;
    wire [16:0] render_tag,limited_tag;
    reg [16:0] volume_product_tag,volume_output_tag,pending_tag,serial_tag;
    reg tag_pending_valid;
    audio_latency_meter #(.CLOCK_HZ(`AUDIO_HZ)) latency_meter(
        .clk(clk),.rst(rst),.cancel(output_reset),.note_accept(note_valid && note_ready && note_on),.note_id(note_id),
        .frame_ce(frame_ce),.voice_valid(gain_valid),.voice_id(voice_ids[sample_voice*7+:7]),
        .serial_complete(rise_ce && bit_index==16),.serial_tag(serial_tag),
        .render_tag(render_tag),.latency_valid(latency_valid),.latency_bcd(latency_bcd));
    wire limiter_ready;wire [16:0] limiter_gain;wire limiter_clipped;
    generate if(OUTPUT_ENABLE)begin: output_conditioning
        reg signed [15:0] staged_sample;reg staged_valid;reg [16:0] staged_tag;
        // Capture each completed render; clock the delay line at every actual
        // sample boundary, including zero frames during a soft engine clear.
        always @(posedge clk or posedge output_reset)begin
            if(output_reset)begin staged_sample<=0;staged_valid<=0;staged_tag<=0;end
            else begin
                if(frame_ce)begin staged_valid<=0;staged_tag<=0;end
                if(effect_valid && !engine_reset)begin staged_sample<=effect_sample;staged_valid<=1;staged_tag<=render_tag;end
            end
        end
        audio_limiter #(.WINDOW_LOG2(LIMITER_LOG2),.PRE_GAIN(OUTPUT_GAIN)) limiter(
            clk,output_reset,frame_ce,staged_valid?staged_sample:16'sd0,
            limiter_ready,limited_valid,limited_sample,limiter_gain,limiter_clipped,staged_valid?staged_tag:17'd0,limited_tag);
    end else begin: output_bypass
        assign limited_valid=effect_valid;assign limited_sample=effect_sample;
        assign limited_tag=render_tag;
        assign limiter_ready=1;assign limiter_gain=65536;assign limiter_clipped=0;
    end endgenerate
    // Urgent clears cancel PCM/valid only; the user's gain/ramp survives.
    master_volume volume_control(clk,rst,limited_valid,limited_sample,volume_percent,output_valid,output_sample,output_reset);
    // Mirror valid/PCM timing through volume, pending frame and serializer.
    always @(posedge clk or posedge output_reset)begin
        if(output_reset)begin volume_product_tag<=0;volume_output_tag<=0;pending_tag<=0;serial_tag<=0;tag_pending_valid<=0;end
        else begin
            volume_product_tag<=limited_valid ? limited_tag : 17'd0;
            volume_output_tag<=volume_product_tag;
            if(frame_ce)begin serial_tag<=tag_pending_valid ? pending_tag : 17'd0;tag_pending_valid<=0;end
            if(output_valid && ready)begin pending_tag<=volume_output_tag;tag_pending_valid<=1;end
        end
    end
    assign visual_sample_valid=output_valid;
    assign visual_sample=output_sample;
    audio_timing timing(clk,rst,bck,rise_ce,fall_ce,frame_ce,bit_index);
    startup_envelope #(.MUTE(MUTE),.FADE(FADE)) startup(clk,rst,frame_ce,input_ready,startup_level);
    assign pa_enable=input_ready;
    assign gate=|voice_held;
    // Freeze ownership while rendering; external producers retain valid/data.
    voice_allocator #(.VOICES(VOICES),.AUTOMATIC_IDS(16)) allocator(
        .clk(clk),.rst(engine_reset),.enabled(input_ready && !render_busy),.frame_ce(frame_ce),
        .note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(note_fcw),
        .voice_active(voice_active),.note_ready(note_ready),.voice_start(voice_start),
        .voice_stop(voice_stop),.voice_restart(voice_restart),.voice_held(voice_held),
        .voice_fcw(voice_fcw),.voice_ids(voice_ids),
        .note_timbre(note_timbre),.voice_timbres(voice_timbres));
    for(genvar v=0;v<VOICES;v=v+1)begin: voices
        instrument_envelope #(.ATTACK(ATTACK),.DECAY(DECAY),.SUSTAIN(SUSTAIN),.RELEASE(RELEASE),.PRECALC(1)) envelope(
            .clk(clk),.rst(engine_reset),.sample_ce(frame_ce),.note_on(voice_start[v]),.note_off(voice_stop[v]),
            .level(voice_level[v]),.active(voice_active[v]),.restart(voice_restart[v]),.timbre(voice_timbres[v*3+:3]));
    end
    dds_sine #(.VOICES(VOICES)) dds(.clk(clk),.rst(engine_reset),.sample_ce(dds_ce),
        .fcw(frame_fcw[selected_voice*32+:32]),.sample(raw_sample),.valid(raw_valid),
        .phase(phase),.restart(frame_restart[selected_voice]),.voice_index(selected_voice),.timbre(frame_timbres[selected_voice*3+:3]));
    always @(posedge clk or posedge engine_reset)begin
        if(engine_reset)begin
            render_busy<=0;render_cycle<=0;frame_fcw<=0;frame_restart<=0;frame_timbres<=0;frame_start<=0;
            for(integer v=0;v<VOICES;v=v+1)voice_velocity[v]<=256;
            selected_level<=0;selected_startup<=0;level_product<=0;combined_level<=0;gain_request<=0;
            first_sample<=0;last_sample<=0;sample_voice<=0;velocity_scale<=256;
        end else begin
            // Context selection and multiplication occupy separate clocks.
            gain_request<=in_slots && render_cycle[3:0]==4;
            if(in_slots && render_cycle[3:0]==1)level_product<=selected_level*selected_startup;
            if(in_slots && render_cycle[3:0]==3)combined_level<=scaled_level[24:8];
            if(frame_ce)begin
                render_busy<=1;render_cycle<=0;
                frame_fcw<=voice_fcw;frame_restart<=voice_restart;frame_timbres<=voice_timbres;frame_start<=voice_start;
            end else if(render_busy)begin
                if(render_cycle==RENDER_BUDGET-2)render_busy<=0;
                else render_cycle<=render_cycle+1'b1;
            end
            if(dds_ce)begin
                selected_level<=voice_level[selected_voice];selected_startup<=startup_level;
                sample_voice<=selected_voice;
                first_sample<=selected_voice==0;
                last_sample<=selected_voice==VOICES-1;
            end
            if(in_slots && render_cycle[3:0]==1)begin
                // One shared lookup, at the same render stage as before.
                // A recycled scheduler ID cannot change an old release gain.
                if(frame_start[selected_voice])begin
                    velocity_scale<=scanning_id<16 ? velocities[scanning_id[3:0]] : 9'd256;
                    voice_velocity[selected_voice]<=scanning_id<16 ? velocities[scanning_id[3:0]] : 9'd256;
                end else velocity_scale<=voice_velocity[selected_voice];
            end
        end
    end
    tone_gain #(.OUTPUT_W(`VOICE_W)) gain(clk,engine_reset,gain_request,raw_sample,combined_level,gain_valid,gain_sample);
    voice_mixer mixer(clk,engine_reset,gain_valid,gain_sample,first_sample,last_sample,mix_valid,mix_sample);
    always @* begin
        envelope_level=0;
        for(integer v=0;v<VOICES;v=v+1)
            if(voice_level[v]>envelope_level)envelope_level=voice_level[v];
    end
    audio_effects #(.DELAY_SAMPLES(DELAY_SAMPLES),.D0(ROOM_D0),.D1(ROOM_D1),.D2(ROOM_D2),.D3(ROOM_D3)) effect(
        .clk(clk),.rst(engine_reset),.enable(effects_enable),.mode(effect_mode),.in_valid(mix_valid),.in_sample(mix_sample),
        .in_ready(effect_ready),.out_valid(effect_valid),.out_sample(effect_sample),
        .cfg_valid(effect_cfg_valid),.cfg_echo_wet(effect_echo_wet),.cfg_room_wet(effect_room_wet),
        .cfg_tremolo_depth(effect_tremolo_depth),.cfg_tremolo_rate_hz(effect_tremolo_rate_hz),
        .cfg_ready(effect_cfg_ready),.cfg_applied(effect_cfg_applied));
    frame_buffer buffer(clk,OUTPUT_ENABLE?output_reset:engine_reset,frame_ce,output_valid,ready,output_sample,output_sample,frame_l,frame_r,underrun);
    i2s_tx tx(clk,rst,fall_ce,bit_index,frame_l,frame_r,ws,din);
    // synthesis translate_off
    initial if(VOICES<1 || VOICES>32 || RENDER_BUDGET>=`FRAME_CYCLES)$fatal(1,"Invalid render budget");
    always @(posedge clk)if(!rst)begin
        if(frame_ce && render_busy)$fatal(1,"Frame renderer missed deadline");
        if(mix_valid && !effect_ready)$fatal(1,"Effect rejected render result");
        if(output_valid && !ready)$fatal(1,"Frame buffer rejected effect result");
    end
    // synthesis translate_on
endmodule


