`timescale 1ns/1ps
`include "../src/config/synth_config.svh"
module adsr_envelope_baseline #(
    parameter integer ATTACK=`ADSR_ATTACK_FRAMES,DECAY=`ADSR_DECAY_FRAMES,
    SUSTAIN=`ADSR_SUSTAIN_LEVEL,RELEASE=`ADSR_RELEASE_FRAMES,PRECALC=0)(
    input wire clk,rst,sample_ce,note_on,note_off,
    output reg [16:0] level,output wire active,input wire restart,
    input wire seed_valid,input wire [16:0] seed_level);
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
    wire [16:0] start_level=restart ? 17'd0 : (seed_valid===1'b1 ? seed_level : level);
    // Optional production preparation: only arithmetic latency changes.
    // The envelope still advances once per sample_ce, which must be >=4 clocks apart.
    // Default0 preserves the original single-clock component interface.
    function automatic integer factor_shift(input integer value);
        integer v;begin v=value;factor_shift=0;
            while(v>1 && v%2==0)begin factor_shift=factor_shift+1;v=v/2;end
        end
    endfunction
    localparam integer ASH=factor_shift(A_DEN),RSH=factor_shift(R_DEN);
    localparam integer AH=17>ASH ? 17-ASH : 1,RH=17>RSH ? 17-RSH : 1;
    localparam integer AODD=A_DEN>>ASH,RODD=R_DEN>>RSH;
    // Exact reciprocal for the entire reduced numerator width: K=N+ceil(log2 D).
    // The ceil reciprocal error is <1/D over 0..2^N-1, so floor is unchanged.
    localparam integer AK=AH+$clog2(AODD),RK=RH+$clog2(RODD);
    localparam [AH:0] AM=((64'd1<<AK)+AODD-1)/AODD;
    localparam [RH:0] RM=((64'd1<<RK)+RODD-1)/RODD;
    wire [16:0] seed=seed_valid===1'b1 ? seed_level : level;
    wire [16:0] attack_q,release_q;
    wire [CW-1:0] attack_r,release_r;
    generate if(PRECALC!=0)begin: preparation
        reg [16:0] an,rn,ad,rd,aq,rq;
        reg [CW-1:0] arem,rrem;
        wire [AH-1:0] ahigh=an>>ASH;
        wire [RH-1:0] rhigh=rn>>RSH;
        wire [2*AH:0] aproduct=ahigh*AM;
        wire [2*RH:0] rproduct=rhigh*RM;
        always @(posedge clk or posedge rst)begin
            if(rst)begin an<=0;rn<=0;ad<=0;rd<=0;aq<=0;rq<=0;arem<=0;rrem<=0;end
            else begin
                an<=17'd65536-seed;rn<=level;
                ad<=an;rd<=rn;aq<=aproduct>>AK;rq<=rproduct>>RK;
                arem<=ad-aq*A_DEN;rrem<=rd-rq*R_DEN;
            end
        end
        assign attack_q=restart ? (65536/A_DEN) : aq;
        assign attack_r=restart ? (65536%A_DEN) : arem;
        assign release_q=rq;assign release_r=rrem;
    end else begin: direct_calculation
        assign attack_q=(17'd65536-start_level)/A_DEN;
        assign attack_r=(17'd65536-start_level)%A_DEN;
        assign release_q=level/R_DEN;assign release_r=level%R_DEN;
    end endgenerate
    assign active=state!=IDLE;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=IDLE;level<=0;remaining<=0;length<=1;remainder<=0;error<=0;base<=0;
        end else if(sample_ce)begin
            if(note_off && !restart)begin
                if(RELEASE==0 || level==0)begin state<=IDLE;level<=0;end
                else begin
                    state<=R;remaining<=RELEASE;length<=RELEASE;
                    base<=release_q;remainder<=release_r;error<=0;
                end
            end else if(note_on)begin
                // Same-note retrigger preserves level; a newly owned voice starts at zero.
                if(restart)level<=0;
                else if(seed_valid===1'b1)level<=seed_level;
                if(ATTACK>0)begin
                    state<=A;remaining<=ATTACK;length<=ATTACK;
                    base<=attack_q;
                    remainder<=attack_r;error<=0;
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
