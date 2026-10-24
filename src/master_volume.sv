`timescale 1ns/1ps
// Post-effects master gain,0..100% in5% steps. 256 sample slew prevents clicks.
// Passive display and I2S consume exactly the same registered output.
module master_volume(input wire clk,rst,in_valid,input wire signed [15:0] in_sample,
 input wire [6:0] percent,output reg out_valid,output reg signed [15:0] out_sample);
 reg [8:0] gain;
 reg signed [25:0] product;
 reg product_valid;
 reg [8:0] target;
 always @*begin
  case(percent)
   7'd0:target=9'd0;
   7'd5:target=9'd13;
   7'd10:target=9'd26;
   7'd15:target=9'd38;
   7'd20:target=9'd51;
   7'd25:target=9'd64;
   7'd30:target=9'd77;
   7'd35:target=9'd90;
   7'd40:target=9'd102;
   7'd45:target=9'd115;
   7'd50:target=9'd128;
   7'd55:target=9'd141;
   7'd60:target=9'd154;
   7'd65:target=9'd166;
   7'd70:target=9'd179;
   7'd75:target=9'd192;
   7'd80:target=9'd205;
   7'd85:target=9'd218;
   7'd90:target=9'd230;
   7'd95:target=9'd243;
   7'd100:target=9'd256;
   default:target=256;
  endcase
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin gain<=256;product<=0;product_valid<=0;out_valid<=0;out_sample<=0;end
  else begin
   product_valid<=in_valid;out_valid<=product_valid;
   if(in_valid)begin
    product<=in_sample*$signed({1'b0,gain});
    if(gain<target)gain<=gain+1'b1;else if(gain>target)gain<=gain-1'b1;
   end
   if(product_valid)out_sample<=product>>>8;
  end
 end
endmodule
