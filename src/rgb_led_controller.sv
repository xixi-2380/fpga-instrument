`timescale 1ns/1ps
// Reference-domain100Hz frames. Brightness and preview arithmetic are split
// across spare builder clocks; WS2812 bit timing and displayed values are exact.
module rgb_led_controller #(parameter integer FRAME_CYCLES=500000)(
 input wire clk,rst,config_valid,keys_valid,input wire [15:0] config_data,
 input wire [20:0] white_held,output wire data,output wire busy,
 output reg [519:0] preview_status);
 `include "config/rgb_led_config.svh"
 localparam integer TW=FRAME_CYCLES>1?$clog2(FRAME_CYCLES):1;
 localparam [3:0] IDLE=0,PERCENT_PRODUCT=1,PERCENT_DIVIDE=2,
  BREATH_PRODUCT=3,BREATH_DIVIDE=4,PIXELS=5,START=6,WAIT_BUSY=7,WAIT_DONE=8;
 reg [TW-1:0] timer;reg pending,start;wire done;
 reg [3:0] state;reg [4:0] index;reg [15:0] cfg;
 reg [20:0] held;reg [503:0] frame,preview;
 reg [7:0] brightness,breath_phase;reg [3:0] rainbow_ticks;
 reg [4:0] rainbow_offset;reg [7:0] breath_hold;reg [4:0] rainbow_hold;
 reg [15:0] percent_product,breath_product;
 reg [8:0] base_level;
 wire [4:0] logical_index=cfg[1]?5'd20-index:index;
 wire [5:0] rainbow_sum={1'b0,logical_index}+{1'b0,rainbow_hold};
 wire [4:0] rainbow_position=rainbow_sum>=21?rainbow_sum-6'd21:rainbow_sum[4:0];
 wire [7:0] breath_factor=breath_hold<=100?breath_hold:8'd200-breath_hold;
 reg [23:0] color;
 function automatic [7:0] dim(input [7:0] value,amount);
  reg [15:0] product;reg [16:0] adjusted;
  begin
   product=value*amount;
   // Exact floor(product/255) for all8-bit products0..65025.
   adjusted={1'b0,product}+17'd1+(product>>8);
   dim=adjusted[15:8];
  end
 endfunction
 function automatic [23:0] rainbow_color(input [4:0] position);
  begin case(position)
   5'd0:rainbow_color=24'hfc0000;
   5'd1:rainbow_color=24'hfc4800;
   5'd2:rainbow_color=24'hfc9000;
   5'd3:rainbow_color=24'hfcd800;
   5'd4:rainbow_color=24'hd8fc00;
   5'd5:rainbow_color=24'h90fc00;
   5'd6:rainbow_color=24'h48fc00;
   5'd7:rainbow_color=24'h00fc00;
   5'd8:rainbow_color=24'h00fc48;
   5'd9:rainbow_color=24'h00fc90;
   5'd10:rainbow_color=24'h00fcd8;
   5'd11:rainbow_color=24'h00d8fc;
   5'd12:rainbow_color=24'h0090fc;
   5'd13:rainbow_color=24'h0048fc;
   5'd14:rainbow_color=24'h0000fc;
   5'd15:rainbow_color=24'h4800fc;
   5'd16:rainbow_color=24'h9000fc;
   5'd17:rainbow_color=24'hd800fc;
   5'd18:rainbow_color=24'hfc00d8;
   5'd19:rainbow_color=24'hfc0090;
   5'd20:rainbow_color=24'hfc0048;
   default:rainbow_color=24'd0;
  endcase end
 endfunction
 always @*begin
  color=cfg[13:12]==2?rainbow_color(rainbow_position):rgb_palette(cfg[11:9]);
  if(cfg[13:12]==3 && !held[logical_index])color=0;
 end
 ws2812_driver #(.LED_COUNT(21),.CLK_MHZ(50)) driver(
  .clk(clk),.rst_n(!rst),.start(start),.enable(cfg[14]),.brightness(brightness),
  .active_count(8'd21),.rgb_data(frame),.data(data),.busy(busy),.done(done));
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   timer<=0;pending<=1;start<=0;state<=IDLE;index<=0;cfg<=RGB_DEFAULTS;
   held<=0;frame<=0;preview<=0;preview_status<=0;brightness<=0;
   breath_phase<=0;rainbow_ticks<=0;rainbow_offset<=0;breath_hold<=0;rainbow_hold<=0;
   percent_product<=0;base_level<=0;breath_product<=0;
  end else begin
   start<=0;
   if(timer==FRAME_CYCLES-1)begin
    timer<=0;pending<=1;
    breath_phase<=breath_phase==199?0:breath_phase+1'b1;
    if(rainbow_ticks==9)begin rainbow_ticks<=0;rainbow_offset<=rainbow_offset==20?0:rainbow_offset+1'b1;end
    else rainbow_ticks<=rainbow_ticks+1'b1;
   end else timer<=timer+1'b1;
   case(state)
    IDLE:if(pending && !busy)begin
     cfg<=config_valid?config_data:RGB_DEFAULTS;held<=keys_valid?white_held:21'd0;
     breath_hold<=breath_phase;rainbow_hold<=rainbow_offset;index<=0;pending<=0;state<=PERCENT_PRODUCT;
    end
    PERCENT_PRODUCT:begin percent_product<=cfg[8:2]*16'd255;state<=PERCENT_DIVIDE;end
    PERCENT_DIVIDE:begin base_level<=percent_product/16'd100;state<=BREATH_PRODUCT;end
    BREATH_PRODUCT:begin breath_product<=base_level*breath_factor;state<=BREATH_DIVIDE;end
    BREATH_DIVIDE:begin
     brightness<=cfg[14] ? (cfg[13:12]==1 ? 8'(breath_product/16'd100):base_level[7:0]):8'd0;
     state<=PIXELS;
    end
    PIXELS:begin
     frame[index*24+:24]<=color;
     preview[index*24+:24]<={dim(color[23:16],brightness),dim(color[15:8],brightness),dim(color[7:0],brightness)};
     if(index==20)state<=START;else index<=index+1'b1;
    end
    START:begin preview_status<={cfg,preview};start<=1;state<=WAIT_BUSY;end
    WAIT_BUSY:if(busy)state<=WAIT_DONE;
    WAIT_DONE:if(!busy)state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
