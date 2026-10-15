`timescale 1ns/1ps
`include "config/synth_config.svh"
module adsr_envelope #(
    parameter integer ATTACK=`ADSR_ATTACK_FRAMES,DECAY=`ADSR_DECAY_FRAMES,
    SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES)(
    input wire clk,rst,sample_ce,note_on,note_off,
    output reg [16:0] level,output wire active,input wire restart);
    localparam integer MAX_AD=ATTACK>DECAY?ATTACK:DECAY;
    localparam integer MAX_N=MAX_AD>RELEASE?MAX_AD:RELEASE;
    localparam integer CW=MAX_N>0?$clog2(MAX_N+1):1;
    localparam integer A_DEN=ATTACK>0?ATTACK:1,D_DEN=DECAY>0?DECAY:1,R_DEN=RELEASE>0?RELEASE:1;
    localparam [2:0] IDLE=0,A=1,D=2,S=3,R=4;
    reg [2:0] state;
    reg [CW-1:0] remaining,length,remainder,error;
    reg [16:0] base;
    wire [CW:0] error_sum={1'b0,error}+{1'b0,remainder};
    wire carry=error_sum>={1'b0,length};
    wire [17:0] delta={1'b0,base}+(carry?18'd1:18'd0);
    wire [16:0] start_level=restart?17'd0:level;
    assign active=state!=IDLE;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=IDLE;level<=0;remaining<=0;length<=1;remainder<=0;error<=0;base<=0;
        end else if(sample_ce)begin
            if(note_off && !restart)begin
                if(RELEASE==0 || level==0)begin state<=IDLE;level<=0;end
                else begin
                    state<=R;remaining<=RELEASE;length<=RELEASE;
                    base<=level/R_DEN;remainder<=level%R_DEN;error<=0;
                end
            end else if(note_on)begin
                // Same-note retrigger preserves level; a newly owned voice starts at zero.
                if(restart)level<=0;
                if(ATTACK>0)begin
                    state<=A;remaining<=ATTACK;length<=ATTACK;
                    base<=(17'd65536-start_level)/A_DEN;
                    remainder<=(17'd65536-start_level)%A_DEN;error<=0;
                end else if(DECAY>0)begin
                    state<=D;level<=65536;remaining<=DECAY;length<=DECAY;
                    base<=(65536-SUSTAIN)/D_DEN;remainder<=(65536-SUSTAIN)%D_DEN;error<=0;
                end else begin state<=S;level<=SUSTAIN;end
            end else if(restart)begin
                state<=IDLE;level<=0;remaining<=0;error<=0;
            end else if(state==A || state==D || state==R)begin
                if(remaining==1)begin
                    error<=0;
                    if(state==A)begin
                        if(DECAY>0)begin
                            level<=65536;state<=D;remaining<=DECAY;length<=DECAY;
                            base<=(65536-SUSTAIN)/D_DEN;remainder<=(65536-SUSTAIN)%D_DEN;
                        end else begin level<=SUSTAIN;state<=S;end
                    end else if(state==D)begin level<=SUSTAIN;state<=S;end
                    else begin level<=0;state<=IDLE;end
                end else begin
                    remaining<=remaining-1'b1;
                    error<=carry?error_sum-length:error_sum;
                    if(state==A)level<=level+delta;else level<=level-delta;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(ATTACK<0 || DECAY<0 || RELEASE<0 || SUSTAIN<0 || SUSTAIN>65536)
        $fatal(1,"Invalid ADSR parameters");
    // synthesis translate_on
endmodule
