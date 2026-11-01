`timescale 1ns/1ps
// One exact preparation pipeline visits all physical voices between sample CEs.
// Inputs may change only on sample_ce. The interval must be >= VOICES+5 clocks.
module envelope_precalc_bank #(
 parameter integer VOICES=32,ATTACK=480,DECAY=4800,RELEASE=9600,
 MAX_AD=ATTACK>DECAY?ATTACK:DECAY,MAX_N=MAX_AD>RELEASE?MAX_AD:RELEASE,
 CW=MAX_N>0?$clog2(MAX_N+1):1)(
 input wire clk,rst,sample_ce,input wire [17*VOICES-1:0] seeds,levels,
 output wire [17*VOICES-1:0] attack_q,release_q,
 output wire [CW*VOICES-1:0] attack_r,release_r);
 localparam integer IW=VOICES>1?$clog2(VOICES):1;
 localparam integer A_DEN=ATTACK>0?ATTACK:1,R_DEN=RELEASE>0?RELEASE:1;
 function automatic integer factor_shift(input integer value);
  integer n;begin n=value;factor_shift=0;while(n>1 && n%2==0)begin factor_shift=factor_shift+1;n=n/2;end end
 endfunction
 localparam integer ASH=factor_shift(A_DEN),RSH=factor_shift(R_DEN);
 localparam integer AH=17>ASH?17-ASH:1,RH=17>RSH?17-RSH:1;
 localparam integer AODD=A_DEN>>ASH,RODD=R_DEN>>RSH;
 localparam integer AK=AH+$clog2(AODD),RK=RH+$clog2(RODD);
 localparam [AH:0] AM=((64'd1<<AK)+AODD-1)/AODD;
 localparam [RH:0] RM=((64'd1<<RK)+RODD-1)/RODD;
 reg busy;reg [IW-1:0] index,index0,index1,index2;
 reg valid0,valid1,valid2;
 reg [1:0] reset_age;
 reg [16:0] an,rn,ad,rd,aq,rq,aq2,rq2;
 reg [CW-1:0] ar,rr;
 wire [AH-1:0] ahigh=an>>ASH;wire [RH-1:0] rhigh=rn>>RSH;
 wire [2*AH:0] aproduct=ahigh*AM;wire [2*RH:0] rproduct=rhigh*RM;
 reg [16:0] aq_bank[0:VOICES-1],rq_bank[0:VOICES-1];
 reg [CW-1:0] ar_bank[0:VOICES-1],rr_bank[0:VOICES-1];
 // Retain the original reset warm-up values at the first two/three clocks.
 for(genvar v=0;v<VOICES;v=v+1)begin: outputs
  assign attack_q[v*17+:17]=reset_age>=2?aq_bank[v]:17'd0;
  assign attack_r[v*CW+:CW]=reset_age>=3?ar_bank[v]:{CW{1'b0}};
  assign release_q[v*17+:17]=rq_bank[v];assign release_r[v*CW+:CW]=rr_bank[v];
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   busy<=0;index<=0;index0<=0;index1<=0;index2<=0;valid0<=0;valid1<=0;valid2<=0;
   an<=0;rn<=0;ad<=0;rd<=0;aq<=0;rq<=0;aq2<=0;rq2<=0;ar<=0;rr<=0;reset_age<=0;
   for(integer v=0;v<VOICES;v=v+1)begin aq_bank[v]<=65536/A_DEN;ar_bank[v]<=65536%A_DEN;rq_bank[v]<=0;rr_bank[v]<=0;end
  end else begin
   if(reset_age!=3)reset_age<=reset_age+1'b1;
   // Restart once after reset and once after each atomic sample update.
   if(sample_ce || reset_age==0)begin busy<=1;index<=0;end
   else if(busy)begin if(index==VOICES-1)busy<=0;else index<=index+1'b1;end
   valid0<=busy && !sample_ce;index0<=index;
   if(busy && !sample_ce)begin an<=17'd65536-seeds[index*17+:17];rn<=levels[index*17+:17];end
   valid1<=valid0;index1<=index0;ad<=an;rd<=rn;aq<=aproduct>>AK;rq<=rproduct>>RK;
   valid2<=valid1;index2<=index1;aq2<=aq;rq2<=rq;ar<=ad-aq*A_DEN;rr<=rd-rq*R_DEN;
   if(valid2)begin aq_bank[index2]<=aq2;rq_bank[index2]<=rq2;ar_bank[index2]<=ar;rr_bank[index2]<=rr;end
  end
 end
 // synthesis translate_off
 integer since_ce;
 reg previous_ce;reg [17*VOICES-1:0] previous_seeds,previous_levels;
 always @(posedge clk or posedge rst)begin
  if(rst)begin previous_ce<=1;previous_seeds<=0;previous_levels<=0;end
  else begin
   if(!previous_ce && (seeds!==previous_seeds || levels!==previous_levels))$fatal(1,"Envelope preparation inputs changed between sample updates");
   previous_ce<=sample_ce;previous_seeds<=seeds;previous_levels<=levels;
  end
 end
 always @(posedge clk or posedge rst)
  if(rst)since_ce<=VOICES+5;
  else if(sample_ce)begin
   if(since_ce<VOICES+5)$fatal(1,"Shared envelope preparation sample interval too short");
   since_ce<=1;
  end else if(since_ce<VOICES+5)since_ce<=since_ce+1;
 // synthesis translate_on
endmodule
