`timescale 1ns/1ps
// v1 byte-stream framing. A verified request is held until frame_ready.
module bt_frame_rx #(parameter integer GAP_MS=200,FRAME_MS=1000)(
 input wire clk,rst,ms_ce,byte_valid,input wire [7:0] byte_data,
 output wire byte_ready,input wire stream_fault,
 output reg frame_valid,input wire frame_ready,
 output reg [7:0] version,command,output reg [15:0] frame_seq,length,
 input wire cache_commit,input wire [7:0] payload_address,
 output wire [7:0] payload_data,cached_data,output reg dropped);
 localparam [2:0] SOF0=0,SOF1=1,HEAD=2,BODY=3,CRCLO=4,CRCHI=5;
 reg [2:0] state;reg [2:0] header_index;reg [7:0] index;
 reg bank;reg [7:0] bank0[0:255],bank1[0:255];
 reg [7:0] read0,read1;
 assign payload_data=bank ? read1 : read0;
 assign cached_data=bank ? read0 : read1;
 always @(posedge clk)begin
  read0<=bank0[payload_address];read1<=bank1[payload_address];
  if(!rst && !stream_fault && byte_valid && byte_ready && state==BODY)begin
   if(bank)bank1[index]<=byte_data;else bank0[index]<=byte_data;
  end
 end
 reg [15:0] crc;reg [7:0] crc_lo;localparam integer GW=$clog2(GAP_MS+2),FW=$clog2(FRAME_MS+2);
 reg [GW-1:0] gap_age;reg [FW-1:0] frame_age;
 function automatic [15:0] crc_byte(input [15:0] c,input [7:0] b);
  reg [15:0] x;begin x=c^{b,8'b0};for(integer i=0;i<8;i=i+1)x=(x<<1)^((x[15])?16'h1021:16'h0);crc_byte=x;end
 endfunction
 assign byte_ready=!frame_valid && !rst;
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=SOF0;frame_valid<=0;version<=0;command<=0;frame_seq<=0;length<=0;bank<=0;crc<=16'hffff;crc_lo<=0;index<=0;header_index<=0;gap_age<=0;frame_age<=0;dropped<=0;end
  else begin
   dropped<=0;
   if(frame_valid&&frame_ready)begin frame_valid<=0;if(cache_commit)bank<=!bank;end
   if(stream_fault && !frame_valid)begin state<=SOF0;frame_valid<=0;dropped<=1;end
   else if(!frame_valid)begin
    if(state!=SOF0 && ms_ce)begin gap_age<=gap_age+1'b1;frame_age<=frame_age+1'b1;end
    if(state!=SOF0 && ms_ce && (gap_age>=GAP_MS || frame_age>=FRAME_MS))begin state<=SOF0;dropped<=1;end
    else if(byte_valid&&byte_ready)begin
     gap_age<=0;
     case(state)
      SOF0:if(byte_data==8'ha5)begin state<=SOF1;frame_age<=0;end
      SOF1:if(byte_data==8'h5a)begin state<=HEAD;header_index<=0;crc<=16'hffff;length<=0;end
            else if(byte_data==8'ha5)frame_age<=0;else state<=SOF0;
      HEAD:begin
       crc<=crc_byte(crc,byte_data);header_index<=header_index+1'b1;
       case(header_index)
        0:version<=byte_data;1:command<=byte_data;2:frame_seq[7:0]<=byte_data;3:frame_seq[15:8]<=byte_data;4:length[7:0]<=byte_data;
        5:begin length[15:8]<=byte_data;index<=0;
         if({byte_data,length[7:0]}>256)begin state<=SOF0;dropped<=1;end
         else state<=({byte_data,length[7:0]}==0)?CRCLO:BODY;
        end
        default:;
       endcase
      end
      BODY:begin crc<=crc_byte(crc,byte_data);if({1'b0,index}+9'd1==length)state<=CRCLO;else index<=index+1'b1;end
      CRCLO:begin crc_lo<=byte_data;state<=CRCHI;end
      CRCHI:begin state<=SOF0;if({byte_data,crc_lo}==crc)frame_valid<=1;else dropped<=1;end
      default:state<=SOF0;
     endcase
    end
   end
  end
 end
endmodule
