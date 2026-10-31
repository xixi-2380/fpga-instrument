`timescale 1ns/1ps
// v1 command engine. Verified packet banks are read byte-by-byte; no wide
// payload copies/comparator. A two-pass DATA transaction commits atomically.
// MAX_VOICES is scheduler capacity, NOT automatically the existing engine's 32.
module bluetooth_score_core #(
 parameter integer CLOCK_HZ=50000000,BAUD=9600,MAX_NOTES=1024,MAX_VOICES=1,LIBRARY_EXTENSION=0,
 NOTE_MIN=48,NOTE_MAX=83,MAX_SONG_MS=3600000,UPLOAD_TIMEOUT_MS=30000,
 GAP_TIMEOUT_MS=200,FRAME_TIMEOUT_MS=1000,
 parameter integer AW=(MAX_NOTES>1?$clog2(MAX_NOTES):1))(
 input wire clk,rst,rx_valid,input wire [7:0] rx_data,output wire rx_ready,input wire rx_fault,
 output wire tx_valid,output wire [7:0] tx_data,input wire tx_ready,
 output wire event_valid,input wire event_ready,output wire [1:0] event_kind,
 output wire [6:0] event_id,event_pitch,event_velocity,
 output reg song_valid,upload_active,output wire [1:0] play_state,
 output wire [31:0] position_ms,output wire manual_inhibit,
 output reg [7:0] last_error,output reg [15:0] received_notes,total_notes,
 output wire bad_frame,output wire scheduler_fault,
 input wire local_valid,input wire [1:0] local_command,output wire local_ready,
 output reg local_done,output reg [7:0] local_error,
 input wire storage_lock,output wire storage_ready,input wire storage_write,storage_invalidate,
 input wire [AW-1:0] storage_address,input wire [95:0] storage_wdata,output wire [95:0] storage_rdata,
 input wire storage_import,input wire [15:0] storage_count,input wire [31:0] storage_crc,
 output reg storage_done,output reg [7:0] storage_error,
 output wire [31:0] song_duration,song_crc,
 output wire extension_valid,input wire extension_ready,output wire [7:0] extension_command,
 output wire [8:0] extension_length,output wire [63:0] extension_payload,
 input wire extension_response_valid,output wire extension_response_ready,
 input wire [4:0] extension_response_length,input wire [159:0] extension_response,input wire storage_format,output reg song_format,output wire [4:0] event_timbre,output wire event_legacy);
 `include "config/score_record.svh"
 wire extended=song_format;wire [4:0] record_bytes=extended?12:8;
 wire [5:0] incoming_count;
 localparam integer MS_CYCLES=CLOCK_HZ/1000;
 localparam integer MS_W=MS_CYCLES>1?$clog2(MS_CYCLES):1;
 localparam integer AGE_W=UPLOAD_TIMEOUT_MS>0?$clog2(UPLOAD_TIMEOUT_MS+1):1;
 localparam [32:0] MAX_END_MS=MAX_SONG_MS;
 localparam [4:0] IDLE=0,DISPATCH=1,EXECUTE=2,DATA_CHECK=3,DATA_WRITE=5,
 COMMIT_FETCH=6,COMMIT_WAIT=7,COMMIT_LATCH=8,COMMIT_SCAN=9,COMMIT_EVAL=10,
 PLAYER_SEND=11,PLAYER_WAIT=12,REPLY=13,
 HEADER_ADDR=14,HEADER_WAIT=15,HEADER_LATCH=16,DUP_ADDR=17,DUP_WAIT=18,DUP_CHECK=19,
 RECORD_ADDR=20,RECORD_WAIT=21,RECORD_LATCH=22,RELEASE_FRAME=23,EXT_SEND=24,EXT_WAIT=25,DATA_END=26;
 reg [4:0] state;
 reg [MS_W-1:0] ms_div;reg [AGE_W-1:0] upload_age;wire ms_ce=ms_div==MS_CYCLES-1;
 wire frame_valid,frame_ready;wire [7:0] frame_version,frame_command;wire [15:0] frame_seq,frame_length;wire [7:0] payload_data,cached_data;
 reg [7:0] payload_address;reg parser_commit;
 reg [8:0] byte_cursor;reg [3:0] field_index;reg duplicate_mismatch,write_phase;
 reg [63:0] small_payload;
 reg [7:0] cmd;reg [15:0] seq,len;reg [7:0] ver;
 // Both formats have a constant record size. Keep the subtraction at the
 // actual16-bit length width; a variable32-bit modulo builds a divider chain.
 // Low6 quotient bits and DATA rejection are exact even for lengths0/1.
 wire [15:0] data_bytes=len-16'd2;
 assign incoming_count=extended ? data_bytes/16'd12 : data_bytes[8:3];
 wire data_length_invalid=(len < (extended ? 16'd14 : 16'd10)) ||
                         (len>16'd254) ||
                         (extended ? data_bytes%16'd12!=0 : data_bytes[2:0]!=0);
 reg session,cache_valid,consume_seq;reg [16:0] expected_seq;
 reg [7:0] cached_cmd;reg [15:0] cached_seq,cached_len;
 reg [4:0] cached_reply_len,reply_len;reg [159:0] cached_reply,reply;
 wire response_ready;
 reg [31:0] score_crc,expected_crc,duration_ms,last_start,packet_last,packet_max,crc_work;
 reg [5:0] packet_count,record_index;
 wire [AW-1:0] validation_address;reg committing;
 wire validation_done;wire [7:0] validation_error;wire [31:0] validation_duration;
 reg validation_start,local_transaction,storage_transaction,import_seen;
 reg [95:0] score_ram[0:MAX_NOTES-1];reg [95:0] ram_data;
 wire [AW-1:0] player_address;wire [AW-1:0] ram_address=committing?validation_address:
   (storage_lock===1'b1 && storage_ready ? storage_address : player_address);
 assign storage_rdata=ram_data;assign song_duration=duration_ms;assign song_crc=expected_crc;
 assign local_ready=!rst && state==IDLE && !frame_valid && !(storage_lock===1'b1);
 assign extension_valid=state==EXT_SEND;assign extension_command=cmd;assign extension_length=len;assign extension_payload=small_payload;
 assign extension_response_ready=state==EXT_WAIT;
 reg [95:0] current_record;
 reg [32:0] current_end;
 wire player_ready,player_done,player_busy;reg [1:0] player_command;
 assign storage_ready=!rst && !upload_active && play_state==0 && !player_busy && !committing && state!=PLAYER_SEND && state!=PLAYER_WAIT;
 wire player_valid=state==PLAYER_SEND;
 wire upload_expired=upload_active && upload_age>=UPLOAD_TIMEOUT_MS && !committing;
 assign frame_ready=state==RELEASE_FRAME && !rst;
 assign manual_inhibit=upload_active || play_state!=0 || player_busy || state==PLAYER_SEND || state==PLAYER_WAIT;
 bt_frame_rx #(.GAP_MS(GAP_TIMEOUT_MS),.FRAME_MS(FRAME_TIMEOUT_MS)) parser(
  clk,rst,ms_ce,rx_valid,rx_data,rx_ready,rx_fault,frame_valid,frame_ready,frame_version,frame_command,frame_seq,frame_length,
  parser_commit,payload_address,payload_data,cached_data,bad_frame);
 bt_frame_tx responses(clk,rst,state==REPLY,response_ready,cmd|8'h80,seq,reply_len,reply,tx_valid,tx_ready,tx_data);
 bt_score_player #(.CLOCK_HZ(CLOCK_HZ),.MAX_NOTES(MAX_NOTES),.VOICES(MAX_VOICES)) player(
  clk,rst,player_valid,player_ready,player_command,player_done,total_notes,duration_ms,
  player_address,ram_data,event_valid,event_ready,event_kind,event_id,event_pitch,event_velocity,
  play_state,position_ms,player_busy,scheduler_fault,song_format,event_timbre,event_legacy);
 score_validator #(.MAX_NOTES(MAX_NOTES),.VOICES(MAX_VOICES),.NOTE_MIN(NOTE_MIN),.NOTE_MAX(NOTE_MAX),.MAX_MS(MAX_SONG_MS)) validator(
 clk,rst,validation_start,total_notes,expected_crc,validation_address,ram_data,,validation_done,validation_error,validation_duration,song_format);
 // One synchronous read port, one sequential write port; RAM contents not reset.
 always @(posedge clk)begin
  ram_data<=score_ram[ram_address];
  if(!rst && state==DATA_WRITE)score_ram[received_notes[AW-1:0]+record_index]<=current_record;
  else if(!rst && storage_lock===1'b1 && storage_ready && storage_write===1'b1)score_ram[storage_address]<=storage_wdata;
 end
 function automatic [31:0] crc32_byte(input [31:0] c,input [7:0] b);
  reg [31:0] x;begin x=c^{24'b0,b};for(integer i=0;i<8;i=i+1)x=(x>>1)^((x[0])?32'hedb88320:32'h0);crc32_byte=x;end
 endfunction
 task automatic respond(input [7:0] code);
  begin reply<=0;reply[7:0]<=code;reply_len<=1;state<=REPLY;if(code!=0)last_error<=code;end
 endtask
 task automatic index_response(input [15:0] next_index);
  begin respond(0);reply[23:8]<=next_index;reply_len<=3;end
 endtask
 task automatic clear_upload;
  begin upload_active<=0;song_valid<=0;received_notes<=0;total_notes<=0;duration_ms<=0;last_start<=0;upload_age<=0;score_crc<=32'hffffffff;end
 endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;ms_div<=0;upload_age<=0;cmd<=0;seq<=0;len<=0;ver<=0;small_payload<=0;payload_address<=0;parser_commit<=0;byte_cursor<=0;field_index<=0;duplicate_mismatch<=0;write_phase<=0;current_record<=0;session<=0;cache_valid<=0;consume_seq<=0;expected_seq<=1;
   cached_cmd<=0;cached_seq<=0;cached_len<=0;cached_reply_len<=0;cached_reply<=0;reply_len<=0;reply<=0;current_end<=0;
   song_format<=0;song_valid<=0;upload_active<=0;last_error<=0;received_notes<=0;total_notes<=0;score_crc<=32'hffffffff;expected_crc<=0;duration_ms<=0;last_start<=0;
   packet_last<=0;packet_max<=0;crc_work<=0;packet_count<=0;record_index<=0;
   committing<=0;validation_start<=0;player_command<=0;local_transaction<=0;storage_transaction<=0;
   local_done<=0;local_error<=0;storage_done<=0;storage_error<=0;import_seen<=0;
  end else begin
   validation_start<=0;local_done<=0;storage_done<=0;
   if(!(storage_import===1'b1))import_seen<=0;
   if(ms_ce)ms_div<=0;else ms_div<=ms_div+1'b1;
   if(upload_active && ms_ce && !committing && upload_age<UPLOAD_TIMEOUT_MS)upload_age<=upload_age+1'b1;
   if(scheduler_fault)last_error<=8'h0d;
   case(state)
    IDLE:if(upload_expired)begin clear_upload();last_error<=8'h0c;end
     else if(frame_valid)begin
      ver<=frame_version;cmd<=frame_command;seq<=frame_seq;len<=frame_length;small_payload<=0;consume_seq<=0;parser_commit<=0;byte_cursor<=0;field_index<=0;
      state<=frame_length==0 ? DISPATCH : HEADER_ADDR;
     end
     else if(storage_lock===1'b1 && storage_ready && storage_import===1'b1 && !import_seen)begin
      song_format<=storage_format===1'b1;song_valid<=0;total_notes<=storage_count;received_notes<=storage_count;expected_crc<=storage_crc;
      storage_transaction<=1;committing<=1;validation_start<=1;import_seen<=1;state<=COMMIT_EVAL;
     end
     else if(local_valid===1'b1 && local_ready)begin
      local_error<=0;
      if(upload_active || (!song_valid && local_command!=3) || (local_command!=0 && local_command!=3 && play_state==0))begin
       local_error<=upload_active?8'd5:(!song_valid?8'h0e:8'd5);local_done<=1;
      end else begin player_command<=local_command;local_transaction<=1;state<=PLAYER_SEND;end
     end
    HEADER_ADDR:begin payload_address<=byte_cursor[7:0];state<=HEADER_WAIT;end
    HEADER_WAIT:state<=HEADER_LATCH;
    HEADER_LATCH:begin
     small_payload[field_index*8+:8]<=payload_data;
     if(byte_cursor+1>=len || field_index==7)state<=DISPATCH;
     else begin byte_cursor<=byte_cursor+1'b1;field_index<=field_index+1'b1;state<=HEADER_ADDR;end
    end
    DUP_ADDR:begin payload_address<=byte_cursor[7:0];state<=DUP_WAIT;end
    DUP_WAIT:state<=DUP_CHECK;
    DUP_CHECK:begin
     if(payload_data!=cached_data)duplicate_mismatch<=1;
     if(byte_cursor+1==len)begin
      if(duplicate_mismatch || payload_data!=cached_data)respond(8'h0b);
      else begin reply<=cached_reply;reply_len<=cached_reply_len;state<=REPLY;end
     end else begin byte_cursor<=byte_cursor+1'b1;state<=DUP_ADDR;end
    end
    RECORD_ADDR:begin payload_address<=byte_cursor[7:0];state<=RECORD_WAIT;end
    RECORD_WAIT:state<=RECORD_LATCH;
    RECORD_LATCH:begin
     if(field_index==0)current_record<=0;
     current_record[field_index*8+:8]<=payload_data;
     if(!write_phase)crc_work<=crc32_byte(crc_work,payload_data);
     byte_cursor<=byte_cursor+1'b1;
     if(field_index==record_bytes-1)begin field_index<=0;state<=write_phase ? DATA_WRITE : DATA_END;end
     else begin field_index<=field_index+1'b1;state<=RECORD_ADDR;end
    end
    DISPATCH:if(cmd[7])state<=RELEASE_FRAME;
     else if(ver!=1)begin reply<=0;reply[7:0]<=2;reply_len<=1;state<=REPLY;end
     else if(cmd==1)begin
      if(len!=0)respond(3);
      else if(seq!=0)respond(6);
      else begin
       if(upload_active)clear_upload();session<=1;cache_valid<=0;expected_seq<=1;last_error<=0;
       respond(0);reply_len<=20;reply[15:8]<=1;reply[23:16]<=1;reply[39:24]<=16'd256;
       reply[55:40]<=MAX_NOTES;reply[63:56]<=MAX_VOICES;reply[71:64]<=NOTE_MIN;reply[79:72]<=NOTE_MAX;
       reply[95:80]<=(MAX_VOICES>1?16'd5:16'd1);reply[127:96]<=BAUD;reply[159:128]<=MAX_SONG_MS;
      end
     end
     else if(cache_valid&&seq==cached_seq&&cmd==cached_cmd&&len==cached_len)begin
      if(len==0)begin reply<=cached_reply;reply_len<=cached_reply_len;state<=REPLY;end
      else begin byte_cursor<=0;duplicate_mismatch<=0;state<=DUP_ADDR;end
     end
     else if({1'b0,seq}!=expected_seq || (cache_valid&&seq==cached_seq))respond(8'h0b);
     else begin consume_seq<=1;state<=EXECUTE;end
    EXECUTE:if(cmd!=8'h14&&cmd!=8'h46&&cmd!=8'h10&&cmd!=8'h11&&cmd!=8'h12&&cmd!=8'h13&&cmd!=8'h20&&cmd!=8'h21&&cmd!=8'h22&&cmd!=8'h23&&cmd!=8'h30&&!(LIBRARY_EXTENSION!=0&&cmd>=8'h40&&cmd<=8'h45))respond(1);
     else if((cmd==8'h10&&len!=6)||(cmd==8'h14&&len!=7)||(cmd==8'h11&&data_length_invalid)||(cmd!=8'h14&&cmd!=8'h10&&cmd!=8'h11&&len!=0&&!(cmd>=8'h40&&cmd<=8'h45)))respond(3);
     else if(!session)respond(5);
     else if(storage_lock===1'b1 && ((cmd==8'h10 || cmd==8'h14) || (cmd>=8'h20 && cmd<=8'h23)))respond(5);
     else if(upload_active&&(cmd==8'h10||cmd==8'h14||cmd==8'h20||cmd==8'h21||cmd==8'h22))respond(5);
     else case(cmd)
      8'h46:begin respond(0);reply_len<=8;reply[63:8]<=56'h003b236c151a03;end
      8'h10,8'h14:if(play_state!=0||player_busy)respond(5);
       else if(cmd==8'h14 && small_payload[55:48]!=1)respond(6);
       else if(small_payload[15:0]==0)respond(6);
       else if(small_payload[15:0]>MAX_NOTES)respond(8);
       else begin
        song_format<=cmd==8'h14;song_valid<=0;upload_active<=1;received_notes<=0;total_notes<=small_payload[15:0];expected_crc<=small_payload[47:16];score_crc<=32'hffffffff;
        upload_age<=0;duration_ms<=0;last_start<=0;player_command<=3;state<=PLAYER_SEND;
       end
      8'h11:if(!upload_active)respond(5);
       else if(small_payload[15:0]!=received_notes)respond(7);
       else if({1'b0,received_notes}+{11'd0,incoming_count}>total_notes)respond(8);
       else begin packet_count<=incoming_count;record_index<=0;packet_last<=last_start;packet_max<=duration_ms;
        byte_cursor<=2;field_index<=0;write_phase<=0;crc_work<=score_crc;state<=RECORD_ADDR;end
      8'h12:if(!upload_active||received_notes!=total_notes)respond(5);
       else if((score_crc^32'hffffffff)!=expected_crc)begin clear_upload();respond(9);end
       else begin committing<=1;validation_start<=1;state<=COMMIT_EVAL;end
      8'h13:begin if(upload_active)clear_upload();respond(0);end
      8'h20,8'h21,8'h22:if(!song_valid)respond(8'h0e);
       else if(cmd!=8'h20&&play_state==0)respond(5);
       else begin player_command<=cmd[1:0];state<=PLAYER_SEND;end
      8'h23:begin player_command<=3;state<=PLAYER_SEND;end
      8'h30:begin
       respond(0);reply_len<=13;reply[15:8]<={7'b0,song_valid};reply[23:16]<={7'b0,upload_active};reply[31:24]<={6'b0,play_state};
       reply[47:32]<=received_notes;reply[63:48]<=total_notes;reply[95:64]<=position_ms;reply[103:96]<=last_error;
      end
      8'h40,8'h41,8'h42,8'h43,8'h44,8'h45:state<=EXT_SEND;
      default:respond(1);
     endcase
    DATA_END:begin current_end<={1'b0,current_record[31:0]}+{17'b0,current_record[63:48]};state<=DATA_CHECK;end
    DATA_CHECK:if(!score_record_valid(current_record,extended) || current_end>MAX_END_MS || current_record[31:0]<packet_last)respond(6);
     else begin
      packet_last<=current_record[31:0];if(current_end[31:0]>packet_max)packet_max<=current_end[31:0];
      if(record_index+1==packet_count)begin record_index<=0;byte_cursor<=2;write_phase<=1;field_index<=0;state<=RECORD_ADDR;end
      else begin record_index<=record_index+1'b1;field_index<=0;state<=RECORD_ADDR;end
     end
    DATA_WRITE:if(record_index+1==packet_count)begin
      received_notes<=received_notes+packet_count;score_crc<=crc_work;last_start<=packet_last;duration_ms<=packet_max;upload_age<=0;
      index_response(received_notes+packet_count);
     end else begin record_index<=record_index+1'b1;field_index<=0;state<=RECORD_ADDR;end
    COMMIT_EVAL:if(validation_done)begin
     committing<=0;upload_active<=0;duration_ms<=validation_duration;
     if(validation_error==0)song_valid<=1;else clear_upload();
     if(storage_transaction)begin storage_transaction<=0;storage_error<=validation_error;storage_done<=1;state<=IDLE;end
     else if(validation_error!=0)respond(validation_error);
     else begin respond(0);reply_len<=5;reply[39:8]<=validation_duration;end
    end
    PLAYER_SEND:if(player_ready)state<=PLAYER_WAIT;
    PLAYER_WAIT:if(player_done)begin
     if(local_transaction)begin local_transaction<=0;local_done<=1;state<=IDLE;end
     else if((cmd==8'h10 || cmd==8'h14))index_response(0);else respond(0);
    end
    EXT_SEND:if(extension_ready)state<=EXT_WAIT;
    EXT_WAIT:if(extension_response_valid===1'b1)begin
     reply<=extension_response;reply_len<=extension_response_length;state<=REPLY;
     if(extension_response[7:0]!=0)last_error<=extension_response[7:0];
    end
    REPLY:if(response_ready)begin
     if(consume_seq)begin
      cache_valid<=1;cached_cmd<=cmd;cached_seq<=seq;cached_len<=len;cached_reply<=reply;cached_reply_len<=reply_len;expected_seq<=expected_seq+1'b1;
     end
     parser_commit<=consume_seq;state<=RELEASE_FRAME;
    end
    RELEASE_FRAME:begin consume_seq<=0;parser_commit<=0;state<=IDLE;end
    default:begin state<=IDLE;last_error<=8'h0d;end
   endcase
   if(storage_lock===1'b1 && storage_ready && storage_invalidate===1'b1)begin song_valid<=0;total_notes<=0;received_notes<=0;duration_ms<=0;end
  end
 end
 // synthesis translate_off
 initial if(MAX_NOTES<1||MAX_NOTES>65535||MAX_VOICES<1||MAX_VOICES>32||NOTE_MIN<0||NOTE_MAX>127||NOTE_MIN>NOTE_MAX||CLOCK_HZ<1000||CLOCK_HZ%1000!=0||(BAUD!=9600&&BAUD!=115200))$fatal(1,"invalid score core parameters");
 // synthesis translate_on
endmodule
