`timescale 1ns/1ps
// Keyboard state-to-event adapter. An offered event remains stable
// through backpressure; acknowledged state catches up to the latest keys.
module key_note_events #(parameter integer BASE_NOTE=60,KEYS=16,INDEX_W=(KEYS>1?$clog2(KEYS):1))(
    input wire clk,rst,enabled,input wire [KEYS-1:0] keys,input wire note_ready,
    output reg note_valid,note_on,output reg [6:0] note_id,
    output reg [31:0] note_fcw,output wire gate,output reg [INDEX_W-1:0] last_key,
    input wire [2:0] selected_timbre,output reg [2:0] note_timbre);
    `include "config/keyboard_notes.svh"
    reg [KEYS-1:0] reported_keys;
    reg [INDEX_W-1:0] offered_key;
    wire [KEYS-1:0] released=reported_keys & ~keys;
    wire [KEYS-1:0] pressed=keys & ~reported_keys;
    reg [INDEX_W-1:0] candidate;
    localparam integer GROUPS=(KEYS+5)/6;
    reg [GROUPS-1:0] group_valid;
    reg [INDEX_W-1:0] group_key[0:GROUPS-1];
    reg lookup_pending;
    reg [2:0] sampled_timbre;
    // Free-running preparation: LOAD consumes the value sampled on the
    // selection edge, preserving the exact onset preset without a long CE.
    always @(posedge clk or posedge rst)begin
        if(rst)sampled_timbre<=0;
        else case(selected_timbre)
            1:sampled_timbre<=1;2:sampled_timbre<=2;3:sampled_timbre<=3;
            4:sampled_timbre<=4;5:sampled_timbre<=5;6:sampled_timbre<=6;
            default:sampled_timbre<=0;
        endcase
    end
    always @* begin
        // Bounded two-level priority, six keys per group. A registered key
        // address separates the state/router path from the synchronous FCW ROM.
        group_valid=0;candidate=0;
        for(integer g=0;g<GROUPS;g=g+1)begin
            group_key[g]=0;
            for(integer k=5;k>=0;k=k-1)if(g*6+k<KEYS)
                if((|released)?released[g*6+k]:pressed[g*6+k])begin
                    group_valid[g]=1;group_key[g]=g*6+k;
                end
        end
        for(integer g=GROUPS-1;g>=0;g=g-1)
            if(group_valid[g])candidate=group_key[g];
    end
    assign gate=|reported_keys;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            reported_keys<=0;offered_key<=0;last_key<=0;
            note_valid<=0;note_on<=0;note_id<=0;note_fcw<=0;note_timbre<=0;lookup_pending<=0;
        end else if(note_valid)begin
            if(note_ready)begin
                for(integer k=0;k<KEYS;k=k+1)
                    if(offered_key==k)reported_keys[k]<=note_on;
                if(note_on)last_key<=offered_key;
                note_valid<=0;
            end
        end else if(lookup_pending)begin
            note_id<=BASE_NOTE+offered_key;
            note_fcw<=key_fcw(offered_key);
            note_timbre<=sampled_timbre;
            lookup_pending<=0;note_valid<=1;
        end else if(enabled && (|released || |pressed))begin
            offered_key<=candidate;
            note_on<=!(|released);
            lookup_pending<=1;
        end
    end
    // synthesis translate_off
    initial if(BASE_NOTE<0 || BASE_NOTE!=60 || KEYS<1 || KEYS>36 || BASE_NOTE+KEYS-1>127)$fatal(1,"Invalid keyboard note range");
    // synthesis translate_on
endmodule

