`timescale 1ns/1ps
// Full quadrature transitions cancel bounce/reversal; invalid jumps discard
// a partial detent. SW uses a shared millisecond CE, never a generated clock.
module ec11_encoder #(parameter integer FILTER_CYCLES=3072,DEBOUNCE_MS=10,
 DOUBLE_MS=250,LONG_MS=600,STEPS_PER_DETENT=4,REVERSE=0)(
 input wire clk,rst,ms_ce,a,b,sw_n,
 output reg step_up,step_down,single_click,double_click,input wire clear_stats,output wire [127:0] diagnostic);
 (* syn_async_reg=1,async_reg="true" *) reg [2:0] meta,sync;
 localparam integer FW=FILTER_CYCLES>1?$clog2(FILTER_CYCLES):1;
 localparam integer BW=DEBOUNCE_MS>1?$clog2(DEBOUNCE_MS):1;
 localparam integer DW=$clog2(DOUBLE_MS+1),HW=$clog2(LONG_MS+1);
 reg [1:0] candidate,stable_ab,last_ab;
 reg [FW-1:0] filter_count;reg [BW-1:0] button_count;
 reg button_n,turned;reg [HW-1:0] held_ms;reg [DW-1:0] click_ms;
 reg [1:0] click_state;
 reg signed [3:0] quarter,delta,total;
 wire press=ms_ce && sync[0]!=button_n && button_count==DEBOUNCE_MS-1 && !sync[0];
 wire release_button=ms_ce && sync[0]!=button_n && button_count==DEBOUNCE_MS-1 && sync[0];
 wire detent=STEPS_PER_DETENT==2 ? stable_ab==0 || stable_ab==3 : stable_ab==3;
 wire rotate=last_ab!=stable_ab && delta!=0 && detent &&
  (total==STEPS_PER_DETENT || total==-STEPS_PER_DETENT);
 reg [15:0] up_count,down_count,single_count,double_count,invalid_count;
 function automatic [15:0] inc(input [15:0] v);inc=v==16'hffff ? v : v+1'b1;endfunction
 assign diagnostic={invalid_count,double_count,single_count,down_count,up_count,
   16'(held_ms),8'(click_ms),quarter,click_state,turned,button_n,
   2'd0,a,b,sw_n,sync,stable_ab,last_ab,step_up,step_down,single_click,double_click};
 always @(posedge clk or posedge rst)begin
  if(rst)begin up_count<=0;down_count<=0;single_count<=0;double_count<=0;invalid_count<=0;end
  else if(clear_stats===1'b1)begin up_count<=0;down_count<=0;single_count<=0;double_count<=0;invalid_count<=0;end
  else begin
   if(step_up)up_count<=inc(up_count);if(step_down)down_count<=inc(down_count);
   if(single_click)single_count<=inc(single_count);if(double_click)double_count<=inc(double_count);
   if(last_ab!=stable_ab && delta==0)invalid_count<=inc(invalid_count);
  end
 end
 always @*begin
  delta=0;
  case({last_ab,stable_ab})
   4'b1101,4'b0100,4'b0010,4'b1011:delta=1;
   4'b1110,4'b1000,4'b0001,4'b0111:delta=-1;
   default:delta=0;
  endcase
  total=quarter+delta;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin meta<=7;sync<=7;end
  else begin meta<={a,b,sw_n};sync<=meta;end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin candidate<=3;stable_ab<=3;filter_count<=0;end
  else if(sync[2:1]!=candidate)begin candidate<=sync[2:1];filter_count<=0;end
  else if(filter_count==FILTER_CYCLES-1)stable_ab<=candidate;
  else filter_count<=filter_count+1'b1;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   last_ab<=3;quarter<=0;step_up<=0;step_down<=0;button_n<=1;button_count<=0;
   held_ms<=0;turned<=0;click_ms<=0;click_state<=0;single_click<=0;double_click<=0;
  end else begin
   step_up<=0;step_down<=0;single_click<=0;double_click<=0;
   if(last_ab!=stable_ab)begin
    last_ab<=stable_ab;
    if(delta==0)quarter<=0;
    else if(detent)begin
     quarter<=0;
     if(rotate)begin
      if((total>0)^REVERSE[0])step_up<=1;else step_down<=1;
     end
    end else quarter<=total;
   end
   if(rotate && !button_n)turned<=1;
   if(ms_ce)begin
    if(sync[0]==button_n)button_count<=0;
    else if(button_count==DEBOUNCE_MS-1)begin button_n<=sync[0];button_count<=0;end
    else button_count<=button_count+1'b1;
    if(!button_n && held_ms<LONG_MS)held_ms<=held_ms+1'b1;
    if(click_state==2 && !press)begin
     if(click_ms==DOUBLE_MS-1)begin single_click<=1;click_state<=0;end
     else click_ms<=click_ms+1'b1;
    end
   end
   if(press)begin
    held_ms<=0;turned<=0;
    click_state<=click_state==2 ? 3 : 1;
   end else if(release_button)begin
    if(turned || held_ms>=LONG_MS || rotate)click_state<=0;
    else if(click_state==1)begin click_state<=2;click_ms<=0;end
    else if(click_state==3)begin double_click<=1;click_state<=0;end
   end
  end
 end
 // synthesis translate_off
 initial if(FILTER_CYCLES<1 || DEBOUNCE_MS<1 || DOUBLE_MS<1 || LONG_MS<DOUBLE_MS ||
  (STEPS_PER_DETENT!=2 && STEPS_PER_DETENT!=4))$fatal(1,"invalid EC11 parameters");
 // synthesis translate_on
endmodule
