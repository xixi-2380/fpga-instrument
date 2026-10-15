`timescale 1ns/1ps
`include "config/keyboard_config.svh"
module keyboard_core #(
    parameter integer SLOT_CYCLES=`KEY_SLOT_CYCLES,SETTLE_CYCLES=`KEY_SETTLE_CYCLES,
    DEBOUNCE_SCANS=`KEY_DEBOUNCE_SCANS,MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES,
    ATTACK=`ADSR_ATTACK_FRAMES,DECAY=`ADSR_DECAY_FRAMES,
    SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES)(
    input wire clk,rst,input wire [3:0] key_row,
    output wire [3:0] col_enable,output wire bck,ws,din,pa_enable,underrun,
    output wire [15:0] keys,output wire ghost,gate,
    output wire [3:0] selected_key,output wire [16:0] envelope_level);
    wire scan_valid,rise_ce,fall_ce,frame_ce,note_on,note_off,raw_valid,gain_valid,ready;
    wire [4:0] bit_index;
    wire [31:0] fcw,phase;
    wire signed [15:0] raw_sample,gain_sample;
    wire [16:0] startup_level;
    wire [33:0] level_product=envelope_level*startup_level;
    reg [16:0] combined_level;
    reg gain_request;
    wire [15:0] frame_l,frame_r;
    matrix_keypad #(.SLOT_CYCLES(SLOT_CYCLES),.SETTLE_CYCLES(SETTLE_CYCLES),.DEBOUNCE_SCANS(DEBOUNCE_SCANS))
        keyboard(clk,rst,key_row,col_enable,keys,scan_valid,ghost);
    audio_timing timing(clk,rst,bck,rise_ce,fall_ce,frame_ce,bit_index);
    mono_note_control control(clk,rst,frame_ce,pa_enable?keys:16'b0,
        note_on,note_off,fcw,gate,selected_key);
    adsr_envelope #(.ATTACK(ATTACK),.DECAY(DECAY),.SUSTAIN(SUSTAIN),.RELEASE(RELEASE))
        envelope(clk,rst,frame_ce,note_on,note_off,envelope_level);
    startup_envelope #(.MUTE(MUTE),.FADE(FADE)) startup(clk,rst,frame_ce,pa_enable,startup_level);
    dds_sine dds(clk,rst,frame_ce,fcw,raw_sample,raw_valid,phase);
    // Pipeline envelope multiplication separately from sample multiplication.
    // ROM output stays constant until the next frame. Production takes three
    // cycles after frame_ce, comfortably before the 1280-cycle deadline.
    always @(posedge clk or posedge rst)begin
        if(rst)begin combined_level<=0;gain_request<=0;end
        else begin
            gain_request<=raw_valid;
            if(raw_valid)combined_level<=level_product[32:16];
        end
    end
    tone_gain gain(clk,rst,gain_request,raw_sample,combined_level,gain_valid,gain_sample);
    frame_buffer buffer(clk,rst,frame_ce,gain_valid,ready,gain_sample,gain_sample,frame_l,frame_r,underrun);
    pt8211_tx tx(clk,rst,fall_ce,bit_index,frame_l,frame_r,ws,din);
endmodule
