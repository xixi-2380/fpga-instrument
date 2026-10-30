`timescale 1ns/1ps
// Keyboard state-to-event adapter. An offered event remains stable
// through backpressure; acknowledged state catches up to the latest keys.
module key_note_events #(parameter integer MAPPING=0,BASE_NOTE=60,KEYS=16,INDEX_W=(KEYS>1?$clog2(KEYS):1))(
    input wire clk,rst,enabled,input wire [KEYS-1:0] keys,input wire note_ready,
    output reg note_valid,note_on,output reg [6:0] note_id,
    output reg [31:0] note_fcw,output wire gate,output reg [INDEX_W-1:0] last_key,
    input wire [4:0] selected_timbre,output reg [4:0] note_timbre, input wire [575:0] keymap,output reg [6:0] note_pitch,output wire event_pending);
    `include "config/keyboard_notes.svh"
    `include "config/midi_frequency.svh"
    reg [6:0] held_pitch[0:KEYS-1];reg [4:0] held_timbre[0:KEYS-1];
    reg [INDEX_W-1:0] offered_key;
    wire [6:0] mapped_pitch=keymap[offered_key*16+:7];
    wire [4:0] mapped_timbre=keymap[offered_key*16+8+:5];
    reg [KEYS-1:0] reported_keys;
    wire [KEYS-1:0] released=reported_keys & ~keys;
    wire [KEYS-1:0] pressed=keys & ~reported_keys;
    reg [INDEX_W-1:0] candidate;
    localparam integer GROUPS=(KEYS+5)/6;
    reg [GROUPS-1:0] group_valid;
    reg [INDEX_W-1:0] group_key[0:GROUPS-1];
    reg lookup_pending,select_pending;
    reg [KEYS-1:0] released_q,pressed_q;
    reg [4:0] sampled_timbre,offered_timbre;
    // Free-running preparation: LOAD consumes the value sampled on the
    // selection edge, preserving the exact onset preset without a long CE.
    always @(posedge clk or posedge rst)begin
        if(rst)sampled_timbre<=0;
        else if(selected_timbre<16)sampled_timbre<=selected_timbre;else sampled_timbre<=0;
    end
    always @* begin
        // Bounded two-level priority, six keys per group. A registered key
        // address separates the state/router path from the synchronous FCW ROM.
        group_valid=0;candidate=0;
        for(integer g=0;g<GROUPS;g=g+1)begin
            group_key[g]=0;
            for(integer k=5;k>=0;k=k-1)if(g*6+k<KEYS)
                if((|released_q)?released_q[g*6+k]:pressed_q[g*6+k])begin
                    group_valid[g]=1;group_key[g]=g*6+k;
                end
        end
        for(integer g=GROUPS-1;g>=0;g=g-1)
            if(group_valid[g])candidate=group_key[g];
    end
    assign event_pending=note_valid || lookup_pending || select_pending || (|reported_keys);
    assign gate=|reported_keys;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            reported_keys<=0;offered_key<=0;last_key<=0;
            note_pitch<=0;note_valid<=0;note_on<=0;note_id<=0;note_fcw<=0;note_timbre<=0;lookup_pending<=0;
            select_pending<=0;released_q<=0;pressed_q<=0;offered_timbre<=0;
        end else if(note_valid)begin
            if(note_ready)begin
                for(integer k=0;k<KEYS;k=k+1)
                    if(offered_key==k)reported_keys[k]<=note_on;
                if(note_on)begin last_key<=offered_key;held_pitch[offered_key]<=note_pitch;held_timbre[offered_key]<=note_timbre;end
                note_valid<=0;
            end
        end else if(lookup_pending)begin
            note_id<=BASE_NOTE+offered_key;
            if(MAPPING!=0)begin
                note_pitch<=note_on?mapped_pitch:held_pitch[offered_key];
                note_fcw<=frequency(note_on?mapped_pitch:held_pitch[offered_key]);
                note_timbre<=note_on?(mapped_timbre==31?offered_timbre:mapped_timbre):held_timbre[offered_key];
            end else begin note_pitch<=BASE_NOTE+offered_key;note_fcw<=key_fcw(offered_key);note_timbre<=offered_timbre;end
            lookup_pending<=0;note_valid<=1;
        end else if(select_pending)begin
            offered_key<=candidate;
            note_on<=!(|released_q);offered_timbre<=sampled_timbre;
            select_pending<=0;lookup_pending<=1;
        end else if(enabled && (|released || |pressed))begin
            // Freeze the change set before priority selection. Inhibit/router
            // changes cannot traverse the priority network on the same clock.
            released_q<=released;pressed_q<=pressed;select_pending<=1;
        end
    end
    // synthesis translate_off
    initial if(BASE_NOTE<0 || BASE_NOTE!=60 || KEYS<1 || KEYS>36 || BASE_NOTE+KEYS-1>127)$fatal(1,"Invalid keyboard note range");
    // synthesis translate_on
endmodule

