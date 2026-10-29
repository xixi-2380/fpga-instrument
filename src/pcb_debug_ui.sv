`timescale 1ns/1ps
// Audio-domain UI/telemetry only. No physical button or encoder action routing.
module pcb_debug_ui(
 input wire clk,rst,ms_ce,menu_mode,mute_ack,action_valid,input wire [5:0] action,
 input wire hardware_valid,input wire [1023:0] hardware,
 input wire [383:0] encoder_diag,input wire [11:0] encoder_events,
 input wire [319:0] audio_status,
 output wire mute_request,output wire page_active,output wire [159:0] control,
 output reg [2:0] encoder_clear,output reg [2591:0] display,input wire display_visible);
 `include "config/ui_layout.svh"
 reg command_valid;reg [5:0] command;
 always @(posedge clk or posedge rst)
  if(rst)begin command_valid<=0;command<=UI_NONE;end
  else begin command_valid<=action_valid;command<=action;end
 localparam [131:0] DEFAULT_CONFIG={{16{8'h04}},4'h2};
 reg opened,closing,frozen,edit_gsr,pending;reg [2:0] tab;reg [1:0] board,detail,target,clear_target;
 reg [3:0] channel;reg [7:0] sequence_id,clear_sequence;reg [131:0] request_data;
 reg [131:0] draft[0:2];reg [7:0] last_result[0:2];
 reg [6:0] refresh_ms;reg refresh,building;reg [2:0] row;reg [1:0] format_phase;reg [127:0] label_q;reg [31:0] word_q;reg [319:0] text_q;
 reg [1023:0] captured;reg [127:0] captured_encoder;reg [319:0] captured_audio;reg [255:0] captured_history;
 reg [31:0] captured_meta;reg [2559:0] lines;reg [31:0] word;reg [127:0] label;
 reg [255:0] history[0:2];reg [15:0] timestamp,note_count,pcm_count,cfg_accept_count,cfg_apply_count;
 reg [2:0] previous_online;reg [31:0] event_value;
 wire [1:0] group_row=row[1:0]-2'd1;
 wire [2:0] history_row={detail!=1,group_row};
 wire [1:0] hardware_board=hardware[905:904];
 wire [131:0] applied=hardware[771:640],observed=hardware[903:772];
 wire [11:0] selected_route=board==0?captured_audio[11:0]:board==1?captured_audio[23:12]:captured_audio[35:24];
 wire [11:0] selected_armed=board==0?captured_audio[267:256]:board==1?captured_audio[279:268]:captured_audio[291:280];
 wire [7:0] ack=hardware[919:912],ack_error=hardware[927:920];
 assign mute_request=(opened && menu_mode) || closing;
 assign page_active=opened && menu_mode && mute_ack;
 assign control={6'd0,clear_target,clear_sequence,request_data,sequence_id,target,board};
 function automatic [7:0] hx(input [3:0] n);hx=n<10?8'd48+n:8'd65+n-8'd10;endfunction
 function automatic [63:0] hex32(input [31:0] n);
  hex32={hx(n[31:28]),hx(n[27:24]),hx(n[23:20]),hx(n[19:16]),hx(n[15:12]),hx(n[11:8]),hx(n[7:4]),hx(n[3:0])};
 endfunction
 function automatic [15:0] inc(input [15:0] n);inc=n==16'hffff ? n : n+1'b1;endfunction
 always @*begin
  label="                ";word=0;
  if(row==0)begin label="PCB CH TAB PAGE ";word={8'(board+1'b1),4'd0,channel,5'd0,tab,6'd0,detail};end
  else case(tab)
   0:case(row)
    1:begin label="ONLINE VALID MUT";word={22'd0,hardware_valid,mute_ack,captured[911:906],pending,frozen};end
    2:begin label="STATE CFG FAIL I";word={16'd0,captured[143:128]};end
    3:begin label="LAST ERROR BYTES";word=captured[175:144];end
    4:begin label="GOOD CHANGED HEX";word=captured[207:176];end
    5:begin label="NACK TIMEOUT HEX";word=captured[239:208];end
    6:begin label="REINIT STALE HEX";word=captured[271:240];end
    7:begin label="LAST GOOD MS HEX";word=captured[335:304];end
   endcase
   1:begin
    if(detail!=0 && row>=1 && row<=4)begin
     case(detail)1:label="DRAFT CH GROUP  ";2:label="APPLIED CH GROUP";default:label="READBACK CH GRP ";endcase
     if(detail==1)word=draft[board][4+{group_row,5'd0}+:32];
     else if(detail==2)begin
      word=captured[640+4+{group_row,5'd0}+:32];
      if(!captured[609])begin label="NO APPLIED CFG  ";word=32'hffffffff;end
     end else begin
      word=captured[772+4+{group_row,5'd0}+:32];
      if(captured[593+{group_row,2'd0}+:4]!=4'hf)begin label="UNVERIFIED READ ";word=32'hffffffff;end
     end
    end else case(row)
     1:begin label="DRAFT GSR / KOR ";word={20'd0,draft[board][3:0],draft[board][4+channel*8+:8]};end
     2:begin
      label="APPLIED GSR KOR ";word={20'd0,captured[643:640],captured[644+channel*8+:8]};
      if(!captured[609])begin label="NO APPLIED CFG  ";word=32'hffffffff;end
     end
     3:begin
      label="READBACK GSR KOR";word={20'd0,captured[775:772],captured[776+channel*8+:8]};
      if(!captured[592] || !captured[593+channel])begin label="UNVERIFIED READ ";word=32'hffffffff;end
     end
     4:begin label="PENDING / RESULT";word={23'd0,pending,last_result[board]};end
     5:begin label="LAST ERROR BYTES";word=captured[175:144];end
     6:begin label="GSR+ SENSITIVE  ";word={28'd0,draft[board][3:0]};end
     7:begin label="KOR+ LESS SENSE ";word={24'd0,draft[board][4+channel*8+:8]};end
    endcase
   end
   2:begin
    if((detail==1 || detail==2) && row<=4)begin label="BUS EVENT LOG   ";word=captured[336+{history_row,5'd0}+:32];end
    else case(row)
     1:begin label="I2C STATE / PINS";word=captured[31:0];end
     2:begin label="I2C ERR ADR TXRX";word=captured[63:32];end
     3:begin label="INIT / BYTE /INT";word={16'd0,captured[143:128]};end
     4:begin label="LAST ERROR BYTES";word=captured[175:144];end
     5:begin label="NACK TIMEOUT HEX";word=captured[239:208];end
     6:begin label="LAST GOOD MS HEX";word=captured[335:304];end
     7:begin label="AGE MS HEX      ";word=captured[303:272]-captured[335:304];end
    endcase
   end
   3:case(row)
    1:begin label="RAW PAIR1 PAIR2 ";word=captured[95:64];end
    2:begin label="STABLE CANDIDATE";word=captured[127:96];end
    3:begin label=detail==0?"ARM / ROUTE PCB ":"ARMED KEYS LOW  ";word=detail==0?{4'd0,selected_armed,4'd0,selected_route}:captured_audio[287:256];end
    4:begin label=detail==0?"BLOCK EVENT FLAG":"ARMED HI / FLAGS";word=detail==0?captured_audio[63:32]:{captured_audio[291:288],captured_audio[59:32]};end
    5:begin label="NOTE FCW        ";word=captured_audio[203:172];end
    6:begin label="HELD VOICES     ";word=captured_audio[125:94];end
    7:begin label="NOTE / PCM COUNT";word={note_count,pcm_count};end
   endcase
   4:begin
    if(detail!=0 && row<=4)begin label="EC11 PCB EVENTS ";word=captured_history[{history_row,5'd0}+:32];end
    else case(row)
     1:begin label="RAW SYNC AB SW  ";word=captured_encoder[31:0];end
     2:begin label="HOLD CLICK UP   ";word=captured_encoder[63:32];end
     3:begin label="DOWN SINGLE HEX ";word=captured_encoder[95:64];end
     4:begin label="DOUBLE INVALID  ";word=captured_encoder[127:96];end
     5:begin label="MASK TIME RATE  ";word={14'd0,captured_audio[52],captured_audio[51],captured_audio[50:48],captured_audio[77:74],captured_audio[93:85]};end
     6:begin label="VOL DEP ROOM ECH";word={1'b0,captured_audio[84:78],1'b0,captured_audio[73:67],1'b0,captured_audio[66:60],1'b0,captured_audio[59:53]};end
     7:begin label="CFG ACCEPT/APPLY";word={cfg_apply_count,cfg_accept_count};end
    endcase
   end
   default:begin end
  endcase
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   captured_meta<=0;opened<=0;closing<=0;frozen<=0;edit_gsr<=1;pending<=0;tab<=0;board<=0;detail<=0;target<=0;clear_target<=0;
   channel<=0;sequence_id<=0;clear_sequence<=0;request_data<=DEFAULT_CONFIG;refresh_ms<=0;
   refresh<=1;building<=0;row<=0;format_phase<=0;label_q<=0;word_q<=0;text_q<=0;captured<=0;captured_encoder<=0;captured_audio<=0;captured_history<=0;
   lines<=0;display<=0;encoder_clear<=0;timestamp<=0;previous_online<=0;note_count<=0;pcm_count<=0;cfg_accept_count<=0;cfg_apply_count<=0;
   for(integer b=0;b<3;b++)begin draft[b]<=DEFAULT_CONFIG;last_result[b]<=0;history[b]<=0;end
  end else begin
   encoder_clear<=0;
   if(ms_ce)begin timestamp<=timestamp+1'b1;if(refresh_ms==99)begin refresh_ms<=0;refresh<=1;end else refresh_ms<=refresh_ms+1'b1;end
   if(audio_status[36] && audio_status[38])note_count<=inc(note_count);
   if(audio_status[45])pcm_count<=inc(pcm_count);
   if(audio_status[42] && audio_status[43])cfg_accept_count<=inc(cfg_accept_count);
   if(audio_status[44])cfg_apply_count<=inc(cfg_apply_count);
   for(integer b=0;b<3;b++)begin
    if(|{encoder_events[b],encoder_events[3+b],encoder_events[6+b],encoder_events[9+b]})
     history[b]<={history[b][223:0],timestamp,4'h4,encoder_events[9+b],encoder_events[6+b],encoder_events[3+b],encoder_events[b],8'(hardware[911:906])};
    else if(hardware_valid && hardware[906+b]!=previous_online[b])
     history[b]<={history[b][223:0],timestamp,8'h50,{7'd0,hardware[906+b]}};
    else if(audio_status[44])history[b]<={history[b][223:0],timestamp,8'h62,5'd0,audio_status[44:42]};
    else if(audio_status[42] && audio_status[43])history[b]<={history[b][223:0],timestamp,8'h61,5'd0,audio_status[44:42]};
   end
   if(hardware_valid)previous_online<=hardware[908:906];
   if(pending && hardware_valid && ack==sequence_id)begin pending<=0;for(integer b=0;b<3;b++)if(target==b)last_result[b]<=ack_error;refresh<=1;end
   if(closing && display_visible!==1'b1)closing<=0;
   if(!menu_mode)begin if(opened)closing<=1;opened<=0;frozen<=0;end
   if(command_valid)begin
    refresh<=1;building<=0;
    if(command!=UI_PCB_FREEZE && command!=UI_PCB_CLEAR)frozen<=0;
    if(command==UI_PCB_OPEN && menu_mode)begin opened<=1;tab<=0;frozen<=0;end
    if(opened)case(command)
     UI_PCB_BACK:begin opened<=0;closing<=1;frozen<=0;end
     UI_PCB_TAB0,UI_PCB_TAB1,UI_PCB_TAB2,UI_PCB_TAB3,UI_PCB_TAB4:begin tab<=3'(command-UI_PCB_TAB0);detail<=0;frozen<=0;end
     UI_PCB_PREV:begin board<=board==0?2'd2:board-2'd1;frozen<=0;end
     UI_PCB_NEXT:begin board<=board==2?2'd0:board+2'd1;frozen<=0;end
     UI_PCB_CH_PREV:channel<=channel-1'b1;
     UI_PCB_CH_NEXT:channel<=channel+1'b1;
     UI_PCB_ITEM:edit_gsr<=!edit_gsr;
     UI_PCB_DETAIL:begin detail<=detail+1'b1;frozen<=0;end
     UI_PCB_FREEZE:frozen<=!frozen;
     UI_PCB_DEFAULT:if(!pending)for(integer b=0;b<3;b++)if(board==b)draft[b]<=DEFAULT_CONFIG;
     UI_PCB_ALL:if(!pending)for(integer b=0;b<3;b++)if(board==b)for(integer k=0;k<16;k++)draft[b][4+k*8+:8]<=draft[b][4+channel*8+:8];
     UI_PCB_MINUS:if(!pending && tab==1)for(integer b=0;b<3;b++)if(board==b)begin
      if(edit_gsr)begin if(draft[b][3:0]>0)draft[b][3:0]<=draft[b][3:0]-1'b1;end
      else for(integer k=0;k<16;k++)if(channel==k && draft[b][4+k*8+:8]>1)draft[b][4+k*8+:8]<=draft[b][4+k*8+:8]-1'b1;
     end
     UI_PCB_PLUS:if(!pending && tab==1)for(integer b=0;b<3;b++)if(board==b)begin
      if(edit_gsr)begin if(draft[b][3:0]<15)draft[b][3:0]<=draft[b][3:0]+1'b1;end
      else for(integer k=0;k<16;k++)if(channel==k && draft[b][4+k*8+:8]<255)draft[b][4+k*8+:8]<=draft[b][4+k*8+:8]+1'b1;
     end
     UI_PCB_APPLY,UI_PCB_REINIT:if(!pending && hardware_valid && hardware_board==board)begin
      request_data<=command==UI_PCB_REINIT?applied:draft[board];target<=board;
      sequence_id<=sequence_id+1'b1;pending<=1;for(integer b=0;b<3;b++)if(board==b)last_result[b]<=0;
     end
     UI_PCB_CLEAR:begin for(integer b=0;b<3;b++)if(board==b)begin encoder_clear[b]<=1;history[b]<=0;end clear_target<=board;clear_sequence<=clear_sequence+1'b1;end
     default:begin end
    endcase
   end
   // Format eight fixed-size text rows outside the pixel timing path. Capture
   // all sources atomically before formatting; publish only the complete set.
   if(!command_valid && !building && refresh && opened && !frozen && hardware_valid && hardware_board==board)begin
    captured_meta<={16'd0,detail,edit_gsr,frozen,pending,channel,board,tab,1'b0,page_active};
    captured<=hardware;captured_encoder<=encoder_diag[board*128+:128];captured_audio<=audio_status;captured_history<=history[board];
    row<=0;format_phase<=0;building<=1;refresh<=0;
   end else if(!command_valid && building)begin
    case(format_phase)
     0:begin label_q<=label;word_q<=word;format_phase<=1;end
     1:begin text_q<={label_q," : ",hex32(word_q),"             "};format_phase<=2;end
     2:begin
      case(row)
       0:lines[0+:320]<=text_q;
       1:lines[320+:320]<=text_q;
       2:lines[640+:320]<=text_q;
       3:lines[960+:320]<=text_q;
       4:lines[1280+:320]<=text_q;
       5:lines[1600+:320]<=text_q;
       6:lines[1920+:320]<=text_q;
       7:lines[2240+:320]<=text_q;
      endcase
      format_phase<=0;
      if(row==7)begin building<=0;refresh<=0;display<={captured_meta,text_q,lines[2239:0]};end
      else row<=row+1'b1;
     end
     default:format_phase<=0;
    endcase
   end
   display[2560]<=page_active;display[2572]<=frozen;
  end
 end
endmodule
