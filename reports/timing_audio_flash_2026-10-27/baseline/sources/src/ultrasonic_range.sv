`timescale 1ns/1ps
// RCWL-9610A trigger/echo acquisition. No generated clock or combinational
// divider: a 1us CE measures echo and a bounded subtract FSM converts to mm.
module ultrasonic_range #(
 parameter integer CLOCK_HZ=50000000,PERIOD_US=60000,TRIG_US=12,TIMEOUT_US=30000
)(input wire clk,rst,enabled,echo,
 output reg trig,report,valid,output reg [12:0] distance_mm);
 localparam integer US_DIV=CLOCK_HZ/1000000,UW=US_DIV>1?$clog2(US_DIV):1;
 localparam integer PW=$clog2(PERIOD_US+1),TW=$clog2(TIMEOUT_US+1);
 localparam [2:0] IDLE=0,TRIGGER=1,WAIT_ECHO=2,HIGH_ECHO=3,CONVERT=4;
 (* syn_async_reg=1,async_reg="true" *) reg echo_meta,echo_sync;
 reg [UW-1:0] us_div;
 wire us_ce=us_div==US_DIV-1;
 reg [PW-1:0] period;
 reg [TW-1:0] elapsed;
 reg [2:0] state;
 reg [17:0] numerator;
 reg [12:0] quotient;
 always @(posedge clk or posedge rst)
  if(rst)begin echo_meta<=0;echo_sync<=0;end
  else begin echo_meta<=echo;echo_sync<=echo_meta;end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   us_div<=0;period<=PERIOD_US;elapsed<=0;state<=IDLE;trig<=0;
   report<=0;valid<=0;distance_mm<=0;numerator<=0;quotient<=0;
  end else begin
   report<=0;
   if(!enabled)begin
    us_div<=0;period<=PERIOD_US;elapsed<=0;state<=IDLE;trig<=0;valid<=0;
   end else begin
    if(us_ce)begin
     us_div<=0;
     if(period<PERIOD_US)period<=period+1'b1;
    end else us_div<=us_div+1'b1;
    case(state)
     IDLE:if(period==PERIOD_US && us_ce)begin
      period<=0;elapsed<=0;
      if(echo_sync)begin report<=1;valid<=0;end // stuck high before trigger
      else begin trig<=1;state<=TRIGGER;end
     end
     TRIGGER:if(us_ce)begin
      if(elapsed==TRIG_US-1)begin trig<=0;elapsed<=0;state<=WAIT_ECHO;end
      else elapsed<=elapsed+1'b1;
     end
     WAIT_ECHO:begin
      if(echo_sync)begin elapsed<=0;state<=HIGH_ECHO;end
      else if(us_ce)begin
       if(elapsed==TIMEOUT_US-1)begin report<=1;valid<=0;state<=IDLE;end
       else elapsed<=elapsed+1'b1;
      end
     end
     HIGH_ECHO:begin
      if(!echo_sync)begin
       // round(us * 10 / 58) = floor((us * 5 + 14) / 29).
       numerator<=({2'b0,16'(elapsed)}<<2)+16'(elapsed)+18'd14;
       quotient<=0;state<=CONVERT;
      end else if(us_ce)begin
       if(elapsed==TIMEOUT_US-1)begin report<=1;valid<=0;state<=IDLE;end
       else elapsed<=elapsed+1'b1;
      end
     end
     CONVERT:if(numerator>=29)begin numerator<=numerator-18'd29;quotient<=quotient+1'b1;end
      else begin distance_mm<=quotient;valid<=quotient>=20 && quotient<=4000;report<=1;state<=IDLE;end
     default:begin trig<=0;state<=IDLE;end
    endcase
   end
  end
 end
 // synthesis translate_off
 initial if(CLOCK_HZ<1000000 || CLOCK_HZ%1000000!=0 || TRIG_US<10 ||
  TIMEOUT_US<TRIG_US || TIMEOUT_US>30000 || PERIOD_US<=TRIG_US)
  $fatal(1,"invalid ultrasonic timing parameters");
 // synthesis translate_on
endmodule
