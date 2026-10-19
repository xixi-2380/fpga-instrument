`timescale 1ns/1ps
`include "config/synth_config.svh"
// Autonomous, keyboard-independent valid/ready source. Lanes 0..3 are score
// identities; keyboard IDs 60..75 remain disjoint. Only frame_ce counts time.
module score_player #(
    parameter integer ENABLE=1,BEAT_FRAMES=(`SAMPLE_HZ/2),TAIL_FRAMES=(`ADSR_RELEASE_FRAMES+4),
    MELODY_TIMBRE=1,CHORD_TIMBRE=0)(
    input wire clk,rst,input_ready,frame_ce,note_ready,
    output wire note_valid,note_on,output wire [6:0] note_id,
    output wire [31:0] note_fcw,output wire [1:0] note_timbre,
    output wire busy,done);
    `include "config/demo_score.svh"
    localparam integer LONG_FRAMES=2*BEAT_FRAMES;
    localparam integer MAX_FRAMES=LONG_FRAMES>TAIL_FRAMES?LONG_FRAMES:TAIL_FRAMES;
    localparam integer CW=MAX_FRAMES>0?$clog2(MAX_FRAMES+1):1;
    localparam [2:0] WAIT_START=0,NOTE_ON=1,HOLD=2,NOTE_OFF=3,GAP=4,TAIL=5,DONE=6;
    localparam [CW-1:0] SHORT_GATE=(3*BEAT_FRAMES)/4,LONG_GATE=(3*LONG_FRAMES)/4;
    localparam [CW-1:0] SHORT_GAP=BEAT_FRAMES-(3*BEAT_FRAMES)/4;
    localparam [CW-1:0] LONG_GAP=LONG_FRAMES-(3*LONG_FRAMES)/4;
    reg [2:0] state;
    reg [5:0] step_index;
    reg [1:0] lane;
    reg [CW-1:0] elapsed;
    wire [7:0] step_data=score_step(step_index);
    wire [CW-1:0] gate_frames=step_data[7]?LONG_GATE:SHORT_GATE;
    wire [CW-1:0] gap_frames=step_data[7]?LONG_GAP:SHORT_GAP;
    assign busy=ENABLE && state!=DONE;
    assign done=!ENABLE || state==DONE;
    assign note_valid=!rst && ENABLE && (state==NOTE_ON || state==NOTE_OFF);
    assign note_on=state==NOTE_ON;
    assign note_id={5'b0,lane};
    assign note_fcw=score_fcw(score_pitch(step_data[6:0],lane));
    assign note_timbre=lane==0?MELODY_TIMBRE:CHORD_TIMBRE;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=ENABLE?WAIT_START:DONE;step_index<=0;lane<=0;elapsed<=0;
        end else case(state)
            WAIT_START:if(input_ready)begin state<=NOTE_ON;lane<=0;end
            NOTE_ON:if(note_ready)begin
                if(lane==3)begin state<=HOLD;lane<=0;elapsed<=0;end
                else lane<=lane+1'b1;
            end
            HOLD:if(frame_ce)begin
                if(elapsed==gate_frames-1'b1)begin state<=NOTE_OFF;lane<=0;elapsed<=0;end
                else elapsed<=elapsed+1'b1;
            end
            NOTE_OFF:if(note_ready)begin
                if(lane==3)begin
                    lane<=0;elapsed<=0;
                    if(step_index==41)state<=TAIL_FRAMES==0?DONE:TAIL;
                    else state<=GAP;
                end else lane<=lane+1'b1;
            end
            GAP:if(frame_ce)begin
                if(elapsed==gap_frames-1'b1)begin
                    step_index<=step_index+1'b1;state<=NOTE_ON;lane<=0;elapsed<=0;
                end else elapsed<=elapsed+1'b1;
            end
            TAIL:if(frame_ce)begin
                if(elapsed==TAIL_FRAMES-1)begin state<=DONE;elapsed<=0;end
                else elapsed<=elapsed+1'b1;
            end
            DONE:state<=DONE;
            default:state<=ENABLE?WAIT_START:DONE;
        endcase
    end
    // synthesis translate_off
    initial if(BEAT_FRAMES<4 || TAIL_FRAMES<0 || MELODY_TIMBRE<0 ||
               MELODY_TIMBRE>2 || CHORD_TIMBRE<0 || CHORD_TIMBRE>2)
        $fatal(1,"Invalid score configuration");
    // synthesis translate_on
endmodule
