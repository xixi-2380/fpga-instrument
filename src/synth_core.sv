`timescale 1ns/1ps
`include "config/synth_config.svh"
// Generic note-event synthesis; physical keyboard logic stays in its adapter.
module synth_core #(
    parameter integer STEREO_ENABLE=0,VOICES=`VOICE_COUNT,MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES,
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
    input wire [6:0] volume_percent,input wire [6:0] note_pitch);
    wire engine_reset=rst || (flush===1'b1);
    // Last-source diagnostics only. Rendering uses immutable per-physical-voice
    // metadata, so reusing one of16 scheduler IDs cannot alter a release tail.
    reg [8:0] velocities[0:15];
    reg [6:0] automatic_pitch[0:15];
    reg [8:0] velocity_scale;
    function automatic [8:0] velocity_gain(input [6:0] value);
    begin case(value)
        7'd0:velocity_gain=9'd0;
        7'd1:velocity_gain=9'd2;
        7'd2:velocity_gain=9'd4;
        7'd3:velocity_gain=9'd6;
        7'd4:velocity_gain=9'd8;
        7'd5:velocity_gain=9'd10;
        7'd6:velocity_gain=9'd12;
        7'd7:velocity_gain=9'd14;
        7'd8:velocity_gain=9'd16;
        7'd9:velocity_gain=9'd18;
        7'd10:velocity_gain=9'd20;
        7'd11:velocity_gain=9'd22;
        7'd12:velocity_gain=9'd24;
        7'd13:velocity_gain=9'd26;
        7'd14:velocity_gain=9'd28;
        7'd15:velocity_gain=9'd30;
        7'd16:velocity_gain=9'd32;
        7'd17:velocity_gain=9'd34;
        7'd18:velocity_gain=9'd36;
        7'd19:velocity_gain=9'd38;
        7'd20:velocity_gain=9'd40;
        7'd21:velocity_gain=9'd42;
        7'd22:velocity_gain=9'd44;
        7'd23:velocity_gain=9'd46;
        7'd24:velocity_gain=9'd48;
        7'd25:velocity_gain=9'd50;
        7'd26:velocity_gain=9'd52;
        7'd27:velocity_gain=9'd54;
        7'd28:velocity_gain=9'd56;
        7'd29:velocity_gain=9'd58;
        7'd30:velocity_gain=9'd60;
        7'd31:velocity_gain=9'd62;
        7'd32:velocity_gain=9'd65;
        7'd33:velocity_gain=9'd67;
        7'd34:velocity_gain=9'd69;
        7'd35:velocity_gain=9'd71;
        7'd36:velocity_gain=9'd73;
        7'd37:velocity_gain=9'd75;
        7'd38:velocity_gain=9'd77;
        7'd39:velocity_gain=9'd79;
        7'd40:velocity_gain=9'd81;
        7'd41:velocity_gain=9'd83;
        7'd42:velocity_gain=9'd85;
        7'd43:velocity_gain=9'd87;
        7'd44:velocity_gain=9'd89;
        7'd45:velocity_gain=9'd91;
        7'd46:velocity_gain=9'd93;
        7'd47:velocity_gain=9'd95;
        7'd48:velocity_gain=9'd97;
        7'd49:velocity_gain=9'd99;
        7'd50:velocity_gain=9'd101;
        7'd51:velocity_gain=9'd103;
        7'd52:velocity_gain=9'd105;
        7'd53:velocity_gain=9'd107;
        7'd54:velocity_gain=9'd109;
        7'd55:velocity_gain=9'd111;
        7'd56:velocity_gain=9'd113;
        7'd57:velocity_gain=9'd115;
        7'd58:velocity_gain=9'd117;
        7'd59:velocity_gain=9'd119;
        7'd60:velocity_gain=9'd121;
        7'd61:velocity_gain=9'd123;
        7'd62:velocity_gain=9'd125;
        7'd63:velocity_gain=9'd127;
        7'd64:velocity_gain=9'd129;
        7'd65:velocity_gain=9'd131;
        7'd66:velocity_gain=9'd133;
        7'd67:velocity_gain=9'd135;
        7'd68:velocity_gain=9'd137;
        7'd69:velocity_gain=9'd139;
        7'd70:velocity_gain=9'd141;
        7'd71:velocity_gain=9'd143;
        7'd72:velocity_gain=9'd145;
        7'd73:velocity_gain=9'd147;
        7'd74:velocity_gain=9'd149;
        7'd75:velocity_gain=9'd151;
        7'd76:velocity_gain=9'd153;
        7'd77:velocity_gain=9'd155;
        7'd78:velocity_gain=9'd157;
        7'd79:velocity_gain=9'd159;
        7'd80:velocity_gain=9'd161;
        7'd81:velocity_gain=9'd163;
        7'd82:velocity_gain=9'd165;
        7'd83:velocity_gain=9'd167;
        7'd84:velocity_gain=9'd169;
        7'd85:velocity_gain=9'd171;
        7'd86:velocity_gain=9'd173;
        7'd87:velocity_gain=9'd175;
        7'd88:velocity_gain=9'd177;
        7'd89:velocity_gain=9'd179;
        7'd90:velocity_gain=9'd181;
        7'd91:velocity_gain=9'd183;
        7'd92:velocity_gain=9'd185;
        7'd93:velocity_gain=9'd187;
        7'd94:velocity_gain=9'd189;
        7'd95:velocity_gain=9'd191;
        7'd96:velocity_gain=9'd194;
        7'd97:velocity_gain=9'd196;
        7'd98:velocity_gain=9'd198;
        7'd99:velocity_gain=9'd200;
        7'd100:velocity_gain=9'd202;
        7'd101:velocity_gain=9'd204;
        7'd102:velocity_gain=9'd206;
        7'd103:velocity_gain=9'd208;
        7'd104:velocity_gain=9'd210;
        7'd105:velocity_gain=9'd212;
        7'd106:velocity_gain=9'd214;
        7'd107:velocity_gain=9'd216;
        7'd108:velocity_gain=9'd218;
        7'd109:velocity_gain=9'd220;
        7'd110:velocity_gain=9'd222;
        7'd111:velocity_gain=9'd224;
        7'd112:velocity_gain=9'd226;
        7'd113:velocity_gain=9'd228;
        7'd114:velocity_gain=9'd230;
        7'd115:velocity_gain=9'd232;
        7'd116:velocity_gain=9'd234;
        7'd117:velocity_gain=9'd236;
        7'd118:velocity_gain=9'd238;
        7'd119:velocity_gain=9'd240;
        7'd120:velocity_gain=9'd242;
        7'd121:velocity_gain=9'd244;
        7'd122:velocity_gain=9'd246;
        7'd123:velocity_gain=9'd248;
        7'd124:velocity_gain=9'd250;
        7'd125:velocity_gain=9'd252;
        7'd126:velocity_gain=9'd254;
        7'd127:velocity_gain=9'd256;
        default:velocity_gain=256;
    endcase end endfunction
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
    wire signed [15:0] effect_sample;
    wire [VOICES*32-1:0] phase;
    reg [33:0] level_product;
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
    reg scanning_held,scanning_first,scanning_last;reg [6:0] slot_pitch;
    wire [15:0] note_bit=(scanning_held && scanning_pitch>=60 && scanning_pitch<76) ? (16'b1 << (scanning_pitch-7'd60)) : 16'd0;
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
    // Flush drops buffered audio but must not reset the user's volume ramp.
    master_volume volume_control(clk,rst,effect_valid,effect_sample,volume_percent,output_valid,output_sample);
    assign visual_sample_valid=output_valid;
    assign visual_sample=STEREO_ENABLE ? (visual_sum>>>1) : output_sample;
    audio_timing timing(clk,rst,bck,rise_ce,fall_ce,frame_ce,bit_index);
    startup_envelope #(.MUTE(MUTE),.FADE(FADE)) startup(clk,rst,frame_ce,input_ready,startup_level);
    assign pa_enable=input_ready;
    assign gate=|voice_held;
    // Freeze ownership while rendering; external producers retain valid/data.
    voice_allocator #(.VOICES(VOICES)) allocator(
        .clk(clk),.rst(engine_reset),.enabled(input_ready && !render_busy),.frame_ce(frame_ce),
        .note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(note_fcw),
        .voice_active(voice_active),.note_ready(note_ready),.voice_start(voice_start),
        .voice_stop(voice_stop),.voice_restart(voice_restart),.voice_held(voice_held),
        .voice_fcw(voice_fcw),.voice_ids(voice_ids),
        .note_timbre(note_timbre),.voice_timbres(voice_timbres),
        .note_independent(velocity_valid===1'b1),.note_gain(velocity_gain(note_velocity)),.note_pitch(note_pitch),
        .voice_gains(voice_gains),.voice_pitches(voice_pitches));
    for(genvar v=0;v<VOICES;v=v+1)begin: voices
        instrument_envelope #(.ATTACK(ATTACK),.DECAY(DECAY),.SUSTAIN(SUSTAIN),.RELEASE(RELEASE)) envelope(
            .clk(clk),.rst(engine_reset),.sample_ce(frame_ce),.note_on(voice_start[v]),.note_off(voice_stop[v]),
            .level(voice_level[v]),.active(voice_active[v]),.restart(voice_restart[v]),.timbre(voice_timbres[v*3+:3]));
    end
    dds_sine #(.VOICES(VOICES)) dds(.clk(clk),.rst(engine_reset),.sample_ce(dds_ce),
        .fcw(frame_fcw[selected_voice*32+:32]),.sample(raw_sample),.valid(raw_valid),
        .phase(phase),.restart(frame_restart[selected_voice]),.voice_index(selected_voice),.timbre(frame_timbres[selected_voice*3+:3]));
    always @(posedge clk or posedge engine_reset)begin
        if(engine_reset)begin
            render_busy<=0;render_cycle<=0;frame_fcw<=0;frame_restart<=0;frame_timbres<=0;
            level_product<=0;combined_level<=0;gain_request<=0;
            first_sample<=0;last_sample<=0;sample_voice<=0;velocity_scale<=256;
        end else begin
            gain_request<=in_slots && render_cycle[3:0]==3;
            if(in_slots && render_cycle[3:0]==2)combined_level<=scaled_level[24:8];
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
        audio_effects #(.DELAY_SAMPLES(DELAY_SAMPLES),.D0(ROOM_D0),.D1(ROOM_D1),.D2(ROOM_D2),.D3(ROOM_D3)) right_effect(
            .clk(clk),.rst(engine_reset),.enable(effects_enable),.mode(effect_mode),.in_valid(stereo_mix_valid_r),.in_sample(stereo_mix_r),
            .in_ready(effect_ready_r),.out_valid(effect_valid_r),.out_sample(effect_sample_r),
            .cfg_valid(effect_cfg_valid),.cfg_echo_wet(effect_echo_wet),.cfg_room_wet(effect_room_wet),
            .cfg_tremolo_depth(effect_tremolo_depth),.cfg_tremolo_rate_hz(effect_tremolo_rate_hz),
            .cfg_ready(cfg_ready_r),.cfg_applied(cfg_applied_r));
        master_volume right_volume(clk,rst,effect_valid_r,effect_sample_r,volume_percent,output_valid_r,output_sample_r);
    end else begin: mono_on
        assign stereo_mix_valid=mix_valid;assign stereo_mix_valid_r=mix_valid;
        assign stereo_mix_l=mix_sample;assign stereo_mix_r=mix_sample;
        assign effect_ready_r=effect_ready;assign effect_valid_r=effect_valid;assign effect_sample_r=effect_sample;
        assign cfg_ready_r=effect_cfg_ready;assign cfg_applied_r=effect_cfg_applied;
        assign output_valid_r=output_valid;assign output_sample_r=output_sample;
    end
    audio_effects #(.DELAY_SAMPLES(DELAY_SAMPLES),.D0(ROOM_D0),.D1(ROOM_D1),.D2(ROOM_D2),.D3(ROOM_D3)) effect(
        .clk(clk),.rst(engine_reset),.enable(effects_enable),.mode(effect_mode),.in_valid(stereo_mix_valid),.in_sample(stereo_mix_l),
        .in_ready(effect_ready),.out_valid(effect_valid),.out_sample(effect_sample),
        .cfg_valid(effect_cfg_valid),.cfg_echo_wet(effect_echo_wet),.cfg_room_wet(effect_room_wet),
        .cfg_tremolo_depth(effect_tremolo_depth),.cfg_tremolo_rate_hz(effect_tremolo_rate_hz),
        .cfg_ready(effect_cfg_ready),.cfg_applied(effect_cfg_applied));
    frame_buffer buffer(clk,engine_reset,frame_ce,output_valid,ready,output_sample,output_sample_r,frame_l,frame_r,underrun);
    i2s_tx tx(clk,rst,fall_ce,bit_index,frame_l,frame_r,ws,din);
    // synthesis translate_off
    initial if(VOICES<1 || VOICES>32 || RENDER_BUDGET>=`FRAME_CYCLES)$fatal(1,"Invalid render budget");
    always @(posedge clk)if(!rst)begin
        if(frame_ce && render_busy)$fatal(1,"Frame renderer missed deadline");
        if(STEREO_ENABLE && (stereo_mix_valid!==stereo_mix_valid_r || effect_valid!==effect_valid_r || output_valid!==output_valid_r || effect_cfg_ready!==cfg_ready_r || effect_cfg_applied!==cfg_applied_r))$fatal(1,"Stereo channel pipeline mismatch");
        if(mix_valid && (!effect_ready || !effect_ready_r))$fatal(1,"Effect rejected render result");
        if(output_valid && !ready)$fatal(1,"Frame buffer rejected effect result");
    end
    // synthesis translate_on
endmodule


