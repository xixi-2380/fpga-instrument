`timescale 1ns/1ps
// Post-effects master gain,0..100% in1% steps. 256 sample slew prevents clicks.
// Passive display and I2S consume exactly the same registered output.
module master_volume(input wire clk,rst,in_valid,input wire signed [15:0] in_sample,
 input wire [6:0] percent,output reg out_valid,output reg signed [15:0] out_sample,
 input wire clear);
 reg [8:0] gain;
 reg signed [25:0] product;
 reg product_valid;
 reg [8:0] target;
 always @*begin
  case(percent)
   7'd0:target=9'd0;
   7'd1:target=9'd3;
   7'd2:target=9'd5;
   7'd3:target=9'd8;
   7'd4:target=9'd10;
   7'd5:target=9'd13;
   7'd6:target=9'd15;
   7'd7:target=9'd18;
   7'd8:target=9'd20;
   7'd9:target=9'd23;
   7'd10:target=9'd26;
   7'd11:target=9'd28;
   7'd12:target=9'd31;
   7'd13:target=9'd33;
   7'd14:target=9'd36;
   7'd15:target=9'd38;
   7'd16:target=9'd41;
   7'd17:target=9'd44;
   7'd18:target=9'd46;
   7'd19:target=9'd49;
   7'd20:target=9'd51;
   7'd21:target=9'd54;
   7'd22:target=9'd56;
   7'd23:target=9'd59;
   7'd24:target=9'd61;
   7'd25:target=9'd64;
   7'd26:target=9'd67;
   7'd27:target=9'd69;
   7'd28:target=9'd72;
   7'd29:target=9'd74;
   7'd30:target=9'd77;
   7'd31:target=9'd79;
   7'd32:target=9'd82;
   7'd33:target=9'd84;
   7'd34:target=9'd87;
   7'd35:target=9'd90;
   7'd36:target=9'd92;
   7'd37:target=9'd95;
   7'd38:target=9'd97;
   7'd39:target=9'd100;
   7'd40:target=9'd102;
   7'd41:target=9'd105;
   7'd42:target=9'd108;
   7'd43:target=9'd110;
   7'd44:target=9'd113;
   7'd45:target=9'd115;
   7'd46:target=9'd118;
   7'd47:target=9'd120;
   7'd48:target=9'd123;
   7'd49:target=9'd125;
   7'd50:target=9'd128;
   7'd51:target=9'd131;
   7'd52:target=9'd133;
   7'd53:target=9'd136;
   7'd54:target=9'd138;
   7'd55:target=9'd141;
   7'd56:target=9'd143;
   7'd57:target=9'd146;
   7'd58:target=9'd148;
   7'd59:target=9'd151;
   7'd60:target=9'd154;
   7'd61:target=9'd156;
   7'd62:target=9'd159;
   7'd63:target=9'd161;
   7'd64:target=9'd164;
   7'd65:target=9'd166;
   7'd66:target=9'd169;
   7'd67:target=9'd172;
   7'd68:target=9'd174;
   7'd69:target=9'd177;
   7'd70:target=9'd179;
   7'd71:target=9'd182;
   7'd72:target=9'd184;
   7'd73:target=9'd187;
   7'd74:target=9'd189;
   7'd75:target=9'd192;
   7'd76:target=9'd195;
   7'd77:target=9'd197;
   7'd78:target=9'd200;
   7'd79:target=9'd202;
   7'd80:target=9'd205;
   7'd81:target=9'd207;
   7'd82:target=9'd210;
   7'd83:target=9'd212;
   7'd84:target=9'd215;
   7'd85:target=9'd218;
   7'd86:target=9'd220;
   7'd87:target=9'd223;
   7'd88:target=9'd225;
   7'd89:target=9'd228;
   7'd90:target=9'd230;
   7'd91:target=9'd233;
   7'd92:target=9'd236;
   7'd93:target=9'd238;
   7'd94:target=9'd241;
   7'd95:target=9'd243;
   7'd96:target=9'd246;
   7'd97:target=9'd248;
   7'd98:target=9'd251;
   7'd99:target=9'd253;
   7'd100:target=9'd256;
   default:target=256;
  endcase
 end
 always @(posedge clk or posedge rst)begin
  if(rst)gain<=256;
  else if(clear!==1'b1 && in_valid)begin
   if(gain<target)gain<=gain+1'b1;else if(gain>target)gain<=gain-1'b1;
  end
 end
 // Urgent PCM clear uses reset pins instead of a long clear->data mux.
 // The gain register above deliberately retains the user's ramp and mute.
 wire pcm_clear=rst || (clear===1'b1);
 always @(posedge clk or posedge pcm_clear)begin
  if(pcm_clear)begin product<=0;product_valid<=0;out_valid<=0;out_sample<=0;end
  else begin
   product_valid<=in_valid;out_valid<=product_valid;
   if(in_valid)begin
    product<=in_sample*$signed({1'b0,gain});
   end
   if(product_valid)out_sample<=product>>>8;
  end
 end
endmodule
