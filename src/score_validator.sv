`timescale 1ns/1ps
// Shared RAM/Flash-load validator: sequential reads, one CRC byte/clock,
// one overlap context/clock. No all-record or all-voice combinational compare.
module score_validator #(
 parameter integer MAX_NOTES=4096,VOICES=16,NOTE_MIN=48,NOTE_MAX=83,MAX_MS=3600000,
 AW=(MAX_NOTES>1?$clog2(MAX_NOTES):1))(
 input wire clk,rst,start,input wire [15:0] count,input wire [31:0] expected_crc,
 output reg [AW-1:0] address,input wire [95:0] data,
 output wire busy,output reg done,output reg [7:0] error,
 output reg [31:0] duration,input wire record_format);
 wire extended=record_format===1'b1;
 `include "config/score_record.svh"
 localparam [3:0] IDLE=0,FETCH=1,WAIT_RAM=2,LATCH=3,CHECK=4,CRC=5,SCAN=6,EVAL=7,READ_END=8;
 reg [3:0] state;reg [15:0] index;reg [95:0] record,bytes;
 reg [31:0] crc,last_time;reg [31:0] ends[0:VOICES-1];
 reg [5:0] slot,free_slot;reg found;reg [3:0] byte_no;
 reg [32:0] ending;
 reg [31:0] scanned_end;
 assign busy=state!=IDLE;
 function automatic [31:0] crc_byte(input [31:0] c,input [7:0] b);
 reg [31:0] x;begin x=c^{24'd0,b};for(integer k=0;k<8;k++)x=(x>>1)^(x[0]?32'hedb88320:0);crc_byte=x;end endfunction
 task automatic finish(input [7:0] value);begin error<=value;done<=1;state<=IDLE;end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;index<=0;address<=0;record<=0;bytes<=0;crc<=0;last_time<=0;duration<=0;ending<=0;scanned_end<=0;
   slot<=0;free_slot<=0;found<=0;byte_no<=0;done<=0;error<=0;for(integer i=0;i<VOICES;i++)ends[i]<=0;end
  else begin done<=0;
   case(state)
    IDLE:if(start)begin
     duration<=0;last_time<=0;index<=0;crc<=32'hffffffff;error<=0;
     for(integer i=0;i<VOICES;i++)ends[i]<=0;
     if(count==0 || count>MAX_NOTES)finish(8);else state<=FETCH;
    end
    FETCH:begin address<=index[AW-1:0];state<=WAIT_RAM;end
    WAIT_RAM:state<=LATCH;
    LATCH:begin
     record<=data;bytes<=data;ending<={1'b0,data[31:0]}+{17'b0,data[63:48]};state<=CHECK;
    end
    CHECK:if(!score_record_valid(record,extended) || ending>MAX_MS || record[31:0]<last_time)finish(6);
     else begin last_time<=record[31:0];if(ending>duration)duration<=ending[31:0];byte_no<=0;state<=CRC;end
    CRC:begin
     crc<=crc_byte(crc,bytes[7:0]);bytes<=bytes>>8;
     if(byte_no==(extended?11:7))begin slot<=0;free_slot<=0;found<=0;state<=READ_END;end
     else byte_no<=byte_no+1'b1;
    end
    READ_END:begin scanned_end<=ends[slot];state<=SCAN;end
    SCAN:begin
     if(!found && scanned_end<=record[31:0])begin found<=1;free_slot<=slot;end
     if(slot==VOICES-1)state<=EVAL;else begin slot<=slot+1'b1;state<=READ_END;end
    end
    EVAL:if(!found)finish(8'h0a);
     else begin
      ends[free_slot]<=ending[31:0];
      if(index+1==count)finish((crc^32'hffffffff)==expected_crc?8'd0:8'd9);
      else begin index<=index+1'b1;state<=FETCH;end
     end
    default:finish(8'h0d);
   endcase
  end
 end
endmodule
