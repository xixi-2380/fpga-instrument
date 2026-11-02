`timescale 1ns/1ps
// Reference-domain distance conditioning and a narrow serial ratio divider.
// The sensor changes pitch only; it has no connection to master volume.
module ultrasonic_pitch #(parameter integer CLOCK_HZ=50000000,LOST_MS=250)(
 input wire clk,rst,cfg_valid,enabled,input wire [2:0] sensitivity,
 input wire [6:0] minimum,maximum,input wire [7:0] version,
 input wire report,valid,input wire [12:0] distance_mm,
 output reg [17:0] target_ratio,output reg [2:0] status,
 output reg [11:0] distance_bcd,output reg [7:0] applied_version);
 localparam [2:0] OFF=0,WAITING=1,TRACKING=2,HOLDING=3,LOST=4;
 localparam MD=CLOCK_HZ/1000,MW=MD>1?$clog2(MD):1,AW=LOST_MS>1?$clog2(LOST_MS+1):1;
 reg [MW-1:0] millisecond;reg [AW-1:0] age;
 reg active,have_sample;reg [12:0] recent,older;
 wire [12:0] d=distance_mm;
 wire [12:0] median=d<recent ? (recent<older?recent:(d<older?older:d)) : (d<older?d:(recent<older?older:recent));
 wire [12:0] filtered=have_sample?median:d;
 wire [12:0] near_mm={6'd0,minimum}*13'd10,far_mm={6'd0,maximum}*13'd10;
 wire [12:0] midpoint=(near_mm+far_mm)>>1;
 wire [3:0] deadband=sensitivity>=1 && sensitivity<=5?4'd6-{1'b0,sensitivity}:4'd5;
 wire usable=valid && d>=20 && d<=4000;
 wire configuration_changed=active!=enabled || applied_version!=version;
 reg [1:0] map_stage;reg negative;
 reg [12:0] delta;reg [13:0] scale;reg [10:0] divisor;
 reg [23:0] numerator;reg [10:0] remainder;reg [13:0] quotient;reg [4:0] bits_left;
 wire [11:0] trial={remainder,numerator[23]};
 wire subtract=trial>={1'b0,divisor};
 wire [10:0] next_remainder=subtract?trial-{1'b0,divisor}:trial;
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
     binary_bcd<=d>999?10'd999:d[9:0];bcd_work<=0;bcd_left<=10;
     if(filtered<=near_mm)begin target_ratio<=73562;map_stage<=0;end
     else if(filtered>=far_mm)begin target_ratio<=58386;map_stage<=0;end
     else if(filtered+deadband>=midpoint && filtered<=midpoint+deadband)begin target_ratio<=65536;map_stage<=0;end
     else begin
      negative<=filtered>midpoint;
      delta<=filtered>midpoint?filtered-midpoint:midpoint-filtered;
      divisor<=filtered>midpoint?far_mm-midpoint:midpoint-near_mm;
      scale<=filtered>midpoint?14'd7150:14'd8026;map_stage<=1;
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
