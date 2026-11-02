`timescale 1ns/1ps
// Whole-cm median conditioning and a narrow serial ratio divider.
// The sensor changes pitch only; it has no connection to master volume.
// sensitivity retains its public control name but is a direct 1..5cm neutral
// half-width. Endpoints always win over the neutral band on narrow ranges.
module ultrasonic_pitch #(parameter integer CLOCK_HZ=50000000,LOST_MS=250)(
 input wire clk,rst,cfg_valid,enabled,input wire [2:0] sensitivity,
 input wire [6:0] minimum,maximum,input wire [7:0] version,
 input wire report,valid,input wire [12:0] distance_cm,
 output reg [17:0] target_ratio,output reg [2:0] status,
 output reg [11:0] distance_bcd,output reg [7:0] applied_version);
 localparam [2:0] OFF=0,WAITING=1,TRACKING=2,HOLDING=3,LOST=4;
 localparam MD=CLOCK_HZ/1000,MW=MD>1?$clog2(MD):1,AW=LOST_MS>1?$clog2(LOST_MS+1):1;
 reg [MW-1:0] millisecond;reg [AW-1:0] age;
 reg active,have_sample;reg [8:0] recent,older;
 wire [8:0] d=distance_cm[8:0];
 wire [8:0] median=d<recent ? (recent<older?recent:(d<older?older:d)) : (d<older?d:(recent<older?older:recent));
 wire [8:0] filtered=have_sample?median:d;
 // Doubled cm preserves half-cm midpoints for odd endpoint spans. Thus a
 // setting of 1 is exactly +/-1cm, not a reversed millimetre sensitivity.
 wire [7:0] midpoint2={1'b0,minimum}+{1'b0,maximum};
 wire [9:0] filtered2={filtered,1'b0};
 wire [9:0] offset2=filtered2>{2'd0,midpoint2}?filtered2-{2'd0,midpoint2}:{2'd0,midpoint2}-filtered2;
 wire [2:0] deadband_cm=sensitivity>=1 && sensitivity<=5?sensitivity:3'd1;
 wire [3:0] deadband2={deadband_cm,1'b0};
 wire [7:0] span={1'b0,maximum}-{1'b0,minimum};
 wire usable=valid && distance_cm>=2 && distance_cm<=400;
 wire configuration_changed=active!=enabled || applied_version!=version;
 reg [1:0] map_stage;reg negative;
 reg [7:0] delta;reg [13:0] scale;reg [7:0] divisor;
 reg [23:0] numerator;reg [7:0] remainder;reg [13:0] quotient;reg [4:0] bits_left;
 wire [8:0] trial={remainder,numerator[23]};
 wire subtract=trial>={1'b0,divisor};
 wire [7:0] next_remainder=subtract?trial-{1'b0,divisor}:trial;
 wire [13:0] next_quotient={quotient[12:0],subtract};
 reg [9:0] binary_bcd;reg [11:0] bcd_work,bcd_adjusted;reg [3:0] bcd_left;
 always @*begin
  bcd_adjusted=bcd_work;
  for(integer j=0;j<3;j=j+1)if(bcd_work[j*4+:4]>=5)bcd_adjusted[j*4+:4]=bcd_work[j*4+:4]+4'd3;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   millisecond<=0;age<=0;active<=0;have_sample<=0;recent<=0;older<=0;
   target_ratio<=65536;status<=OFF;distance_bcd<=0;applied_version<=0;
   map_stage<=0;negative<=0;delta<=0;scale<=0;divisor<=1;numerator<=0;remainder<=0;quotient<=0;bits_left<=0;
   binary_bcd<=0;bcd_work<=0;bcd_left<=0;
  end else begin
   if(millisecond==MD-1)begin millisecond<=0;if(age<LOST_MS)age<=age+1'b1;end
   else millisecond<=millisecond+1'b1;
   if(bcd_left!=0)begin
    binary_bcd<=binary_bcd<<1;bcd_work<={bcd_adjusted[10:0],binary_bcd[9]};bcd_left<=bcd_left-1'b1;
    if(bcd_left==1)distance_bcd<={bcd_adjusted[10:0],binary_bcd[9]};
   end
   if(!cfg_valid || !enabled || maximum<=minimum)begin
    active<=0;have_sample<=0;age<=0;map_stage<=0;target_ratio<=65536;status<=OFF;applied_version<=version;
   end else if(configuration_changed)begin
    active<=1;have_sample<=0;age<=0;map_stage<=0;target_ratio<=65536;status<=WAITING;applied_version<=version;
   end else begin
    if(age==LOST_MS)begin target_ratio<=65536;status<=LOST;map_stage<=0;end
    if(report && usable)begin
     recent<=d;older<=have_sample?recent:d;have_sample<=1;age<=0;status<=TRACKING;
     binary_bcd<={1'b0,d};bcd_work<=0;bcd_left<=10;
     if(filtered<=minimum)begin target_ratio<=73562;map_stage<=0;end
     else if(filtered>=maximum)begin target_ratio<=58386;map_stage<=0;end
     // Endpoints above keep full bend even when the requested band covers
     // every strict interior point. This branch also prevents zero division.
     else if(span<={4'd0,deadband2} || offset2<={6'd0,deadband2})begin target_ratio<=65536;map_stage<=0;end
     else begin
      negative<=filtered2>{2'd0,midpoint2};
      delta<=offset2-{6'd0,deadband2};
      divisor<=span-{4'd0,deadband2};
      scale<=filtered2>{2'd0,midpoint2}?14'd7150:14'd8026;map_stage<=1;
     end
    end else if(report && !usable)begin
     if(have_sample && age<LOST_MS)status<=HOLDING;
    end else if(age<LOST_MS && map_stage==1)begin
     numerator<=delta*scale+(divisor>>1);remainder<=0;quotient<=0;bits_left<=24;map_stage<=2;
    end else if(age<LOST_MS && map_stage==2)begin
     numerator<=numerator<<1;remainder<=next_remainder;quotient<=next_quotient;bits_left<=bits_left-1'b1;
     if(bits_left==1)begin target_ratio<=negative?18'd65536-next_quotient:18'd65536+next_quotient;map_stage<=0;end
    end
   end
  end
 end
 // synthesis translate_off
 initial if(CLOCK_HZ<1000 || CLOCK_HZ%1000!=0 || LOST_MS<1)$fatal(1,"Invalid ultrasonic pitch timing");
 always @(posedge clk)if(!rst && (target_ratio<58386 || target_ratio>73562))$fatal(1,"Ultrasonic pitch escaped +/-2 semitones");
 // synthesis translate_on
endmodule
