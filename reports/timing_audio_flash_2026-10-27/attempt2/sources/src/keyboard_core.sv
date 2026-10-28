`timescale 1ns/1ps
`include "config/keyboard_config.svh"
// Replaceable matrix adapter. Voice allocation and all audio stay in synth_core.
module keyboard_core #(
    parameter integer SLOT_CYCLES=`KEY_SLOT_CYCLES,SETTLE_CYCLES=`KEY_SETTLE_CYCLES,
    DEBOUNCE_SCANS=`KEY_DEBOUNCE_SCANS)(
    input wire clk,rst,input_ready,note_ready,input wire [3:0] key_row,
    output wire [3:0] col_enable,output wire [15:0] keys,output wire ghost,
    output wire note_valid,note_on,output wire [6:0] note_id,
    output wire [31:0] note_fcw,output wire gate,output wire [3:0] last_key,
    input wire [2:0] selected_timbre,output wire [2:0] note_timbre,input wire inhibit_notes);
    wire scan_valid;
    wire [15:0] note_keys=(inhibit_notes===1'b1) ? 16'd0 : keys;
    matrix_keypad #(.SLOT_CYCLES(SLOT_CYCLES),.SETTLE_CYCLES(SETTLE_CYCLES),.DEBOUNCE_SCANS(DEBOUNCE_SCANS))
        keyboard(clk,rst,key_row,col_enable,keys,scan_valid,ghost);
    key_note_events control(clk,rst,input_ready,note_keys,note_ready,
        note_valid,note_on,note_id,note_fcw,gate,last_key,selected_timbre,note_timbre);
endmodule

