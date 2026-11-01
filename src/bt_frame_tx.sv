`timescale 1ns/1ps
// Responses are <=20 payload bytes. Byte handshake may stall at any point.
module bt_frame_tx(
 input wire clk,rst,response_valid,output wire response_ready,
 input wire [7:0] response_command,input wire [15:0] response_sequence,
 input wire [4:0] response_length,input wire [159:0] response_payload,
 output wire byte_valid,input wire byte_ready,output reg [7:0] byte_data);
 reg busy;reg [7:0] cmd;reg [15:0] seq,crc;reg [4:0] len;reg [159:0] payload;reg [5:0] index;
 function automatic [15:0] crc_byte(input [15:0] c,input [7:0] b);
  reg [15:0] x;begin x=c^{b,8'b0};for(integer i=0;i<8;i=i+1)x=(x<<1)^((x[15])?16'h1021:16'h0);crc_byte=x;end
 endfunction
 assign response_ready=!busy&&!rst;assign byte_valid=busy&&!rst;
 always @* begin
  case(index)
   0:byte_data=8'ha5;1:byte_data=8'h5a;2:byte_data=1;3:byte_data=cmd;
   4:byte_data=seq[7:0];5:byte_data=seq[15:8];6:byte_data={3'b0,len};7:byte_data=0;
   default:if(index<8+len)byte_data=payload[7:0];else if(index==8+len)byte_data=crc[7:0];else byte_data=crc[15:8];
  endcase
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin busy<=0;cmd<=0;seq<=0;crc<=16'hffff;len<=0;payload<=0;index<=0;end
  else if(response_valid&&response_ready)begin busy<=1;cmd<=response_command;seq<=response_sequence;len<=response_length;payload<=response_payload;index<=0;crc<=16'hffff;end
  else if(byte_valid&&byte_ready)begin
   if(index>=2&&index<8+len)crc<=crc_byte(crc,byte_data);
   if(index>=8 && index<8+len)payload<=payload>>8;
   if(index==9+len)busy<=0;else index<=index+1'b1;
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(!rst&&response_valid&&response_ready&&response_length>20)$fatal(1,"response too long");
 // synthesis translate_on
endmodule
