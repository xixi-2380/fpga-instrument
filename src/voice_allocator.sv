`timescale 1ns/1ps
// Keyboard-independent ownership and pending frame commands. Rank is a
// bounded permutation, avoiding the wraparound of timestamp-based stealing.
module voice_allocator #(parameter integer VOICES=4)(
    input wire clk,rst,enabled,frame_ce,note_valid,note_on,
    input wire [6:0] note_id,input wire [31:0] note_fcw,
    input wire [VOICES-1:0] voice_active,
    output wire note_ready,output wire [VOICES-1:0] voice_start,voice_stop,voice_restart,
    output reg [VOICES-1:0] voice_held,
    output wire [VOICES*32-1:0] voice_fcw,
    output wire [VOICES*7-1:0] voice_ids,input wire [1:0] note_timbre,
    output wire [VOICES*2-1:0] voice_timbres);
    localparam integer RW=VOICES>1?$clog2(VOICES):1;
    reg [VOICES-1:0] owned,pending_start,pending_restart,committed_gate;
    reg [6:0] ids [0:VOICES-1];
    reg [31:0] frequencies [0:VOICES-1];
    reg [RW-1:0] rank [0:VOICES-1];
    reg [1:0] timbres[0:VOICES-1];
    integer match_slot,free_slot,released_slot,oldest_slot,target;
    always @* begin
        match_slot=-1;free_slot=-1;released_slot=-1;oldest_slot=0;
        for(integer i=0;i<VOICES;i=i+1)begin
            if(owned[i] && ids[i]==note_id)match_slot=i;
            if(free_slot<0 && (!owned[i] ||
               (!voice_active[i] && !voice_held[i] && !pending_start[i] && !committed_gate[i])))free_slot=i;
            if(owned[i] && !voice_held[i] && !pending_start[i])begin
                if(released_slot<0)released_slot=i;
                else if(rank[i]<rank[released_slot])released_slot=i;
            end
            if(rank[i]<rank[oldest_slot])oldest_slot=i;
        end
        if(match_slot>=0)target=match_slot;
        else if(free_slot>=0)target=free_slot;
        else if(released_slot>=0)target=released_slot;
        else target=oldest_slot;
    end
    // Never acknowledge on a frame edge: metadata and pending commands are
    // stable when every voice snapshots them. Audio serialization never stalls.
    assign note_ready=!rst && enabled && !frame_ce;
    for(genvar v=0;v<VOICES;v=v+1)begin: ports
        assign voice_fcw[v*32+:32]=frequencies[v];
        assign voice_ids[v*7+:7]=ids[v];
        assign voice_timbres[v*2+:2]=timbres[v];
        assign voice_start[v]=!rst && frame_ce && pending_start[v];
        assign voice_restart[v]=voice_start[v] && pending_restart[v];
        assign voice_stop[v]=!rst && frame_ce && !pending_start[v] && committed_gate[v] && !voice_held[v];
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            owned<=0;voice_held<=0;pending_start<=0;pending_restart<=0;committed_gate<=0;
            for(integer i=0;i<VOICES;i=i+1)begin ids[i]<=0;frequencies[i]<=0;rank[i]<=i;timbres[i]<=0;end
        end else if(frame_ce)begin
            for(integer i=0;i<VOICES;i=i+1)begin
                if(pending_start[i])begin
                    pending_start[i]<=0;pending_restart[i]<=0;committed_gate[i]<=1;
                end else if(committed_gate[i] && !voice_held[i])committed_gate[i]<=0;
                if(!voice_held[i] && !voice_active[i] && !pending_start[i] && !committed_gate[i])owned[i]<=0;
            end
        end else if(note_valid && note_ready)begin
            if(note_on)begin
                owned[target]<=1;voice_held[target]<=1;ids[target]<=note_id;frequencies[target]<=note_fcw;
                pending_start[target]<=1;
                case(note_timbre)
                    2'd1:timbres[target]<=1;
                    2'd2:timbres[target]<=2;
                    default:timbres[target]<=0;
                endcase
                if(match_slot<0)pending_restart[target]<=1;
                rank[target]<=VOICES-1;
                for(integer i=0;i<VOICES;i=i+1)
                    if(i!=target && rank[i]>rank[target])rank[i]<=rank[i]-1'b1;
            end else if(match_slot>=0)begin
                // Releases for stolen note IDs are ignored. An On+Off between
                // two frames starts once, then releases at the following frame.
                voice_held[match_slot]<=0;
            end
        end
    end
    // synthesis translate_off
    initial if(VOICES<1 || VOICES>32)$fatal(1,"Invalid voice count");
    // synthesis translate_on
endmodule

