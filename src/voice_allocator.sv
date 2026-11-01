`timescale 1ns/1ps
// Keyboard-independent ownership and pending frame commands. Rank is a
// bounded permutation, avoiding the wraparound of timestamp-based stealing.
module voice_allocator #(parameter integer VOICES=4,AUTOMATIC_IDS=0,PRESERVE_MANUAL_TAILS=0,GATE_FRAME_COMMANDS=1)(
    input wire clk,rst,enabled,frame_ce,note_valid,note_on,
    input wire [6:0] note_id,input wire [31:0] note_fcw,
    input wire [VOICES-1:0] voice_active,
    output wire note_ready,output wire [VOICES-1:0] voice_start,voice_stop,voice_restart,
    output reg [VOICES-1:0] voice_held,
    output wire [VOICES*32-1:0] voice_fcw,
    output wire [VOICES*7-1:0] voice_ids,input wire [4:0] note_timbre,
    output wire [VOICES*5-1:0] voice_timbres,
    // Automatic scheduler IDs describe held notes, not release-tail ownership.
    input wire note_independent,input wire [8:0] note_gain,input wire [6:0] note_pitch,
    output wire [VOICES*9-1:0] voice_gains,output wire [VOICES*7-1:0] voice_pitches);
    localparam integer RW=VOICES>1?$clog2(VOICES):1;
    reg [VOICES-1:0] owned,pending_start,pending_restart,committed_gate;
    reg [6:0] ids [0:VOICES-1];
    reg [31:0] frequencies [0:VOICES-1];
    reg [RW-1:0] rank [0:VOICES-1];
    reg [4:0] timbres[0:VOICES-1];
    reg [8:0] gains[0:VOICES-1];reg [6:0] pitches[0:VOICES-1];
    // Read one context, then compare its registered metadata. No candidate
    // index feeds another context read in the same cycle. The producer holds
    // the event until OFFER; ownership still changes on its handshake edge.
    localparam [2:0] IDLE=0,READ_CONTEXT=1,COMPARE=2,SELECT=3,OFFER=4;
    reg [2:0] search_state;
    reg [RW-1:0] scan_slot,scan_rank;
    reg scan_match,scan_free,scan_released;
    reg match_found,free_found,released_found,oldest_found;
    reg [RW-1:0] match_slot,free_slot,released_slot,oldest_slot,target;
    reg [RW-1:0] match_rank,free_rank,released_rank,oldest_rank,target_rank;
    reg target_matched;
    reg event_on,event_independent;reg [8:0] event_gain;reg [6:0] event_pitch;
    reg [6:0] event_id;
    reg [31:0] event_fcw;
    reg [4:0] event_timbre;
    assign note_ready=!rst && enabled && !frame_ce && search_state==OFFER;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            search_state<=IDLE;scan_slot<=0;scan_rank<=0;
            scan_match<=0;scan_free<=0;scan_released<=0;
            match_found<=0;free_found<=0;released_found<=0;oldest_found<=0;
            match_slot<=0;free_slot<=0;released_slot<=0;oldest_slot<=0;target<=0;
            match_rank<=0;free_rank<=0;released_rank<=0;oldest_rank<=0;target_rank<=0;
            target_matched<=0;event_independent<=0;event_gain<=256;event_pitch<=0;event_on<=0;event_id<=0;event_fcw<=0;event_timbre<=0;
        end else if(frame_ce || !enabled)begin
            // A frame can retire an ownership or change active flags. Cancel
            // the unacknowledged search and retry against the new snapshot.
            search_state<=IDLE;
        end else case(search_state)
            IDLE:if(note_valid)begin
                event_on<=note_on;event_id<=note_id;event_fcw<=note_fcw;
                event_independent<=note_independent===1'b1;
                event_gain<=note_independent===1'b1 ? note_gain : 9'd256;
                event_pitch<=note_independent===1'b1 ? note_pitch : note_id;
                if(note_timbre<=25)event_timbre<=note_timbre;else event_timbre<=0;
                scan_slot<=0;match_found<=0;free_found<=0;
                released_found<=0;oldest_found<=0;
                search_state<=READ_CONTEXT;
            end
            READ_CONTEXT:begin
                scan_rank<=rank[scan_slot];
                // A released automatic ID may be reused immediately by the score.
                // Never retune that release tail: match only its held/pending
                // owner; the new On allocates a free or oldest released slot.
                scan_match<=owned[scan_slot] && ids[scan_slot]==event_id &&
                    ((!PRESERVE_MANUAL_TAILS && !event_independent && event_id>=AUTOMATIC_IDS) || voice_held[scan_slot] || pending_start[scan_slot]);
                scan_free<=!owned[scan_slot] ||
                    (!voice_active[scan_slot] && !voice_held[scan_slot] &&
                     !pending_start[scan_slot] && !committed_gate[scan_slot]);
                scan_released<=owned[scan_slot] && !voice_held[scan_slot] && !pending_start[scan_slot];
                search_state<=COMPARE;
            end
            COMPARE:begin
                if(scan_match)begin
                    match_found<=1;match_slot<=scan_slot;match_rank<=scan_rank;
                end
                if(scan_free && !free_found)begin
                    free_found<=1;free_slot<=scan_slot;free_rank<=scan_rank;
                end
                if(scan_released && (!released_found || scan_rank<released_rank))begin
                    released_found<=1;released_slot<=scan_slot;released_rank<=scan_rank;
                end
                if(!oldest_found || scan_rank<oldest_rank)begin
                    oldest_found<=1;oldest_slot<=scan_slot;oldest_rank<=scan_rank;
                end
                if(scan_slot==VOICES-1)search_state<=SELECT;
                else begin scan_slot<=scan_slot+1'b1;search_state<=READ_CONTEXT;end
            end
            SELECT:begin
                target_matched<=match_found;
                if(match_found)begin target<=match_slot;target_rank<=match_rank;end
                else if(free_found)begin target<=free_slot;target_rank<=free_rank;end
                else if(released_found)begin target<=released_slot;target_rank<=released_rank;end
                else begin target<=oldest_slot;target_rank<=oldest_rank;end
                search_state<=OFFER;
            end
            OFFER:search_state<=IDLE;
            default:search_state<=IDLE;
        endcase
    end
    for(genvar v=0;v<VOICES;v=v+1)begin: ports
        assign voice_fcw[v*32+:32]=frequencies[v];
        assign voice_ids[v*7+:7]=ids[v];
        assign voice_timbres[v*5+:5]=timbres[v];
        assign voice_gains[v*9+:9]=gains[v];assign voice_pitches[v*7+:7]=pitches[v];
        assign voice_start[v]=!rst && (GATE_FRAME_COMMANDS==0 || frame_ce) && pending_start[v];
        assign voice_restart[v]=voice_start[v] && pending_restart[v];
        assign voice_stop[v]=!rst && (GATE_FRAME_COMMANDS==0 || frame_ce) && !pending_start[v] && committed_gate[v] && !voice_held[v];
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            owned<=0;voice_held<=0;pending_start<=0;pending_restart<=0;committed_gate<=0;
            for(integer i=0;i<VOICES;i=i+1)begin ids[i]<=0;frequencies[i]<=0;rank[i]<=i;timbres[i]<=0;gains[i]<=256;pitches[i]<=0;end
        end else if(frame_ce)begin
            for(integer i=0;i<VOICES;i=i+1)begin
                if(pending_start[i])begin
                    pending_start[i]<=0;pending_restart[i]<=0;committed_gate[i]<=1;
                end else if(committed_gate[i] && !voice_held[i])committed_gate[i]<=0;
                if(!voice_held[i] && !voice_active[i] && !pending_start[i] && !committed_gate[i])owned[i]<=0;
            end
        end else if(note_valid && note_ready)begin
            // Constant-index writes avoid a variable bit-write barrel network.
            // target_rank was captured during search, not read through target.
            for(integer i=0;i<VOICES;i=i+1)begin
                if(event_on)begin
                    if(target==i)begin
                        owned[i]<=1;voice_held[i]<=1;ids[i]<=event_id;
                        frequencies[i]<=event_fcw;timbres[i]<=event_timbre;gains[i]<=event_gain;pitches[i]<=event_pitch;
                        pending_start[i]<=1;
                        if(!target_matched)pending_restart[i]<=1;
                        rank[i]<=VOICES-1;
                    end else if(rank[i]>target_rank)rank[i]<=rank[i]-1'b1;
                end else if(target_matched && target==i)begin
                    // Ignore releases for stolen IDs. On+Off before a frame
                    // still starts once and releases on the following frame.
                    voice_held[i]<=0;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(VOICES<1 || VOICES>32)$fatal(1,"Invalid voice count");
    always @(posedge clk)if(!rst)begin
        if(search_state!=IDLE && scan_slot>=VOICES)$fatal(1,"Search context out of range");
        if(note_valid && note_ready &&
           ({note_on,note_id,note_fcw}!=={event_on,event_id,event_fcw}))
            $fatal(1,"Producer changed an unacknowledged note event");
    end
    // synthesis translate_on
endmodule

