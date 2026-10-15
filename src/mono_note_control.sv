`timescale 1ns/1ps
module mono_note_control(input wire clk,rst,sample_ce,input wire [15:0] keys,
    output wire note_on,note_off,output wire [31:0] fcw,
    output reg gate,output reg [3:0] selected_key);
    `include "config/keyboard_notes.svh"
    reg [15:0] previous_keys;
    reg [31:0] held_fcw;
    wire [15:0] new_keys=keys & ~previous_keys;
    reg [3:0] next_key;
    reg next_gate;
    always @* begin
        next_key=selected_key;next_gate=|keys;
        if(|new_keys)begin
            for(integer k=0;k<16;k=k+1)if(new_keys[k])next_key=k;
        end else if(!gate || !keys[selected_key])begin
            for(integer k=0;k<16;k=k+1)if(keys[k])next_key=k;
        end
    end
    assign note_on=!rst && sample_ce && next_gate &&
                   (!gate || next_key!=selected_key || new_keys[next_key]);
    assign note_off=!rst && sample_ce && gate && !next_gate;
    assign fcw=(sample_ce && next_gate)?key_fcw(next_key):held_fcw;
    always @(posedge clk or posedge rst)begin
        if(rst)begin previous_keys<=0;selected_key<=0;gate<=0;held_fcw<=key_fcw(0);end
        else if(sample_ce)begin
            previous_keys<=keys;gate<=next_gate;selected_key<=next_key;
            if(next_gate)held_fcw<=key_fcw(next_key);
        end
    end
endmodule
