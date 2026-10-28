`timescale 1ns/1ps
// Ref-domain median filtering, freshness and bounded distance-to-volume map.
// Inputs arrive as one atomic configuration. Version tags reject old targets
// after UI edits; no distance arithmetic is placed in audio/pixel domains.
module ultrasonic_volume #(parameter integer CLOCK_HZ=50000000,LOST_MS=1000)(
 input wire clk,rst,cfg_valid,enabled,input wire [2:0] sensitivity,
 input wire [6:0] minimum,maximum,manual_percent,input wire [7:0] version,
 input wire report,valid,input wire [12:0] distance_mm,
 output reg [6:0] target,output reg [2:0] status,
 output reg [11:0] distance_bcd,output reg [7:0] applied_version);
 localparam [2:0] OFF=0,WAITING=1,TRACKING=2,HOLDING=3,LOST=4;
 localparam integer MS_DIV=CLOCK_HZ/1000,MW=$clog2(MS_DIV),AW=$clog2(LOST_MS+1);
 reg [MW-1:0] ms_count;reg [AW-1:0] age;
 reg active,have_sample,busy,last_good;
 reg [8:0] recent,older;
 reg [15:0] remainder;
 reg [6:0] quotient,map_min;
 reg [8:0] map_span;
 reg [3:0] bcd_left;reg [8:0] bcd_binary;reg [11:0] bcd_work,bcd_adjusted;
 wire ms_ce=ms_count==MS_DIV-1;
 wire cfg_changed=applied_version!=version || active!=enabled;
 wire usable=valid && distance_mm>=20 && distance_mm<=400;
 wire [8:0] d=distance_mm[8:0];
 wire [8:0] median=(d<recent) ? (recent<older ? recent : (d<older ? older : d)) :
                                    (d<older ? d : (recent<older ? older : recent));
 wire [8:0] filtered=have_sample ? median : d;
 reg [8:0] span;
 always @*begin
  case(sensitivity)2:span=300;3:span=250;4:span=200;5:span=150;default:span=350;endcase
  bcd_adjusted=bcd_work;
  for(integer i=0;i<3;i=i+1)
   if(bcd_work[i*4+:4]>=5)bcd_adjusted[i*4+:4]=bcd_work[i*4+:4]+4'd3;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   ms_count<=0;age<=0;active<=0;have_sample<=0;last_good<=0;busy<=0;
   recent<=0;older<=0;remainder<=0;quotient<=0;map_min<=0;map_span<=1;
   target<=100;status<=OFF;distance_bcd<=0;applied_version<=0;
   bcd_left<=0;bcd_binary<=0;bcd_work<=0;
  end else begin
   if(ms_ce)ms_count<=0;else ms_count<=ms_count+1'b1;
   if(bcd_left!=0)begin
    bcd_binary<=bcd_binary<<1;bcd_work<={bcd_adjusted[10:0],bcd_binary[8]};bcd_left<=bcd_left-1'b1;
    if(bcd_left==1)distance_bcd<={bcd_adjusted[10:0],bcd_binary[8]};
   end
   if(!cfg_valid || !enabled)begin
    active<=0;target<=manual_percent;status<=OFF;age<=0;have_sample<=0;
    busy<=0;last_good<=0;bcd_left<=0;applied_version<=version;
   end else if(cfg_changed)begin
    active<=1;applied_version<=version;busy<=0;
    // Clamp the target immediately; the audio arbiter performs the smooth handover.
    if(!active)begin
     age<=0;have_sample<=0;last_good<=0;status<=WAITING;
     target<=manual_percent<minimum ? minimum : manual_percent>maximum ? maximum : manual_percent;
    end else target<=target<minimum ? minimum : target>maximum ? maximum : target;
   end else begin
    if(ms_ce && age<LOST_MS)age<=age+1'b1;
    if(age==LOST_MS)begin target<=minimum;status<=LOST;busy<=0;end
    if(report)begin
     if(usable)begin
      age<=0;last_good<=1;status<=TRACKING;
      recent<=d;older<=have_sample ? recent : d;have_sample<=1;
      bcd_work<=0;bcd_binary<=d;bcd_left<=9;
      if(filtered<=50)begin target<=maximum;busy<=0;end
      else if(filtered>=50+span)begin target<=minimum;busy<=0;end
      else begin
       // At most 100 narrow subtractions; product is separately registered.
       remainder<=(9'd50+span-filtered)*(maximum-minimum)+(span>>1);
       quotient<=0;map_min<=minimum;map_span<=span;busy<=1;
      end
     end else begin last_good<=0;if(have_sample && age<LOST_MS)status<=HOLDING;end
    end else if(busy && age<LOST_MS)begin
     if(remainder>=map_span)begin remainder<=remainder-map_span;quotient<=quotient+1'b1;end
     else begin target<=map_min+quotient;busy<=0;end
    end
   end
  end
 end
 // synthesis translate_off
 initial if(CLOCK_HZ<1000000 || CLOCK_HZ%1000!=0 || LOST_MS<1)$fatal(1,"invalid ultrasonic volume clock");
 // synthesis translate_on
endmodule
