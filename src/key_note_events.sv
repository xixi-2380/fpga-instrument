`timescale 1ns/1ps
// Matrix-specific state-to-event adapter. An offered event remains stable
// through backpressure; acknowledged state catches up to the latest keys.
module key_note_events #(parameter integer BASE_NOTE=60)(
    input wire clk,rst,enabled,input wire [15:0] keys,input wire note_ready,
    output reg note_valid,note_on,output reg [6:0] note_id,
    output reg [31:0] note_fcw,output wire gate,output reg [3:0] last_key,
    input wire [2:0] selected_timbre,output reg [2:0] note_timbre);
    `include "config/keyboard_notes.svh"
    reg [15:0] reported_keys;
    reg [3:0] offered_key;
    wire [15:0] released=reported_keys & ~keys;
    wire [15:0] pressed=keys & ~reported_keys;
    reg [3:0] candidate;
    always @* begin
        candidate=0;
        // Prefer releases when selecting a NEW event, then lowest key number.
        for(integer k=15;k>=0;k=k-1)
            if((|released)?released[k]:pressed[k])candidate=k;
    end
    assign gate=|reported_keys;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            reported_keys<=0;offered_key<=0;last_key<=0;
            note_valid<=0;note_on<=0;note_id<=0;note_fcw<=0;note_timbre<=0;
        end else if(note_valid)begin
            if(note_ready)begin
                reported_keys[offered_key]<=note_on;
                if(note_on)last_key<=offered_key;
                note_valid<=0;
            end
        end else if(enabled && (|released || |pressed))begin
            offered_key<=candidate;
            note_on<=!(|released);
            note_id<=BASE_NOTE+candidate;
            note_fcw<=key_fcw(candidate);
            case(selected_timbre)
                3'd1:note_timbre<=1;
                3'd2:note_timbre<=2;
                3'd3:note_timbre<=3;3'd4:note_timbre<=4;3'd5:note_timbre<=5;3'd6:note_timbre<=6;
                default:note_timbre<=0;
            endcase
            note_valid<=1;
        end
    end
    // synthesis translate_off
    initial if(BASE_NOTE<0 || BASE_NOTE+15>127)$fatal(1,"Invalid matrix note range");
    // synthesis translate_on
endmodule

