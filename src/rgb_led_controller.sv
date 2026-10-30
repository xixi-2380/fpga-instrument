`timescale 1ns/1ps
// Reference-domain 100Hz frame builder. One complete immutable frame per start.
module rgb_led_controller #(parameter integer FRAME_CYCLES=500000)(
 input wire clk,rst,config_valid,keys_valid,input wire [15:0] config_data,
 input wire [20:0] white_held,output wire data,output wire busy,
 output reg [519:0] preview_status);
 `include "config/rgb_led_config.svh"
 localparam integer TW=FRAME_CYCLES>1?$clog2(FRAME_CYCLES):1;
 reg [TW-1:0] timer;reg pending,start;wire done;
 reg [2:0] state;reg [4:0] index;reg [15:0] cfg;
 reg [20:0] held;reg [503:0] frame,preview;
 reg [7:0] brightness,breath_phase;reg [3:0] rainbow_ticks;
 reg [4:0] rainbow_offset;reg [7:0] breath_hold;reg [4:0] rainbow_hold;
 integer logical_index,wheel,segment,ramp,level;reg [23:0] color;
 function automatic [7:0] dim(input [7:0] value,amount);
  reg [15:0] product;begin product=value*amount;dim=product/255;end
 endfunction
 always @*begin
  logical_index=cfg[1]?20-index:index;color=rgb_palette(cfg[11:9]);
  wheel=0;segment=0;ramp=0;level=cfg[14] ? (integer'(cfg[8:2])*255)/100:0;
  if(cfg[13:12]==1)level=level*(breath_hold<=100?breath_hold:200-breath_hold)/100;
  if(cfg[13:12]==2)begin
   wheel=((logical_index+rainbow_hold)%21)*6;segment=wheel/21;ramp=(wheel%21)*12;
   case(segment)
    0:color={8'd252,8'(ramp),8'd0};1:color={8'(252-ramp),8'd252,8'd0};
    2:color={8'd0,8'd252,8'(ramp)};3:color={8'd0,8'(252-ramp),8'd252};
    4:color={8'(ramp),8'd0,8'd252};default:color={8'd252,8'd0,8'(252-ramp)};
   endcase
  end
  if(cfg[13:12]==3 && !held[logical_index])color=0;
 end
 ws2812_driver #(.LED_COUNT(21),.CLK_MHZ(50)) driver(
  .clk(clk),.rst_n(!rst),.start(start),.enable(cfg[14]),.brightness(brightness),
  .active_count(8'd21),.rgb_data(frame),.data(data),.busy(busy),.done(done));
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   timer<=0;pending<=1;start<=0;state<=0;index<=0;cfg<=RGB_DEFAULTS;
   held<=0;frame<=0;preview<=0;preview_status<=0;brightness<=0;
   breath_phase<=0;rainbow_ticks<=0;rainbow_offset<=0;breath_hold<=0;rainbow_hold<=0;
  end else begin
   start<=0;
   if(timer==FRAME_CYCLES-1)begin
    timer<=0;pending<=1;
    breath_phase<=breath_phase==199?0:breath_phase+1'b1;
    if(rainbow_ticks==9)begin rainbow_ticks<=0;rainbow_offset<=rainbow_offset==20?0:rainbow_offset+1'b1;end
    else rainbow_ticks<=rainbow_ticks+1'b1;
   end else timer<=timer+1'b1;
   case(state)
    0:if(pending && !busy)begin
     cfg<=config_valid?config_data:RGB_DEFAULTS;held<=keys_valid?white_held:21'd0;
     breath_hold<=breath_phase;rainbow_hold<=rainbow_offset;index<=0;pending<=0;state<=1;
    end
    1:begin
     frame[index*24+:24]<=color;brightness<=8'(level);
     preview[index*24+:24]<={dim(color[23:16],8'(level)),dim(color[15:8],8'(level)),dim(color[7:0],8'(level))};
     if(index==20)state<=2;else index<=index+1'b1;
    end
    2:begin preview_status<={cfg,preview};start<=1;state<=3;end
    3:if(busy)state<=4;
    4:if(!busy)state<=0;
    default:state<=0;
   endcase
  end
 end
endmodule
