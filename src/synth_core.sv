`timescale 1ns/1ps
`include "config/synth_config.svh"
// Generic note-event synthesis; physical keyboard logic stays in its adapter.
module synth_core #(
    parameter integer SHARED_ENVELOPE_PRECALC=0,PERFORMANCE_ENABLE=0,STEREO_ENABLE=0,SUSTAIN_ENABLE=0,VISUAL_KEYS=16,LIMITER_HOLD_SAMPLES=240,OUTPUT_ENABLE=1,OUTPUT_GAIN=24,LIMITER_LOG2=6,
    VOICES=`VOICE_COUNT,MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES,
    ATTACK=`ADSR_ATTACK_FRAMES,DECAY=`ADSR_DECAY_FRAMES,
    SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES,
    DELAY_SAMPLES=7200,ROOM_D0=1499,ROOM_D1=1601,ROOM_D2=1867,ROOM_D3=2053)(
    input wire clk,rst,note_valid,note_on,input wire [6:0] note_id,input wire [31:0] note_fcw,
    output wire note_ready,input_ready,bck,ws,din,pa_enable,underrun,frame_ce,gate,
    output wire [VOICES-1:0] voice_active,voice_held,output reg [16:0] envelope_level,input wire [4:0] note_timbre,input wire effects_enable,input wire [1:0] effect_mode,
    input wire effect_cfg_valid,input wire [8:0] effect_echo_wet,effect_room_wet,effect_tremolo_depth,
    input wire [4:0] effect_tremolo_rate_hz,output wire effect_cfg_ready,effect_cfg_applied,
    output wire visual_sample_valid,output wire signed [15:0] visual_sample,
    output reg [VISUAL_KEYS-1:0] visual_notes,
    input wire flush,input wire velocity_valid,input wire [6:0] note_velocity,
    input wire [6:0] volume_percent,input wire [6:0] note_pitch,input wire output_flush,
    output wire latency_valid,output wire [19:0] latency_bcd,
    input wire [2:0] effect_mask,input wire [16:0] effect_echo_samples,
    input wire debug_mute,output wire debug_muted,
    input wire [17:0] manual_pitch_ratio,input wire chorus_enabled,
    input wire [8:0] chorus_wet,input wire [1:0] chorus_depth,chorus_rate);
    // Register the soft engine clear before its wide envelope/RAM fanout.
    // Button assertion stays asynchronous; serial urgent-clear remains separate.
    // One clk of control staging is far below a sample and cancels work before
    // a new render can complete. No PCM sample boundary or startup clock moves.
    reg engine_reset;
    always @(posedge clk or posedge rst)begin
        if(rst)engine_reset<=1'b1;
        else engine_reset<=flush===1'b1;
    end
    // Legacy standalone callers can omit output_flush; top distinguishes an
    // Natural end drains before urgent output clear. Clocks/startup never use these resets.
    wire output_reset=rst || (output_flush===1'b1) ||
        ((output_flush!==1'b0 && output_flush!==1'b1) && (flush===1'b1));
    // Last-source diagnostics only. Rendering uses immutable per-physical-voice
    // metadata, so reusing one of16 scheduler IDs cannot alter a release tail.
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
    wire [VOICES*7-1:0] voice_ids,voice_pitches;
    wire [VOICES*9-1:0] voice_gains;
    wire [16:0] voice_level[0:VOICES-1];
    wire [VOICES*5-1:0] voice_timbres;
    reg [VOICES*5-1:0] frame_timbres;
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
    reg [INDEX_W-1:0] prepared_voice;
    reg [17:0] frame_pitch_ratio;reg [31:0] bend_source,bent_fcw;reg bend_manual;
    reg [49:0] bend_product;
    wire [17:0] safe_pitch_ratio=(PERFORMANCE_ENABLE && manual_pitch_ratio>=58386 && manual_pitch_ratio<=73562)?manual_pitch_ratio:18'd65536;
    reg [31:0] slot_fcw;reg slot_restart;reg [4:0] slot_timbre;
    wire signed [`VOICE_W-1:0] gain_sample;
    wire signed [15:0] mix_sample;
    wire [15:0] frame_l,frame_r;
    reg [VISUAL_KEYS-1:0] note_scan;
    // Metadata read, automatic lookup, then bitmap update occupy separate clocks.
    // Avoid a render-counter -> context mux -> dynamic shift -> bitmap path.
    reg [6:0] scanning_id,scanning_pitch;
    reg scanning_held,scanning_first,scanning_last;reg [6:0] slot_pitch;
    wire [VISUAL_KEYS-1:0] note_bit=(scanning_held && scanning_pitch>=60 && scanning_pitch<60+VISUAL_KEYS) ? ( {{(VISUAL_KEYS-1){1'b0}},1'b1} << (scanning_pitch-7'd60)) : {VISUAL_KEYS{1'b0}};
    always @(posedge clk or posedge engine_reset)begin
        if(engine_reset)begin note_scan<=0;visual_notes<=0;scanning_id<=0;scanning_pitch<=0;scanning_held<=0;scanning_first<=0;scanning_last<=0;slot_pitch<=0;end
        else begin
            if(dds_ce)begin
                scanning_id<=voice_ids[selected_voice*7+:7];slot_pitch<=voice_pitches[selected_voice*7+:7];scanning_held<=voice_held[selected_voice];
                scanning_first<=selected_voice==0;scanning_last<=selected_voice==VOICES-1;
            end
            if(in_slots && render_cycle[3:0]==1)scanning_pitch<=slot_pitch;
            if(in_slots && render_cycle[3:0]==2)begin
                if(scanning_first)note_scan<=note_bit;else note_scan<=note_scan | note_bit;
                if(scanning_last)visual_notes<=scanning_first ? note_bit : note_scan | note_bit;
            end
        end
    end
    wire output_valid,output_valid_r;wire signed [15:0] output_sample,output_sample_r;
    wire stereo_mix_valid,stereo_mix_valid_r;
    wire signed [15:0] stereo_mix_l,stereo_mix_r;
    wire effect_ready_r,effect_valid_r;wire signed [15:0] effect_sample_r;
    wire cfg_ready_r,cfg_applied_r;
    wire signed [16:0] visual_sum={output_sample[15],output_sample}+{output_sample_r[15],output_sample_r};
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
        audio_limiter #(.WINDOW_LOG2(LIMITER_LOG2),.PRE_GAIN(OUTPUT_GAIN),.HOLD_SAMPLES(LIMITER_HOLD_SAMPLES),.FIXED_LATENCY(STEREO_ENABLE)) limiter(
            clk,output_reset,frame_ce,staged_valid?staged_sample:16'sd0,
            limiter_ready,limited_valid,limited_sample,limiter_gain,limiter_clipped,staged_valid?staged_tag:17'd0,limited_tag);
    end else begin: output_bypass
        assign limited_valid=effect_valid;assign limited_sample=effect_sample;
        assign limited_tag=render_tag;
        assign limiter_ready=1;assign limiter_gain=65536;assign limiter_clipped=0;
    end endgenerate
    // Urgent clears cancel PCM/valid only; the user's gain/ramp survives.
    wire [6:0] effective_volume=debug_mute===1'b1 ? 7'd0 : volume_percent;
    reg [8:0] mute_samples;
    always @(posedge clk or posedge rst)begin
        if(rst)mute_samples<=0;
        else if(debug_mute!==1'b1)mute_samples<=0;
        else if(output_valid && mute_samples<260)mute_samples<=mute_samples+1'b1;
    end
    // Four frames beyond the maximum 256-sample ramp cover the frame buffer
    // and the complete left/right serial words; no audio clocks are stopped.
    assign debug_muted=debug_mute===1'b1 && mute_samples==260 && frame_l==0 && frame_r==0;
    master_volume volume_control(clk,rst,limited_valid,limited_sample,effective_volume,output_valid,output_sample,output_reset);
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
    assign visual_sample=STEREO_ENABLE ? (visual_sum>>>1) : output_sample;
    wire frame_pre_ce;wire [VOICES-1:0] envelope_enables,envelope_resets;
    audio_timing timing(clk,rst,bck,rise_ce,fall_ce,frame_ce,bit_index,frame_pre_ce);
    startup_envelope #(.MUTE(MUTE),.FADE(FADE)) startup(clk,rst,frame_ce,input_ready,startup_level);
    assign pa_enable=input_ready;
    assign gate=|voice_held;
    // Freeze ownership while rendering; external producers retain valid/data.
    voice_allocator #(.VOICES(VOICES),.AUTOMATIC_IDS(16),.PRESERVE_MANUAL_TAILS(1)) allocator(
        .clk(clk),.rst(engine_reset),.enabled(input_ready && !render_busy),.frame_ce(frame_ce),
        .note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(note_fcw),
        .voice_active(voice_active),.note_ready(note_ready),.voice_start(voice_start),
        .voice_stop(voice_stop),.voice_restart(voice_restart),.voice_held(voice_held),
        .voice_fcw(voice_fcw),.voice_ids(voice_ids),
        .note_timbre(note_timbre),.voice_timbres(voice_timbres),
        .note_independent(velocity_valid===1'b1 && (note_id<16 || (PERFORMANCE_ENABLE && note_id>=96 && note_id<108))),.note_gain(velocity_gain(note_velocity)),.note_pitch(note_pitch),
        .voice_gains(voice_gains),.voice_pitches(voice_pitches));
    `include "config/sustain_curve.svh"
    reg [50:0] release_curve;reg [8:0] release_strength;
    always @(posedge clk or posedge engine_reset)
        if(engine_reset)begin release_curve<=sustain_curve(17'd7200);release_strength<=64;end
        else if(effect_cfg_valid)begin release_curve<=sustain_curve(effect_echo_samples);release_strength<=effect_echo_wet>256?9'd256:effect_echo_wet;end
    localparam integer ENV_MAX_AD=ATTACK>DECAY?ATTACK:DECAY;
    localparam integer ENV_MAX_N=ENV_MAX_AD>RELEASE?ENV_MAX_AD:RELEASE;
    localparam integer ENV_CW=ENV_MAX_N>0?$clog2(ENV_MAX_N+1):1;
    wire [17*VOICES-1:0] prepare_seeds,prepare_releases,prepared_attack_q,prepared_release_q;
    wire [ENV_CW*VOICES-1:0] prepared_attack_r,prepared_release_r;
    if(SHARED_ENVELOPE_PRECALC!=0)begin: shared_envelope_preparation
        envelope_precalc_bank #(.VOICES(VOICES),.ATTACK(ATTACK),.DECAY(DECAY),.RELEASE(RELEASE)) prepare(
            .clk(clk),.rst(engine_reset),.sample_ce(frame_ce),.seeds(prepare_seeds),.levels(prepare_releases),
            .attack_q(prepared_attack_q),.attack_r(prepared_attack_r),.release_q(prepared_release_q),.release_r(prepared_release_r));
    end else begin: individual_envelope_preparation
        assign prepared_attack_q=0;assign prepared_attack_r=0;assign prepared_release_q=0;assign prepared_release_r=0;
    end
    for(genvar v=0;v<VOICES;v=v+1)begin: voices
        // Same predictor and reset as the main boundary FF: no added cycle.
        // Preserve local copies so each envelope has a nearby, bounded CE net.
        (* syn_preserve=1, syn_keep=1 *) reg envelope_ce;
        (* syn_preserve=1, syn_keep=1 *) reg envelope_reset;
        always @(posedge clk or posedge rst)begin
            if(rst)envelope_ce<=`BCK_HALF_CYCLES==1;
            else envelope_ce<=frame_pre_ce;
        end
        // Identical phase to engine_reset, but without its global reset fanout.
        always @(posedge clk or posedge rst)begin
            if(rst)envelope_reset<=1'b1;
            else envelope_reset<=flush===1'b1;
        end
        assign envelope_resets[v]=envelope_reset;
        assign envelope_enables[v]=`BCK_HALF_CYCLES==1 ? (!rst && envelope_ce) : envelope_ce;
        wire [16:0] native_level;wire native_active;
        if(SUSTAIN_ENABLE)begin: sustain_on
            sustain_envelope #(.PRECALC(1)) tail(.clk(clk),.rst(envelope_reset),.sample_ce(envelope_enables[v]),
                .note_on(voice_start[v]),.note_off(voice_stop[v]),.enabled(effect_mask[0]===1'b1 && voice_timbres[v*5+:5]<16),
                .base_level(native_level),.base_active(native_active),.duration(release_curve[50:34]),
                .phase_step(release_curve[33:17]),.phase_remainder(release_curve[16:0]),.strength(release_strength),
                .level(voice_level[v]),.active(voice_active[v]));
        end else begin: sustain_off
            assign voice_level[v]=native_level;assign voice_active[v]=native_active;
        end
        instrument_envelope #(.ATTACK(ATTACK),.DECAY(DECAY),.SUSTAIN(SUSTAIN),.RELEASE(RELEASE),.PRECALC(1),.EXTERNAL_PRECALC(SHARED_ENVELOPE_PRECALC)) envelope(
            .clk(clk),.rst(envelope_reset),.sample_ce(envelope_enables[v]),.note_on(voice_start[v]),.note_off(voice_stop[v]),
            .level(native_level),.active(native_active),.restart(voice_restart[v]),.timbre(voice_timbres[v*5+:5]),
            .prepared_attack_q(prepared_attack_q[v*17+:17]),.prepared_attack_r(prepared_attack_r[v*ENV_CW+:ENV_CW]),
            .prepared_release_q(prepared_release_q[v*17+:17]),.prepared_release_r(prepared_release_r[v*ENV_CW+:ENV_CW]),
            .prepare_seed(prepare_seeds[v*17+:17]),.prepare_release(prepare_releases[v*17+:17]));
    end
    dds_sine #(.VOICES(VOICES),.PREPARE_CONTEXT(1)) dds(.clk(clk),.rst(engine_reset),.sample_ce(dds_ce),
        .fcw(slot_fcw),.sample(raw_sample),.valid(raw_valid),
        .phase(phase),.restart(slot_restart),.voice_index(prepared_voice),.timbre(slot_timbre));
    always @(posedge clk or posedge engine_reset)begin
        if(engine_reset)begin
            render_busy<=0;render_cycle<=0;frame_fcw<=0;frame_restart<=0;frame_timbres<=0;
            selected_level<=0;selected_startup<=0;level_product<=0;combined_level<=0;gain_request<=0;
            first_sample<=0;last_sample<=0;sample_voice<=0;velocity_scale<=256;
            prepared_voice<=0;slot_fcw<=0;slot_restart<=0;slot_timbre<=0;
            frame_pitch_ratio<=65536;bend_source<=0;bend_manual<=0;bend_product<=0;bent_fcw<=0;
        end else begin
            // Frame-atomic manual pitch bend, three registered steps before slot0.
            if(PERFORMANCE_ENABLE && render_busy && render_cycle<16*VOICES)begin
                if(render_cycle[3:0]==11)begin
                    bend_source<=frame_fcw[(render_cycle>>4)*32+:32];
                    bend_manual<=voice_ids[(render_cycle>>4)*7+:7]>=60 && voice_ids[(render_cycle>>4)*7+:7]<=107;
                end
                if(render_cycle[3:0]==12)bend_product<=bend_source*(bend_manual?frame_pitch_ratio:18'd65536);
                if(render_cycle[3:0]==13)bent_fcw<=(bend_product+50'd32768)>>16;
            end
            // Prepare the next voice during its two preceding idle clocks.
            // DDS still samples on slot0: context mux and phase addition no
            // longer share the render-counter path, with no extra audio cycle.
            if(render_busy && render_cycle<16*VOICES && render_cycle[3:0]==14)
                prepared_voice<=render_cycle>>4;
            if(render_busy && render_cycle<16*VOICES && render_cycle[3:0]==15)begin
                slot_fcw<=PERFORMANCE_ENABLE?bent_fcw:frame_fcw[prepared_voice*32+:32];
                slot_restart<=frame_restart[prepared_voice];slot_timbre<=frame_timbres[prepared_voice*5+:5];
            end
            // Context selection and multiplication occupy separate clocks.
            gain_request<=in_slots && render_cycle[3:0]==4;
            if(in_slots && render_cycle[3:0]==1)level_product<=selected_level*selected_startup;
            if(in_slots && render_cycle[3:0]==3)combined_level<=scaled_level[24:8];
            if(frame_ce)begin
                render_busy<=1;render_cycle<=0;
                frame_fcw<=voice_fcw;frame_restart<=voice_restart;frame_timbres<=voice_timbres;frame_pitch_ratio<=safe_pitch_ratio;
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
            if(in_slots && render_cycle[3:0]==1)velocity_scale<=voice_gains[selected_voice*9+:9];
        end
    end
    tone_gain #(.OUTPUT_W(`VOICE_W)) gain(clk,engine_reset,gain_request,raw_sample,combined_level,gain_valid,gain_sample);
    voice_mixer mixer(clk,engine_reset,gain_valid,gain_sample,first_sample,last_sample,mix_valid,mix_sample);
    // Explicit balanced peak tree, rather than a 32-comparator serial chain.
    localparam integer PEAK_LEAVES=1<<INDEX_W;
    wire [16:0] peak_tree[1:2*PEAK_LEAVES-1];
    for(genvar p=0;p<PEAK_LEAVES;p=p+1)begin: peak_leaves
        if(p<VOICES)assign peak_tree[PEAK_LEAVES+p]=voice_level[p];
        else assign peak_tree[PEAK_LEAVES+p]=0;
    end
    for(genvar p=1;p<PEAK_LEAVES;p=p+1)begin: peak_nodes
        assign peak_tree[p]=peak_tree[p*2]>peak_tree[p*2+1]?peak_tree[p*2]:peak_tree[p*2+1];
    end
    always @* envelope_level=peak_tree[1];
    // Fixed pitch zones spread voices without gain boosts or dynamic pan jumps.
    // Each physical voice keeps its pitch/pan through release. Mono remains an
    // exact compatibility path for standalone callers; board enables stereo.
    wire signed [`VOICE_W-1:0] pan_left=slot_pitch<60 ? gain_sample-(gain_sample>>>2) :
        slot_pitch<66 ? gain_sample : slot_pitch<72 ? (gain_sample>>>1) : (gain_sample>>>2);
    wire signed [`VOICE_W-1:0] pan_right=slot_pitch<60 ? (gain_sample>>>2) :
        slot_pitch<66 ? (gain_sample>>>1) : slot_pitch<72 ? gain_sample : gain_sample-(gain_sample>>>2);
    if(STEREO_ENABLE)begin: stereo_on
        voice_mixer left_mixer(clk,engine_reset,gain_valid,pan_left,first_sample,last_sample,stereo_mix_valid,stereo_mix_l);
        voice_mixer right_mixer(clk,engine_reset,gain_valid,pan_right,first_sample,last_sample,stereo_mix_valid_r,stereo_mix_r);
        audio_effects #(.CHORUS_ENABLE(PERFORMANCE_ENABLE),.CHORUS_PHASE(32'h40000000),.ECHO_ENABLE(!SUSTAIN_ENABLE),.DELAY_SAMPLES(DELAY_SAMPLES),.D0(ROOM_D0),.D1(ROOM_D1),.D2(ROOM_D2),.D3(ROOM_D3)) right_effect(
            .clk(clk),.rst(engine_reset),.enable(effects_enable),.mode(effect_mode),.in_valid(stereo_mix_valid_r),.in_sample(stereo_mix_r),
            .in_ready(effect_ready_r),.out_valid(effect_valid_r),.out_sample(effect_sample_r),
            .effect_mask(effect_mask),.cfg_echo_samples(effect_echo_samples[14:0]),
            .cfg_valid(effect_cfg_valid),.cfg_echo_wet(effect_echo_wet),.cfg_room_wet(effect_room_wet),
            .cfg_tremolo_depth(effect_tremolo_depth),.cfg_tremolo_rate_hz(effect_tremolo_rate_hz),
            .cfg_ready(cfg_ready_r),.cfg_applied(cfg_applied_r),
            .chorus_enabled(chorus_enabled),.chorus_wet(chorus_wet),.chorus_depth(chorus_depth),.chorus_rate(chorus_rate));
        wire right_limited_valid;wire signed [15:0] right_limited_sample;
        wire right_limiter_ready,right_limiter_clipped;wire [16:0] right_limiter_gain,right_limited_tag;
        if(OUTPUT_ENABLE)begin: output_conditioning
            reg signed [15:0] staged_sample;reg staged_valid;reg [16:0] staged_tag;
            always @(posedge clk or posedge output_reset)begin
                if(output_reset)begin staged_sample<=0;staged_valid<=0;staged_tag<=0;end
                else begin
                    if(frame_ce)begin staged_valid<=0;staged_tag<=0;end
                    if(effect_valid_r && !engine_reset)begin staged_sample<=effect_sample_r;staged_valid<=1;staged_tag<=render_tag;end
                end
            end
            audio_limiter #(.WINDOW_LOG2(LIMITER_LOG2),.PRE_GAIN(OUTPUT_GAIN),.HOLD_SAMPLES(LIMITER_HOLD_SAMPLES),.FIXED_LATENCY(1)) limiter(
                clk,output_reset,frame_ce,staged_valid?staged_sample:16'sd0,
                right_limiter_ready,right_limited_valid,right_limited_sample,right_limiter_gain,right_limiter_clipped,
                staged_valid?staged_tag:17'd0,right_limited_tag);
        end else begin: output_bypass
            assign right_limited_valid=effect_valid_r;assign right_limited_sample=effect_sample_r;
            assign right_limited_tag=render_tag;
            assign right_limiter_ready=1;assign right_limiter_gain=65536;assign right_limiter_clipped=0;
        end
        master_volume right_volume(clk,rst,right_limited_valid,right_limited_sample,effective_volume,output_valid_r,output_sample_r,output_reset);
    end else begin: mono_on
        assign stereo_mix_valid=mix_valid;assign stereo_mix_valid_r=mix_valid;
        assign stereo_mix_l=mix_sample;assign stereo_mix_r=mix_sample;
        assign effect_ready_r=effect_ready;assign effect_valid_r=effect_valid;assign effect_sample_r=effect_sample;
        assign cfg_ready_r=effect_cfg_ready;assign cfg_applied_r=effect_cfg_applied;
        assign output_valid_r=output_valid;assign output_sample_r=output_sample;
    end
    audio_effects #(.CHORUS_ENABLE(PERFORMANCE_ENABLE),.CHORUS_PHASE(32'h00000000),.ECHO_ENABLE(!SUSTAIN_ENABLE),.DELAY_SAMPLES(DELAY_SAMPLES),.D0(ROOM_D0),.D1(ROOM_D1),.D2(ROOM_D2),.D3(ROOM_D3)) effect(
        .clk(clk),.rst(engine_reset),.enable(effects_enable),.mode(effect_mode),.in_valid(stereo_mix_valid),.in_sample(stereo_mix_l),
        .in_ready(effect_ready),.out_valid(effect_valid),.out_sample(effect_sample),
        .effect_mask(effect_mask),.cfg_echo_samples(effect_echo_samples[14:0]),
            .cfg_valid(effect_cfg_valid),.cfg_echo_wet(effect_echo_wet),.cfg_room_wet(effect_room_wet),
        .cfg_tremolo_depth(effect_tremolo_depth),.cfg_tremolo_rate_hz(effect_tremolo_rate_hz),
        .cfg_ready(effect_cfg_ready),.cfg_applied(effect_cfg_applied),
        .chorus_enabled(chorus_enabled),.chorus_wet(chorus_wet),.chorus_depth(chorus_depth),.chorus_rate(chorus_rate));
    frame_buffer buffer(clk,OUTPUT_ENABLE?output_reset:engine_reset,frame_ce,output_valid,ready,output_sample,output_sample_r,frame_l,frame_r,underrun);
    i2s_tx tx(clk,rst,fall_ce,bit_index,frame_l,frame_r,ws,din);
    // synthesis translate_off
    initial if(VOICES<1 || VOICES>32 || RENDER_BUDGET>=`FRAME_CYCLES)$fatal(1,"Invalid render budget");
    always @(posedge clk)if(!rst)begin
        if(envelope_enables!=={VOICES{frame_ce}})$fatal(1,"Distributed envelope CE changed sample boundary");
        if(envelope_resets!=={VOICES{engine_reset}})$fatal(1,"Distributed envelope reset changed clear phase");
        if(!PERFORMANCE_ENABLE && dds_ce && (prepared_voice!==selected_voice ||
           {slot_fcw,slot_restart,slot_timbre}!=={frame_fcw[selected_voice*32+:32],frame_restart[selected_voice],frame_timbres[selected_voice*5+:5]}))
            $fatal(1,"Prepared DDS context differs at the original sample edge");
        if(frame_ce && render_busy)$fatal(1,"Frame renderer missed deadline");
        if(STEREO_ENABLE && (stereo_mix_valid!==stereo_mix_valid_r || effect_valid!==effect_valid_r || output_valid!==output_valid_r || effect_cfg_ready!==cfg_ready_r || effect_cfg_applied!==cfg_applied_r))$fatal(1,"Stereo channel pipeline mismatch");
        if(mix_valid && (!effect_ready || !effect_ready_r))$fatal(1,"Effect rejected render result");
        if(output_valid && !ready)$fatal(1,"Frame buffer rejected effect result");
    end
    // synthesis translate_on
endmodule


