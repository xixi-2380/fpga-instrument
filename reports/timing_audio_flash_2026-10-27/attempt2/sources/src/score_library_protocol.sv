`timescale 1ns/1ps
// Short extension requests only; long Flash work is an asynchronous job.
module score_library_protocol(
 input wire clk,rst,request_valid,output wire request_ready,input wire [7:0] command,
 input wire [8:0] length,input wire [63:0] payload,
 output wire response_valid,input wire response_ready,output reg [4:0] response_length,output reg [159:0] response,
 input wire initialized,supported,writable,library_busy,local_busy,storage_ready,
 input wire [23:0] jedec_id,input wire [7:0] status1,status2,status3,library_error,
 input wire [15:0] job_id,input wire [1:0] job_state,input wire [31:0] ram_crc,
 output wire library_valid,input wire library_ready,output reg [1:0] library_command,
 output reg [4:0] library_index,output reg [55:0] library_name,
 output reg [4:0] lookup_index,input wire [159:0] lookup_data);
 localparam [2:0] IDLE=0,DISPATCH=1,ENTRY_WAIT=2,ENTRY_READ=3,JOB=4,REPLY=5;
 reg [2:0] state;reg [7:0] cmd;reg [8:0] len;reg [63:0] data;
 reg tracked;reg [15:0] tracked_id;reg [1:0] tracked_command;reg [4:0] tracked_index;reg [31:0] tracked_crc;
 assign request_ready=state==IDLE;assign response_valid=state==REPLY;assign library_valid=state==JOB;
 function automatic valid_name(input [55:0] name);
 begin valid_name=1;for(integer k=0;k<7;k++)if(name[k*8+:8]!=0 && (name[k*8+:8]<32 || name[k*8+:8]>126))valid_name=0;end endfunction
 task automatic reply_error(input [7:0] e);begin response<=0;response[7:0]<=e;response_length<=1;state<=REPLY;end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;cmd<=0;len<=0;data<=0;response<=0;response_length<=0;library_command<=0;library_index<=0;library_name<=0;lookup_index<=0;
   tracked<=0;tracked_id<=0;tracked_command<=0;tracked_index<=0;tracked_crc<=0;end
  else case(state)
   IDLE:if(request_valid)begin cmd<=command;len<=length;data<=payload;state<=DISPATCH;end
   DISPATCH:begin
    if((cmd==8'h40&&len!=0)||(cmd==8'h41&&len!=1)||(cmd==8'h42&&len!=8)||((cmd==8'h43||cmd==8'h44)&&len!=1)||(cmd==8'h45&&len!=8))reply_error(3);
    else case(cmd)
     8'h40:begin
      response<=0;response_length<=20;response[15:8]<=1;
      response[23:16]<={3'd0,1'b1,1'b1,writable,supported,initialized};response[31:24]<=32;
      response[47:32]<=4096;response[55:48]<=16;response[79:56]<=jedec_id;
      response[87:80]<=status1;response[95:88]<=status2;response[103:96]<=status3;
      response[119:104]<=job_id;response[127:120]<=library_error;response[159:128]<=ram_crc;state<=REPLY;
     end
     8'h41:if(data[7:0]>=32)reply_error(6);
      else begin lookup_index<=data[4:0];state<=ENTRY_WAIT;end
     8'h42,8'h43,8'h44:if(data[7:0]>=32 || (cmd==8'h42 && !valid_name(data[63:8])))reply_error(6);
      else if(!initialized || library_busy || local_busy || !storage_ready)reply_error(5);
      else if(!supported || (cmd!=8'h43 && !writable))reply_error(8'h21);
      else begin library_command<=cmd==8'h42 ? 0 : cmd==8'h43 ? 1 : 2;library_index<=data[4:0];library_name<=cmd==8'h42 ? data[63:8] : 56'd0;state<=JOB;end
     8'h45:if(!tracked || data[15:0]!=tracked_id || data[23:16]!={6'd0,tracked_command} || data[31:24]!={3'd0,tracked_index} || data[63:32]!=tracked_crc || job_id!=tracked_id)reply_error(8'h28);
      else begin
       response<=0;response_length<=20;response[23:8]<=job_id;response[31:24]<={6'd0,job_state};
       response[39:32]<=library_error;response[47:40]<={6'd0,tracked_command};response[55:48]<={3'd0,tracked_index};response[87:56]<=tracked_crc;
       response[95:88]<=job_state==2 && tracked_command==0;state<=REPLY;
      end
     default:reply_error(1);
    endcase
   end
   ENTRY_WAIT:state<=ENTRY_READ;
   ENTRY_READ:begin
    response<=0;response_length<=20;response[15:8]<={3'd0,lookup_index};response[23:16]<=lookup_data[7:0];
    response[39:24]<=lookup_data[31:16];response[71:40]<=lookup_data[63:32];response[103:72]<=lookup_data[95:64];
    response[159:104]<=lookup_data[151:96];state<=REPLY;
   end
   JOB:if(library_ready)begin
    tracked<=1;tracked_id<=job_id+1'b1;tracked_command<=library_command;tracked_index<=library_index;tracked_crc<=library_command==0?ram_crc:32'd0;
    response<=0;response_length<=3;response[23:8]<=job_id+1'b1;state<=REPLY;
   end else reply_error(5);
   REPLY:if(response_ready)state<=IDLE;
   default:state<=IDLE;
  endcase
 end
endmodule
