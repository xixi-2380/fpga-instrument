`timescale 1ns/1ps
`include "config/synth_config.svh"
// File-backed event source. No melody, harmony, keyboard mapping or synthesis
// logic lives here. ROM is initialized at FPGA configuration, not runtime I/O.
module score_player #(
    parameter SCORE_FILE="src/scores/twinkle.hex",
    parameter integer SCORE_WORDS=512,ENABLE=1,BEAT_FRAMES=(`SAMPLE_HZ/2),
    TAIL_FRAMES=(`ADSR_RELEASE_FRAMES+4))(
    input wire clk,rst,input_ready,frame_ce,note_ready,
    output wire note_valid,note_on,output wire [6:0] note_id,
    output wire [31:0] note_fcw,output wire [4:0] note_timbre,
    output wire busy,done,output reg error);
    localparam integer AW=SCORE_WORDS>1?$clog2(SCORE_WORDS):1;
    localparam integer TICK_FRAMES=BEAT_FRAMES/4;
    localparam integer MAX_FRAMES=TICK_FRAMES>TAIL_FRAMES?TICK_FRAMES:TAIL_FRAMES;
    localparam integer CW=MAX_FRAMES>0?$clog2(MAX_FRAMES+1):1;
    localparam [3:0] WAIT_START=0,FETCH=1,DECODE=2,SEND=3,WAIT_TIME=4,
        TAIL=5,DONE=6,NEXT=7,FAULT=8;
    reg [63:0] rom[0:SCORE_WORDS-1];
    reg [63:0] instruction;
    reg [AW-1:0] pc;
    reg [3:0] state;
    reg [31:0] ticks_left;
    reg [CW-1:0] elapsed;
    initial if(ENABLE)$readmemh(SCORE_FILE,rom);
    // Synchronous read, matching the project's waveform ROM convention.
    always @(posedge clk)if(ENABLE)instruction<=rom[pc];
    assign busy=ENABLE && state!=DONE;
    assign done=!ENABLE || state==DONE;
    assign note_valid=!rst && ENABLE && state==SEND;
    assign note_on=instruction[63:60]==4'h2;
    assign note_id=instruction[40:34];
    assign note_timbre={2'd0,instruction[41],instruction[33:32]};
    assign note_fcw=instruction[31:0];
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=ENABLE?WAIT_START:DONE;pc<=0;elapsed<=0;ticks_left<=0;error<=0;
        end else case(state)
            WAIT_START:if(input_ready)state<=FETCH;
            FETCH:state<=DECODE;
            DECODE:case(instruction[63:60])
                4'h0:begin elapsed<=0;state<=TAIL_FRAMES==0?DONE:TAIL;end
                4'h1:begin
                    elapsed<=0;ticks_left<=instruction[31:0];
                    state<=instruction[31:0]==0?NEXT:WAIT_TIME;
                end
                4'h2,4'h3:state<=SEND;
                default:begin state<=FAULT;error<=1;end
            endcase
            SEND:if(note_ready)state<=NEXT;
            WAIT_TIME:if(frame_ce)begin
                if(elapsed==TICK_FRAMES-1)begin
                    elapsed<=0;
                    if(ticks_left==1)state<=NEXT;
                    else ticks_left<=ticks_left-1'b1;
                end else elapsed<=elapsed+1'b1;
            end
            NEXT:if(pc==SCORE_WORDS-1)begin state<=FAULT;error<=1;end
                 else begin pc<=pc+1'b1;state<=FETCH;end
            TAIL:if(frame_ce)begin
                if(elapsed==TAIL_FRAMES-1)begin state<=DONE;elapsed<=0;end
                else elapsed<=elapsed+1'b1;
            end
            DONE:state<=DONE;
            FAULT:state<=FAULT; // Invalid ROM never hands an unfinished score to the keyboard.
            default:begin state<=FAULT;error<=1;end
        endcase
    end
    // synthesis translate_off
    integer score_fd;
    initial begin
        if(SCORE_WORDS<1 || BEAT_FRAMES<4 || BEAT_FRAMES%4!=0 || TAIL_FRAMES<0)
            $fatal(1,"Invalid score configuration: beat frames must be a positive multiple of four");
        if(ENABLE)begin
            score_fd=$fopen(SCORE_FILE,"r");
            if(!score_fd)$fatal(1,"Cannot open score file: %s",SCORE_FILE);
            $fclose(score_fd);
        end
    end
    always @(posedge clk)if(!rst && ENABLE && state==DECODE)begin
        if((^instruction)===1'bx)$fatal(1,"Uninitialized score ROM at address %0d",pc);
        if((instruction[63:60]==2 || instruction[63:60]==3) &&
           (instruction[59:42]!=0 || {instruction[41],instruction[33:32]}>6 || instruction[31:0]==0))
            $fatal(1,"Invalid score event at address %0d",pc);
    end
    // synthesis translate_on
endmodule
