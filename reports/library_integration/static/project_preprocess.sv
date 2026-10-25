`timescale 1ns/1ps
// One outstanding full event. Source data stays frozen until the AUDIO
// consumer has really accepted it, including completed silence requests.
module bt_event_cdc #(parameter integer WIDTH=23)(
 input wire source_clk,audio_clk,rst,
 input wire source_valid,output wire source_ready,input wire [WIDTH-1:0] source_data,
 output wire audio_valid,input wire audio_ready,output wire [WIDTH-1:0] audio_data);
 wire sr,ar;reset_sync s_reset(source_clk,rst,sr);reset_sync a_reset(audio_clk,rst,ar);
 reg [WIDTH-1:0] held;
 reg request,ack,busy;
 (* syn_async_reg=1, async_reg="true" *) reg req_meta,req_sync,ack_meta,ack_sync;
 assign source_ready=!sr && busy && ack_sync==request;
 assign audio_valid=!ar && req_sync!=ack;
 assign audio_data=held;
 always @(posedge source_clk or posedge sr)begin
  if(sr)begin held<=0;request<=0;busy<=0;ack_meta<=0;ack_sync<=0;end
  else begin
   ack_meta<=ack;ack_sync<=ack_meta;
   if(source_ready)busy<=0;
   else if(source_valid && !busy)begin held<=source_data;request<=!request;busy<=1;end
  end
 end
 always @(posedge audio_clk or posedge ar)begin
  if(ar)begin req_meta<=0;req_sync<=0;ack<=0;end
  else begin
   req_meta<=request;req_sync<=req_meta;
   if(audio_valid && audio_ready)ack<=req_sync;
  end
 end
endmodule
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
`timescale 1ns/1ps
// 8N1, LSB first. One-cycle valid/error pulses; downstream cannot stall RX.
module uart_rx #(
    parameter integer CLOCK_HZ=50000000, BAUD=9600
)(input wire clk,rst,rx, output reg [7:0] data,
  output reg valid,framing_error);
    localparam integer DIV=(CLOCK_HZ+BAUD/2)/BAUD;
    localparam integer CW=$clog2(DIV+1);
    localparam [2:0] IDLE=0,START=1,DATA=2,STOP=3,RECOVER=4;
    (* syn_async_reg="true" *) reg rx_meta,rx_sync;
    reg [2:0] state,bit_index;
    reg [CW-1:0] timer;
    reg [7:0] shift;
    always @(posedge clk or posedge rst) begin
        if(rst)begin rx_meta<=1;rx_sync<=1;end
        else begin rx_meta<=rx;rx_sync<=rx_meta;end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin state<=IDLE;timer<=0;bit_index<=0;shift<=0;data<=0;valid<=0;framing_error<=0;end
        else begin
            valid<=0;framing_error<=0;
            case(state)
                IDLE:if(!rx_sync)begin timer<=DIV/2-1;state<=START;end
                START:if(timer!=0)timer<=timer-1'b1;
                    else if(rx_sync)state<=IDLE;
                    else begin timer<=DIV-1;bit_index<=0;state<=DATA;end
                DATA:if(timer!=0)timer<=timer-1'b1;
                    else begin
                        shift[bit_index]<=rx_sync;timer<=DIV-1;
                        if(bit_index==7)state<=STOP;else bit_index<=bit_index+1'b1;
                    end
                STOP:if(timer!=0)timer<=timer-1'b1;
                    else if(rx_sync)begin data<=shift;valid<=1;state<=IDLE;end
                    else begin framing_error<=1;state<=RECOVER;timer<=0;end
                // Following a break, require one full idle bit before accepting.
                RECOVER:if(!rx_sync)timer<=0;
                    else if(timer==DIV-1)begin timer<=0;state<=IDLE;end
                    else timer<=timer+1'b1;
                default:state<=IDLE;
            endcase
        end
    end
    // synthesis translate_off
    initial if(DIV<16)$fatal(1,"UART requires at least 16 clocks/bit");
    // synthesis translate_on
endmodule
`timescale 1ns/1ps
// Accept exactly when valid && ready. Payload is latched on acceptance.
module uart_tx #(
    parameter integer CLOCK_HZ=50000000, BAUD=9600
)(input wire clk,rst,input wire [7:0] data,input wire valid,
  output wire ready,output reg tx);
    localparam integer DIV=(CLOCK_HZ+BAUD/2)/BAUD;
    localparam integer CW=$clog2(DIV+1);
    reg busy;
    reg [CW-1:0] timer;
    reg [3:0] bit_index;
    reg [9:0] shift;
    assign ready=!busy && !rst;
    always @(posedge clk or posedge rst)begin
        if(rst)begin busy<=0;timer<=0;bit_index<=0;shift<=10'h3ff;tx<=1;end
        else if(!busy)begin
            tx<=1;
            if(valid)begin shift<={1'b1,data,1'b0};tx<=0;busy<=1;timer<=DIV-1;bit_index<=0;end
        end else if(timer!=0)timer<=timer-1'b1;
        else if(bit_index==9)begin busy<=0;tx<=1;end
        else begin shift<={1'b1,shift[9:1]};tx<=shift[1];bit_index<=bit_index+1'b1;timer<=DIV-1;end
    end
    // synthesis translate_off
    initial if(DIV<16)$fatal(1,"UART requires at least 16 clocks/bit");
    // synthesis translate_on
endmodule
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
`timescale 1ns/1ps
// Downloaded-record scheduler; 64-bit RAM records are NOT old score ROM words.
// Event kind: 0=Off, 1=On, 2=Silence all AUTO voices (hard flush, not ADSR Off).
// One clock domain. A future audio-domain bridge must retain the full event.
module bt_score_player #(
 parameter integer CLOCK_HZ=50000000,MAX_NOTES=1024,VOICES=1,
 parameter integer AW=(MAX_NOTES>1?$clog2(MAX_NOTES):1))(
 input wire clk,rst,input wire command_valid,output wire command_ready,
 input wire [1:0] command,output reg command_done,
 input wire [15:0] note_count,input wire [31:0] song_duration,
 output reg [AW-1:0] ram_address,input wire [63:0] ram_data,
 output wire event_valid,input wire event_ready,output reg [1:0] event_kind,
 output reg [6:0] event_id,event_pitch,event_velocity,
 output reg [1:0] play_state,output reg [31:0] position_ms,
 output wire busy,output reg deadline_error);
 localparam integer MS_CYCLES=CLOCK_HZ/1000;
 localparam [3:0] IDLE=0,WAIT_TICK=1,SILENCE=2,OFF_BEGIN=3,OFF_SCAN=4,EMIT_OFF=5,
  ON_CHECK=6,FETCH=7,FETCH_WAIT=8,FETCH_LATCH=9,FREE_SCAN=10,EMIT_ON=11,RESUME_SCAN=12,RESUME_EMIT=13;
 reg [3:0] state;reg [1:0] action;reg [31:0] ms_counter;
 reg [15:0] pc;reg [63:0] next_record;reg next_valid;
 reg [VOICES-1:0] active;reg [31:0] end_ms[0:VOICES-1];
 reg [6:0] pitches[0:VOICES-1],velocities[0:VOICES-1];
 reg [6:0] scan;reg fault_pending,natural_finish;
 wire time_tick=play_state==1 && ms_counter==MS_CYCLES-1;
 assign command_ready=!rst&&(state==IDLE||state==WAIT_TICK);
 assign busy=!rst && state!=IDLE && state!=WAIT_TICK;
 assign event_valid=!rst&&(state==SILENCE||state==EMIT_OFF||state==EMIT_ON||state==RESUME_EMIT);
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;action<=0;ms_counter<=0;pc<=0;next_record<=0;next_valid<=0;active<=0;
   event_kind<=0;event_id<=0;event_pitch<=0;event_velocity<=0;scan<=0;
   play_state<=0;position_ms<=0;command_done<=0;ram_address<=0;deadline_error<=0;fault_pending<=0;natural_finish<=0;
   for(integer i=0;i<VOICES;i=i+1)begin end_ms[i]<=0;pitches[i]<=0;velocities[i]<=0;end
  end else begin
   command_done<=0;deadline_error<=0;
   if(play_state==1)begin if(time_tick)ms_counter<=0;else ms_counter<=ms_counter+1'b1;end
   else ms_counter<=0;
   if(time_tick && state!=WAIT_TICK && !fault_pending)begin fault_pending<=1;deadline_error<=1;end
   if(command_valid&&command_ready)begin
    action<=command;natural_finish<=0;
    if(command==2 && play_state==2)begin scan<=0;state<=RESUME_SCAN;end
    else if((command==1&&play_state==2)||(command==2&&play_state==1))command_done<=1;
    else begin if(command==1)play_state<=2;else play_state<=0;event_kind<=2;event_id<=0;event_pitch<=0;event_velocity<=0;state<=SILENCE;end
   end else case(state)
    IDLE:;
    WAIT_TICK:if(fault_pending)begin action<=3;natural_finish<=0;event_kind<=2;event_id<=0;event_pitch<=0;event_velocity<=0;state<=SILENCE;end
     else if(time_tick)begin position_ms<=position_ms+1'b1;state<=OFF_BEGIN;end
    SILENCE:if(event_ready)begin
     if(action==0)begin // PLAY after external automatic-voice flush is acknowledged
      pc<=0;next_valid<=0;active<=0;play_state<=1;position_ms<=0;ms_counter<=0;fault_pending<=0;state<=OFF_BEGIN;command_done<=1;
     end else if(action==1)begin play_state<=2;state<=IDLE;command_done<=1;end
     else begin play_state<=0;active<=0;next_valid<=0;fault_pending<=0;state<=IDLE;if(!natural_finish)position_ms<=0;command_done<=!natural_finish;end
    end
    OFF_BEGIN:begin scan<=0;state<=OFF_SCAN;end
    OFF_SCAN:if(active[scan]&&end_ms[scan]<=position_ms)begin
      event_kind<=0;event_id<=scan;event_pitch<=pitches[scan];event_velocity<=0;state<=EMIT_OFF;
     end else if(scan==VOICES-1)state<=ON_CHECK;else scan<=scan+1'b1;
    EMIT_OFF:if(event_ready)begin active[scan]<=0;if(scan==VOICES-1)state<=ON_CHECK;else begin scan<=scan+1'b1;state<=OFF_SCAN;end end
    ON_CHECK:if(fault_pending)state<=WAIT_TICK;
     else if(!next_valid&&pc<note_count)state<=FETCH;
     else if(next_valid&&next_record[31:0]<=position_ms)begin scan<=0;state<=FREE_SCAN;end
     else if(pc==note_count && active==0)begin action<=3;natural_finish<=1;event_kind<=2;event_id<=0;event_pitch<=0;event_velocity<=0;state<=SILENCE;end
     else state<=WAIT_TICK;
    FETCH:begin ram_address<=pc[AW-1:0];state<=FETCH_WAIT;end
    FETCH_WAIT:state<=FETCH_LATCH;
    FETCH_LATCH:begin next_record<=ram_data;next_valid<=1;state<=ON_CHECK;end
    FREE_SCAN:if(!active[scan])begin
      active[scan]<=1;end_ms[scan]<={16'b0,next_record[63:48]}+next_record[31:0];
      pitches[scan]<=next_record[38:32];velocities[scan]<=next_record[46:40];
      event_kind<=1;event_id<=scan;event_pitch<=next_record[38:32];event_velocity<=next_record[46:40];
      next_valid<=0;pc<=pc+1'b1;state<=EMIT_ON;
     end else if(scan==VOICES-1)begin fault_pending<=1;deadline_error<=1;state<=WAIT_TICK;end
     else scan<=scan+1'b1;
    EMIT_ON:if(event_ready)state<=ON_CHECK;
    RESUME_SCAN:if(active[scan])begin event_kind<=1;event_id<=scan;event_pitch<=pitches[scan];event_velocity<=velocities[scan];state<=RESUME_EMIT;end
     else if(scan==VOICES-1)begin play_state<=1;ms_counter<=0;state<=WAIT_TICK;command_done<=1;end
     else scan<=scan+1'b1;
    RESUME_EMIT:if(event_ready)begin
     if(scan==VOICES-1)begin play_state<=1;ms_counter<=0;state<=WAIT_TICK;command_done<=1;end
     else begin scan<=scan+1'b1;state<=RESUME_SCAN;end
    end
    default:begin state<=IDLE;play_state<=0;deadline_error<=1;end
   endcase
  end
 end
 // synthesis translate_off
 initial if(VOICES<1||VOICES>32||CLOCK_HZ<1000||CLOCK_HZ%1000!=0)$fatal(1,"invalid scheduler parameters");
 // synthesis translate_on
endmodule
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
 input wire [AW-1:0] storage_address,input wire [63:0] storage_wdata,output wire [63:0] storage_rdata,
 input wire storage_import,input wire [15:0] storage_count,input wire [31:0] storage_crc,
 output reg storage_done,output reg [7:0] storage_error,
 output wire [31:0] song_duration,song_crc,
 output wire extension_valid,input wire extension_ready,output wire [7:0] extension_command,
 output wire [8:0] extension_length,output wire [63:0] extension_payload,
 input wire extension_response_valid,output wire extension_response_ready,
 input wire [4:0] extension_response_length,input wire [159:0] extension_response);
 localparam integer MS_CYCLES=CLOCK_HZ/1000;
 localparam [32:0] MAX_END_MS=MAX_SONG_MS;
 localparam [4:0] IDLE=0,DISPATCH=1,EXECUTE=2,DATA_CHECK=3,DATA_WRITE=5,
 COMMIT_FETCH=6,COMMIT_WAIT=7,COMMIT_LATCH=8,COMMIT_SCAN=9,COMMIT_EVAL=10,
 PLAYER_SEND=11,PLAYER_WAIT=12,REPLY=13,
 HEADER_ADDR=14,HEADER_WAIT=15,HEADER_LATCH=16,DUP_ADDR=17,DUP_WAIT=18,DUP_CHECK=19,
 RECORD_ADDR=20,RECORD_WAIT=21,RECORD_LATCH=22,RELEASE_FRAME=23,EXT_SEND=24,EXT_WAIT=25;
 reg [4:0] state;
 reg [31:0] ms_div,upload_age;wire ms_ce=ms_div==MS_CYCLES-1;
 wire frame_valid,frame_ready;wire [7:0] frame_version,frame_command;wire [15:0] frame_seq,frame_length;wire [7:0] payload_data,cached_data;
 reg [7:0] payload_address;reg parser_commit;
 reg [8:0] byte_cursor;reg [2:0] field_index;reg duplicate_mismatch,write_phase;
 reg [63:0] small_payload;
 reg [7:0] cmd;reg [15:0] seq,len;reg [7:0] ver;
 reg session,cache_valid,consume_seq;reg [16:0] expected_seq;
 reg [7:0] cached_cmd;reg [15:0] cached_seq,cached_len;
 reg [4:0] cached_reply_len,reply_len;reg [159:0] cached_reply,reply;
 wire response_ready;
 reg [31:0] score_crc,expected_crc,duration_ms,last_start,packet_last,packet_max,crc_work;
 reg [5:0] packet_count,record_index;
 wire [AW-1:0] validation_address;reg committing;
 wire validation_done;wire [7:0] validation_error;wire [31:0] validation_duration;
 reg validation_start,local_transaction,storage_transaction,import_seen;
 reg [63:0] score_ram[0:MAX_NOTES-1];reg [63:0] ram_data;
 wire [AW-1:0] player_address;wire [AW-1:0] ram_address=committing?validation_address:
   (storage_lock===1'b1 && storage_ready ? storage_address : player_address);
 assign storage_rdata=ram_data;assign song_duration=duration_ms;assign song_crc=expected_crc;
 assign local_ready=!rst && state==IDLE && !frame_valid && !(storage_lock===1'b1);
 assign extension_valid=state==EXT_SEND;assign extension_command=cmd;assign extension_length=len;assign extension_payload=small_payload;
 assign extension_response_ready=state==EXT_WAIT;
 reg [63:0] current_record;
 wire [32:0] current_end={1'b0,current_record[31:0]}+{17'b0,current_record[63:48]};
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
  play_state,position_ms,player_busy,scheduler_fault);
 score_validator #(.MAX_NOTES(MAX_NOTES),.VOICES(MAX_VOICES),.NOTE_MIN(NOTE_MIN),.NOTE_MAX(NOTE_MAX),.MAX_MS(MAX_SONG_MS)) validator(
 clk,rst,validation_start,total_notes,expected_crc,validation_address,ram_data,,validation_done,validation_error,validation_duration);
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
   cached_cmd<=0;cached_seq<=0;cached_len<=0;cached_reply_len<=0;cached_reply<=0;reply_len<=0;reply<=0;
   song_valid<=0;upload_active<=0;last_error<=0;received_notes<=0;total_notes<=0;score_crc<=32'hffffffff;expected_crc<=0;duration_ms<=0;last_start<=0;
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
      song_valid<=0;total_notes<=storage_count;received_notes<=storage_count;expected_crc<=storage_crc;
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
     current_record<={payload_data,current_record[63:8]};
     if(!write_phase)crc_work<=crc32_byte(crc_work,payload_data);
     byte_cursor<=byte_cursor+1'b1;
     if(field_index==7)begin field_index<=0;state<=write_phase ? DATA_WRITE : DATA_CHECK;end
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
    EXECUTE:if(cmd!=8'h10&&cmd!=8'h11&&cmd!=8'h12&&cmd!=8'h13&&cmd!=8'h20&&cmd!=8'h21&&cmd!=8'h22&&cmd!=8'h23&&cmd!=8'h30&&!(LIBRARY_EXTENSION!=0&&cmd>=8'h40&&cmd<=8'h45))respond(1);
     else if((cmd==8'h10&&len!=6)||(cmd==8'h11&&(len<10||len>250||len[2:0]!=2))||(cmd!=8'h10&&cmd!=8'h11&&len!=0&&!(cmd>=8'h40&&cmd<=8'h45)))respond(3);
     else if(!session)respond(5);
     else if(storage_lock===1'b1 && (cmd==8'h10 || (cmd>=8'h20 && cmd<=8'h23)))respond(5);
     else if(upload_active&&(cmd==8'h10||cmd==8'h20||cmd==8'h21||cmd==8'h22))respond(5);
     else case(cmd)
      8'h10:if(play_state!=0||player_busy)respond(5);
       else if(small_payload[15:0]==0)respond(6);
       else if(small_payload[15:0]>MAX_NOTES)respond(8);
       else begin
        song_valid<=0;upload_active<=1;received_notes<=0;total_notes<=small_payload[15:0];expected_crc<=small_payload[47:16];score_crc<=32'hffffffff;
        upload_age<=0;duration_ms<=0;last_start<=0;player_command<=3;state<=PLAYER_SEND;
       end
      8'h11:if(!upload_active)respond(5);
       else if(small_payload[15:0]!=received_notes)respond(7);
       else if({1'b0,received_notes}+{11'd0,len[8:3]}>total_notes)respond(8);
       else begin packet_count<=len[8:3];record_index<=0;packet_last<=last_start;packet_max<=duration_ms;
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
    DATA_CHECK:if(current_record[39:32]<NOTE_MIN || current_record[39:32]>NOTE_MAX || current_record[47:40]<1 || current_record[47:40]>127 || current_record[63:48]==0 || current_end>MAX_END_MS || current_record[31:0]<packet_last)respond(6);
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
     else if(cmd==8'h10)index_response(0);else respond(0);
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
`timescale 1ns/1ps
// Optional serial link, not instantiated by keyboard_top until wiring is known.
module bluetooth_score_link #(
 parameter integer CLOCK_HZ=50000000,BAUD=9600,MAX_NOTES=1024,MAX_VOICES=1,LIBRARY_EXTENSION=0,
 NOTE_MIN=48,NOTE_MAX=83,MAX_SONG_MS=3600000,FIFO_DEPTH=512)(
 input wire clk,rst,uart_rx_pin,output wire uart_tx_pin,
 output wire event_valid,input wire event_ready,output wire [1:0] event_kind,
 output wire [6:0] event_id,event_pitch,event_velocity,
 output wire song_valid,upload_active,output wire [1:0] play_state,output wire [31:0] position_ms,
 output wire manual_inhibit,output wire [7:0] last_error,output wire [15:0] received_notes,total_notes,
 output reg overflow,framing_fault,output wire bad_frame,scheduler_fault,
 input wire local_valid,input wire [1:0] local_command,output wire local_ready,local_done,output wire [7:0] local_error,
 input wire storage_lock,output wire storage_ready,input wire storage_write,storage_invalidate,
 input wire [(MAX_NOTES>1?$clog2(MAX_NOTES):1)-1:0] storage_address,input wire [63:0] storage_wdata,output wire [63:0] storage_rdata,
 input wire storage_import,input wire [15:0] storage_count,input wire [31:0] storage_crc,
 output wire storage_done,output wire [7:0] storage_error,output wire [31:0] song_duration,song_crc,
 output wire extension_valid,input wire extension_ready,output wire [7:0] extension_command,
 output wire [8:0] extension_length,output wire [63:0] extension_payload,
 input wire extension_response_valid,output wire extension_response_ready,
 input wire [4:0] extension_response_length,input wire [159:0] extension_response);
 localparam integer PW=$clog2(FIFO_DEPTH),CW=$clog2(FIFO_DEPTH+1);
 wire [7:0] data;wire valid,rx_error,ready,tx_valid,tx_ready;wire [7:0] tx_data;
 reg [7:0] fifo[0:FIFO_DEPTH-1];reg [PW-1:0] wr,rd;reg [CW-1:0] count;
 wire pop=count!=0&&ready;
 wire overflow_now=valid&&count==FIFO_DEPTH&&!pop;
 wire fault=rx_error||overflow_now;
 uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) rx(clk,rst,uart_rx_pin,data,valid,rx_error);
 uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) tx(clk,rst,tx_data,tx_valid,tx_ready,uart_tx_pin);
 bluetooth_score_core #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD),.MAX_NOTES(MAX_NOTES),.MAX_VOICES(MAX_VOICES),.LIBRARY_EXTENSION(LIBRARY_EXTENSION),
  .NOTE_MIN(NOTE_MIN),.NOTE_MAX(NOTE_MAX),.MAX_SONG_MS(MAX_SONG_MS)) core(
  .clk(clk),.rst(rst),.rx_valid(count!=0),.rx_data(fifo[rd]),.rx_ready(ready),.rx_fault(fault),
  .tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready),.event_valid(event_valid),.event_ready(event_ready),
  .event_kind(event_kind),.event_id(event_id),.event_pitch(event_pitch),.event_velocity(event_velocity),
  .song_valid(song_valid),.upload_active(upload_active),.play_state(play_state),.position_ms(position_ms),
  .manual_inhibit(manual_inhibit),.last_error(last_error),.received_notes(received_notes),.total_notes(total_notes),
  .bad_frame(bad_frame),.scheduler_fault(scheduler_fault),
  .local_valid(local_valid),.local_command(local_command),.local_ready(local_ready),.local_done(local_done),.local_error(local_error),
  .storage_lock(storage_lock),.storage_ready(storage_ready),.storage_write(storage_write),.storage_invalidate(storage_invalidate),
  .storage_address(storage_address),.storage_wdata(storage_wdata),.storage_rdata(storage_rdata),
  .storage_import(storage_import),.storage_count(storage_count),.storage_crc(storage_crc),
  .storage_done(storage_done),.storage_error(storage_error),.song_duration(song_duration),.song_crc(song_crc),
  .extension_valid(extension_valid),.extension_ready(extension_ready),.extension_command(extension_command),
  .extension_length(extension_length),.extension_payload(extension_payload),.extension_response_valid(extension_response_valid),
  .extension_response_ready(extension_response_ready),.extension_response_length(extension_response_length),.extension_response(extension_response));
 always @(posedge clk or posedge rst)begin
  if(rst)begin wr<=0;rd<=0;count<=0;overflow<=0;framing_fault<=0;end
  else if(fault)begin wr<=0;rd<=0;count<=0;if(rx_error)framing_fault<=1;if(overflow_now)overflow<=1;end
  else begin
   if(valid)begin fifo[wr]<=data;wr<=wr+1'b1;end
   if(pop)rd<=rd+1'b1;
   case({valid,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:;endcase
  end
 end
 // synthesis translate_off
 initial if(FIFO_DEPTH<512 || (FIFO_DEPTH&(FIFO_DEPTH-1))!=0)$fatal(1,"FIFO must be power of two >=512");
 // synthesis translate_on
endmodule
`timescale 1ns/1ps
// Automatic IDs 0..15 are independent; ordinary note events preserve effects.
// Only source takeover and explicit Silence clear the engine/serial buffers.
module bluetooth_audio_bridge(
 input wire clk,rst,frame_ce,event_valid,input wire [1:0] event_kind,
 input wire [6:0] event_pitch,event_velocity,input wire inhibit,
 output wire event_ready,output wire note_valid,input wire note_ready,
 output wire note_on,output wire [6:0] note_id,
 output wire [31:0] note_fcw,output wire [6:0] note_velocity,output wire flush,
 input wire [2:0] selected_timbre,output reg [2:0] note_timbre,output wire [6:0] note_pitch,input wire audio_ready,
 input wire [6:0] event_id);
 localparam [2:0] IDLE=0,CLEAR=1,SEND=2,ACK=3;
 reg [2:0] state;reg [2:0] count;
 reg prior_inhibit,on_latched,has_event,silence_latched;reg [6:0] pitch,velocity,ident;
 function automatic [31:0] frequency(input [6:0] midi);
 begin case(midi)
            7'd48:frequency=32'd11704930;
            7'd49:frequency=32'd12400941;
            7'd50:frequency=32'd13138339;
            7'd51:frequency=32'd13919586;
            7'd52:frequency=32'd14747287;
            7'd53:frequency=32'd15624207;
            7'd54:frequency=32'd16553270;
            7'd55:frequency=32'd17537579;
            7'd56:frequency=32'd18580418;
            7'd57:frequency=32'd19685267;
            7'd58:frequency=32'd20855814;
            7'd59:frequency=32'd22095965;
            7'd60:frequency=32'd23409859;
            7'd61:frequency=32'd24801882;
            7'd62:frequency=32'd26276679;
            7'd63:frequency=32'd27839171;
            7'd64:frequency=32'd29494575;
            7'd65:frequency=32'd31248413;
            7'd66:frequency=32'd33106541;
            7'd67:frequency=32'd35075158;
            7'd68:frequency=32'd37160835;
            7'd69:frequency=32'd39370534;
            7'd70:frequency=32'd41711627;
            7'd71:frequency=32'd44191930;
            7'd72:frequency=32'd46819719;
            7'd73:frequency=32'd49603764;
            7'd74:frequency=32'd52553357;
            7'd75:frequency=32'd55678342;
            7'd76:frequency=32'd58989149;
            7'd77:frequency=32'd62496826;
            7'd78:frequency=32'd66213081;
            7'd79:frequency=32'd70150316;
            7'd80:frequency=32'd74321671;
            7'd81:frequency=32'd78741067;
            7'd82:frequency=32'd83423255;
            7'd83:frequency=32'd88383859;
            default:frequency=0;
 endcase end endfunction
 assign flush=state==CLEAR;
 assign note_valid=state==SEND;
 assign note_on=on_latched;
 assign note_id=ident;
 assign note_fcw=frequency(pitch);
 assign note_velocity=velocity;
 assign note_pitch=pitch;
 assign event_ready=state==ACK || (state==SEND && note_ready);
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;count<=0;prior_inhibit<=0;has_event<=0;silence_latched<=0;on_latched<=0;pitch<=0;velocity<=127;ident<=0;note_timbre<=0;end
  else begin
   prior_inhibit<=inhibit;
   case(state)
    IDLE:if(event_valid)begin
     has_event<=1;silence_latched<=event_kind==2;on_latched<=event_kind==1;pitch<=event_pitch;velocity<=event_velocity;ident<=event_id;note_timbre<=selected_timbre;
     if(event_kind==2 || (inhibit && !prior_inhibit))begin state<=CLEAR;count<=0;end
     else state<=SEND;
    end else if(inhibit && !prior_inhibit)begin has_event<=0;state<=CLEAR;count<=0;end
    // Two frame boundaries replace both serializer channels with silence
    // before acknowledging a clear, without disturbing BCLK/LRCLK.
    CLEAR:if(frame_ce)begin
     if(count==0)count<=1;
     else if(audio_ready)state<=has_event ? (silence_latched?ACK:SEND) : IDLE;
    end
    SEND:if(note_ready)state<=IDLE;
    ACK:state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
`timescale 1ns/1ps
































// Voice defaults are independent of the physical keyboard adapter.





// Legacy envelopes remain exact for IDs0..2. New profiles use constant shifts
// and bounded linear release, never variable division or generated clocks.
module instrument_envelope #(
 parameter integer ATTACK=(48000/100),DECAY=(48000/10),
 SUSTAIN=17'd45875,RELEASE=(48000/5))(
 input wire clk,rst,sample_ce,note_on,note_off,restart,input wire [2:0] timbre,
 output wire [16:0] level,output wire active);
 wire [16:0] legacy_level;wire legacy_active;
 reg [2:0] profile;
 reg [1:0] state;
 reg [16:0] musical_level,release_step;
 wire new_profile=timbre>=3 && timbre<=6;
 wire [16:0] attack_step=profile==3 ? 17'd32 : profile==4 ? 17'd1024 : profile==5 ? 17'd2048 : 17'd512;
 wire [16:0] decay_step=profile==4 ? (musical_level>>13) : profile==5 ? (musical_level>>12) : (musical_level>>14);
 wire [16:0] cello_decay=(musical_level-17'd49152)>>11;
 wire [16:0] release_amount=profile==5 ? (musical_level>>9)+17'd1 : profile==4 ? (musical_level>>10)+17'd1 : (musical_level>>11)+17'd1;
 assign level=profile==0 ? legacy_level : musical_level;
 assign active=profile==0 ? legacy_active : state!=0;
 adsr_envelope #(.ATTACK(ATTACK),.DECAY(DECAY),.SUSTAIN(SUSTAIN),.RELEASE(RELEASE)) legacy(
  .clk(clk),.rst(rst),.sample_ce(sample_ce),.note_on(note_on && !new_profile),
  .note_off(note_off && profile==0),.restart(restart && !new_profile),
  .level(legacy_level),.active(legacy_active),.seed_valid(profile!=0),.seed_level(musical_level));
 always @(posedge clk or posedge rst)begin
  if(rst)begin profile<=0;state<=0;musical_level<=0;release_step<=1;end
  else if(sample_ce)begin
   if(note_on && (!note_off || restart))begin
    if(new_profile)begin
     profile<=timbre;state<=1;
     // New ownership starts at zero; retrigger continues its present level.
     if(restart)musical_level<=0;
     else if(profile==0)musical_level<=legacy_level;
    end else begin profile<=0;state<=0;musical_level<=0;end
   end else if(note_off && profile!=0)begin
    if(musical_level==0)state<=0;
    else begin state<=3;release_step<=release_amount;end
   end else if(profile!=0)begin
    case(state)
     1:if(musical_level>=17'd65536-attack_step)begin musical_level<=65536;state<=2;end
       else musical_level<=musical_level+attack_step;
     2:if(profile==3)begin
        if(musical_level>49152)musical_level<=musical_level-(cello_decay==0 ? 17'd1 : cello_decay);
       end else if(musical_level<=1)begin musical_level<=0;state<=0;end
       else musical_level<=musical_level-(decay_step==0 ? 17'd1 : decay_step);
     3:if(musical_level<=release_step)begin musical_level<=0;state<=0;end
       else musical_level<=musical_level-release_step;
     default:musical_level<=0;
    endcase
   end
  end
 end
endmodule
`timescale 1ns/1ps
// Passive tap on actual post-effect PCM. The audio producer is never stalled.
// 128 points, one per four accepted48kHz samples:10.667ms rolling windows.
// Complete windows publish atomically; rgb_status_cdc captures a stable copy.
module audio_visualizer(
 input wire clk,rst,sample_valid,input wire signed [15:0] sample,
 output reg [1023:0] waveform,output reg [7:0] peak,output reg window_valid);
 reg [1023:0] working;
 reg [6:0] index;
 reg [1:0] decimate;
 reg [7:0] peak_work;
 wire [15:0] magnitude=sample[15] ? (~sample+16'd1) : sample;
 wire [7:0] amplitude=magnitude[15] ? 8'd255 : magnitude[14:7];
 wire [7:0] display_sample=sample>16'sd4095 ? 8'h7f : sample < -16'sd4096 ? 8'h80 : sample[12:5];
 wire [7:0] max_peak=amplitude>peak_work ? amplitude : peak_work;
 always @(posedge clk or posedge rst)begin
  if(rst)begin waveform<=0;working<=0;peak<=0;window_valid<=0;index<=0;decimate<=0;peak_work<=0;end
  else begin
   window_valid<=0;
   if(sample_valid)begin
    decimate<=decimate+1'b1;
    peak_work<=max_peak;
    if(decimate==3)begin
     working[index*8+:8]<=display_sample;
     if(index==127)begin
      waveform<={display_sample,working[1015:0]};peak<=max_peak;
      index<=0;peak_work<=0;window_valid<=1;
     end else index<=index+1'b1;
    end
   end
  end
 end
endmodule
`timescale 1ns/1ps
// Audio-domain routing only. Raw matrix scanning continues in both modes.
// Sending zero keys to the note adapter drains Note Off instead of freezing it.
module ui_keypad_router #(parameter integer RELEASE_CYCLES=1)(
 input wire clk,rst,menu_mode,ghost,input wire [15:0] keys,
 output wire inhibit_notes,output reg action_valid,output reg [5:0] action,input wire more_mode);
// Shared actions and half-open rectangles for the British UI,800x480.
localparam [5:0] UI_SINE=0,UI_FLUTE=1,UI_REED=2,UI_ECHO=3,UI_ROOM=4,
 UI_TREMOLO=5,UI_FX=6,UI_MODE=7,UI_LESS=8,UI_MORE=9,
 UI_SLOWER=10,UI_FASTER=11,UI_DEFAULTS=12,UI_CELLO=13,UI_PIANO=14,
 UI_GUITAR=15,UI_VIBES=16,UI_PREV=17,UI_NEXT=18,UI_VOLUME_DOWN=19,UI_VOLUME_UP=20,
 UI_OPEN_MORE=21,UI_MORE_BACK=22,UI_SONG_PREV=23,UI_SONG_NEXT=24,UI_SONG_PLAY=25,
 UI_SONG_PAUSE=26,UI_SONG_RESUME=27,UI_SONG_STOP=28,UI_SONG_LOAD=29,UI_SONG_SAVE=30,
 UI_SONG_DELETE=31,UI_FLASH_INFO=32,UI_NONE=63;
function automatic ui_inside(input integer px,py,left,top,width,height);
 begin ui_inside=px>=left && px<left+width && py>=top && py<top+height;end
endfunction
function automatic integer timbre_x(input integer id);
 begin timbre_x=28+(id%2)*124;end
endfunction
function automatic integer timbre_y(input integer id);
 begin timbre_y=132+(id/2)*64;end
endfunction
function automatic [5:0] timbre_action(input integer id);
 begin case(id)
 0:timbre_action=UI_SINE;1:timbre_action=UI_FLUTE;2:timbre_action=UI_REED;
 3:timbre_action=UI_CELLO;4:timbre_action=UI_PIANO;5:timbre_action=UI_GUITAR;
 6:timbre_action=UI_VIBES;default:timbre_action=UI_NONE;endcase end
endfunction
function automatic [5:0] ui_hit(input integer px,py,input [1:0] fx,input menu);
 integer i;
 begin
  ui_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))ui_hit=UI_MODE;
  else if(menu)begin
   for(i=0;i<7;i=i+1)
    if(ui_inside(px,py,timbre_x(i),timbre_y(i),112,52))ui_hit=timbre_action(i);
   if(ui_inside(px,py,152,324,112,52))ui_hit=UI_FX;
   if(ui_inside(px,py,308,124,148,48))ui_hit=UI_ECHO;
   if(ui_inside(px,py,464,124,148,48))ui_hit=UI_ROOM;
   if(ui_inside(px,py,620,124,148,48))ui_hit=UI_TREMOLO;
   if(ui_inside(px,py,308,240,52,48))ui_hit=UI_LESS;
   if(ui_inside(px,py,716,240,52,48))ui_hit=UI_MORE;
   if(fx==2 && ui_inside(px,py,308,344,52,48))ui_hit=UI_SLOWER;
   if(fx==2 && ui_inside(px,py,716,344,52,48))ui_hit=UI_FASTER;
   if(ui_inside(px,py,24,420,44,44))ui_hit=UI_VOLUME_DOWN;
   if(ui_inside(px,py,272,420,44,44))ui_hit=UI_VOLUME_UP;
   if(ui_inside(px,py,664,420,116,44))ui_hit=UI_DEFAULTS;
   if(ui_inside(px,py,550,420,104,44))ui_hit=UI_OPEN_MORE;
  end
 end
endfunction
function automatic [5:0] more_hit(input integer px,py);
 begin
  more_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))more_hit=UI_MORE_BACK;
  if(ui_inside(px,py,24,200,160,40))more_hit=UI_SONG_PREV;
  if(ui_inside(px,py,204,200,160,40))more_hit=UI_SONG_NEXT;
  if(ui_inside(px,py,384,200,160,40))more_hit=UI_SONG_LOAD;
  if(ui_inside(px,py,564,200,160,40))more_hit=UI_SONG_PLAY;
  if(ui_inside(px,py,24,252,160,40))more_hit=UI_SONG_PAUSE;
  if(ui_inside(px,py,204,252,160,40))more_hit=UI_SONG_RESUME;
  if(ui_inside(px,py,384,252,160,40))more_hit=UI_SONG_STOP;
  if(ui_inside(px,py,24,304,160,40))more_hit=UI_SONG_SAVE;
  if(ui_inside(px,py,204,304,160,40))more_hit=UI_SONG_DELETE;
  if(ui_inside(px,py,384,304,160,40))more_hit=UI_FLASH_INFO;
 end
endfunction
 localparam integer RW=$clog2(RELEASE_CYCLES+1);
 reg [RW-1:0] release_count;
 wire all_released=release_count==RELEASE_CYCLES;
 reg play_armed,menu_armed,prior_menu;
 always @(posedge clk or posedge rst)begin
  if(rst)release_count<=0;
  else if(keys!=0 || ghost)release_count<=0;
  else if(!all_released)release_count<=release_count+1'b1;
 end
 reg [3:0] index;
 wire one_key=keys!=0 && (keys & (keys-16'd1))==0;
 assign inhibit_notes=menu_mode || !play_armed;
 always @*begin
  index=0;
  for(integer k=0;k<16;k=k+1)if(keys[k])index=k;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin play_armed<=0;menu_armed<=0;prior_menu<=0;action_valid<=0;action<=UI_NONE;end
  else begin
   action_valid<=0;prior_menu<=menu_mode;
   if(menu_mode)play_armed<=0;
   else if(all_released && !ghost)play_armed<=1;
   if(!menu_mode || !prior_menu || ghost)menu_armed<=0;
   else if(keys==0)menu_armed<=all_released;
   else begin
    menu_armed<=0;
    if(menu_armed && one_key)begin
     action_valid<=1;
     if(more_mode===1'b1)case(index)
      0:action<=UI_SONG_PREV;1:action<=UI_SONG_NEXT;2:action<=UI_SONG_LOAD;3:action<=UI_SONG_PLAY;
      4:action<=UI_SONG_PAUSE;5:action<=UI_SONG_RESUME;6:action<=UI_SONG_STOP;7:action<=UI_SONG_SAVE;
      8:action<=UI_SONG_DELETE;9,15:action<=UI_MORE_BACK;10:action<=UI_FLASH_INFO;
      default:begin action<=UI_NONE;action_valid<=0;end
     endcase else case(index)
      0:action<=UI_SINE;1:action<=UI_FLUTE;2:action<=UI_REED;3:action<=UI_MODE;
      4:action<=UI_ECHO;5:action<=UI_ROOM;6:action<=UI_TREMOLO;7:action<=UI_FX;
      8:action<=UI_LESS;9:action<=UI_MORE;10:action<=UI_SLOWER;11:action<=UI_FASTER;
      12:action<=UI_DEFAULTS;13:action<=UI_PREV;14:action<=UI_NEXT;15:action<=UI_OPEN_MORE;
      default:begin action<=UI_NONE;action_valid<=0;end
     endcase
    end
   end
  end
 end
 // synthesis translate_off
 initial if(RELEASE_CYCLES<1)$fatal(1,"Invalid menu release qualification");
 // synthesis translate_on
endmodule
`timescale 1ns/1ps
// Input is an already atomic audio-domain snapshot. One action per DOWN;
// no drag/repeat. First contact after reset/error/enable requires an UP first.
module ui_touch_actions(
 input wire clk,rst,enabled,snapshot_valid,ready,error,down,
 input wire [3:0] count,input wire [15:0] x,y,resolution_x,resolution_y,
 input wire [1:0] effect_mode,input wire menu_mode,output reg action_valid,output reg [5:0] action,input wire more_mode);
// Shared actions and half-open rectangles for the British UI,800x480.
localparam [5:0] UI_SINE=0,UI_FLUTE=1,UI_REED=2,UI_ECHO=3,UI_ROOM=4,
 UI_TREMOLO=5,UI_FX=6,UI_MODE=7,UI_LESS=8,UI_MORE=9,
 UI_SLOWER=10,UI_FASTER=11,UI_DEFAULTS=12,UI_CELLO=13,UI_PIANO=14,
 UI_GUITAR=15,UI_VIBES=16,UI_PREV=17,UI_NEXT=18,UI_VOLUME_DOWN=19,UI_VOLUME_UP=20,
 UI_OPEN_MORE=21,UI_MORE_BACK=22,UI_SONG_PREV=23,UI_SONG_NEXT=24,UI_SONG_PLAY=25,
 UI_SONG_PAUSE=26,UI_SONG_RESUME=27,UI_SONG_STOP=28,UI_SONG_LOAD=29,UI_SONG_SAVE=30,
 UI_SONG_DELETE=31,UI_FLASH_INFO=32,UI_NONE=63;
function automatic ui_inside(input integer px,py,left,top,width,height);
 begin ui_inside=px>=left && px<left+width && py>=top && py<top+height;end
endfunction
function automatic integer timbre_x(input integer id);
 begin timbre_x=28+(id%2)*124;end
endfunction
function automatic integer timbre_y(input integer id);
 begin timbre_y=132+(id/2)*64;end
endfunction
function automatic [5:0] timbre_action(input integer id);
 begin case(id)
 0:timbre_action=UI_SINE;1:timbre_action=UI_FLUTE;2:timbre_action=UI_REED;
 3:timbre_action=UI_CELLO;4:timbre_action=UI_PIANO;5:timbre_action=UI_GUITAR;
 6:timbre_action=UI_VIBES;default:timbre_action=UI_NONE;endcase end
endfunction
function automatic [5:0] ui_hit(input integer px,py,input [1:0] fx,input menu);
 integer i;
 begin
  ui_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))ui_hit=UI_MODE;
  else if(menu)begin
   for(i=0;i<7;i=i+1)
    if(ui_inside(px,py,timbre_x(i),timbre_y(i),112,52))ui_hit=timbre_action(i);
   if(ui_inside(px,py,152,324,112,52))ui_hit=UI_FX;
   if(ui_inside(px,py,308,124,148,48))ui_hit=UI_ECHO;
   if(ui_inside(px,py,464,124,148,48))ui_hit=UI_ROOM;
   if(ui_inside(px,py,620,124,148,48))ui_hit=UI_TREMOLO;
   if(ui_inside(px,py,308,240,52,48))ui_hit=UI_LESS;
   if(ui_inside(px,py,716,240,52,48))ui_hit=UI_MORE;
   if(fx==2 && ui_inside(px,py,308,344,52,48))ui_hit=UI_SLOWER;
   if(fx==2 && ui_inside(px,py,716,344,52,48))ui_hit=UI_FASTER;
   if(ui_inside(px,py,24,420,44,44))ui_hit=UI_VOLUME_DOWN;
   if(ui_inside(px,py,272,420,44,44))ui_hit=UI_VOLUME_UP;
   if(ui_inside(px,py,664,420,116,44))ui_hit=UI_DEFAULTS;
   if(ui_inside(px,py,550,420,104,44))ui_hit=UI_OPEN_MORE;
  end
 end
endfunction
function automatic [5:0] more_hit(input integer px,py);
 begin
  more_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))more_hit=UI_MORE_BACK;
  if(ui_inside(px,py,24,200,160,40))more_hit=UI_SONG_PREV;
  if(ui_inside(px,py,204,200,160,40))more_hit=UI_SONG_NEXT;
  if(ui_inside(px,py,384,200,160,40))more_hit=UI_SONG_LOAD;
  if(ui_inside(px,py,564,200,160,40))more_hit=UI_SONG_PLAY;
  if(ui_inside(px,py,24,252,160,40))more_hit=UI_SONG_PAUSE;
  if(ui_inside(px,py,204,252,160,40))more_hit=UI_SONG_RESUME;
  if(ui_inside(px,py,384,252,160,40))more_hit=UI_SONG_STOP;
  if(ui_inside(px,py,24,304,160,40))more_hit=UI_SONG_SAVE;
  if(ui_inside(px,py,204,304,160,40))more_hit=UI_SONG_DELETE;
  if(ui_inside(px,py,384,304,160,40))more_hit=UI_FLASH_INFO;
 end
endfunction
 reg armed;
 wire calibrated=resolution_x==800 && resolution_y==480;
 wire valid_point=count==1 && x<800 && y<480;
 wire [5:0] hit=more_mode===1'b1 ? more_hit(integer'(x),integer'(y)) : ui_hit(integer'(x),integer'(y),effect_mode,menu_mode);
 always @(posedge clk or posedge rst)begin
  if(rst)begin armed<=0;action_valid<=0;action<=UI_NONE;end
  else begin
   action_valid<=0;
   if(!enabled || !snapshot_valid || !ready || error || !calibrated)armed<=0;
   else if(!down)armed<=1;
   else begin
    armed<=0;
    if(armed && valid_point && hit!=UI_NONE)begin action_valid<=1;action<=hit;end
   end
  end
 end
endmodule
`timescale 1ns/1ps
// Trial DE-only profile based on Sipeed's TangMega-138KPro 800x480 example.
// This is NOT a timing specification for the user's QTB203V121C panel.
// Existing audio PLLs are separate and unchanged.
module rgb_display #(
    parameter integer VOICES=32,TEST_PATTERN=0,PCLK_INVERT=1,
    H_SYNC=0,H_BACK=182,H_FRONT=210,V_SYNC=0,V_BACK=8,V_FRONT=45,
    HS_ACTIVE=0,VS_ACTIVE=0,DE_ONLY=1
)(
    input wire ref_clk,pll_reset,audio_clk,audio_reset,
    input wire [VOICES-1:0] voice_active,voice_held,
    input wire [2:0] selected_timbre,
    input wire visual_sample_valid,input wire signed [15:0] visual_sample,input wire [15:0] visual_notes,
    input wire score_busy,audio_ready,score_error,underrun,ghost,
    output wire lcd_clk,lcd_hs,lcd_vs,lcd_en,
    output wire [5:0] lcd_r,lcd_g,lcd_b,
    input wire menu_mode,effects_enabled,input wire [1:0] effect_mode,
    input wire [6:0] echo_percent,room_percent,depth_percent,input wire [3:0] tremolo_rate_hz,
    input wire [6:0] volume_percent,
    input wire touch_enabled,touch_ui_enabled,touch_ready_status,touch_error_status,
    input wire [81:0] more_status
);
    wire pixel_clk,pixel_lock,pixel_reset;
    wire common_reset=pll_reset || !pixel_lock || audio_reset;
    // 50 * 21 / 30 = 35 MHz; independent third PLL, no audio clock edits.
    PLL #(.FCLKIN("50"),.IDIV_SEL(1),.FBDIV_SEL(1),.MDIV_SEL(21),
        .ODIV0_SEL(30),.CLKFB_SEL("INTERNAL")) pixel_pll(
        .CLKIN(ref_clk),.CLKOUT0(pixel_clk),.CLKOUT1(),.CLKOUT2(),.CLKOUT3(),
        .CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.CLKFBOUT(),.LOCK(pixel_lock),.RESET(pll_reset),
        .CLKFB(1'b0),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
        .ENCLK0(1'b1),.ENCLK1(1'b0),.ENCLK2(1'b0),.ENCLK3(1'b0),
        .ENCLK4(1'b0),.ENCLK5(1'b0),.ENCLK6(1'b0),
        .FBDSEL(6'b0),.IDSEL(6'b0),.MDSEL(7'b0),.MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0),.ODSEL0_FRAC(3'b0),.ODSEL1(7'b0),.ODSEL2(7'b0),
        .ODSEL3(7'b0),.ODSEL4(7'b0),.ODSEL5(7'b0),.ODSEL6(7'b0),
        .DT0(4'b0),.DT1(4'b0),.DT2(4'b0),.DT3(4'b0),
        .PSSEL(3'b0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),
        .SSCON(1'b0),.SSCMDSEL(7'b0),.SSCMDSEL_FRAC(3'b0),
        .ICPSEL(6'b0),.LPFRES(3'b0),.LPFCAP(2'b0));
    reset_sync pixel_reset_sync(pixel_clk,common_reset,pixel_reset);

    // Balanced reduction instead of a 32-stage serial count in the audio domain.
    function automatic [5:0] count_voices(input [31:0] bitmap);
        reg [1:0] pair_count[0:15];
        reg [2:0] quad_count[0:7];
        reg [3:0] oct_count[0:3];
        reg [4:0] half_count[0:1];
        integer i;
        begin
            for(i=0;i<16;i=i+1)pair_count[i]={1'b0,bitmap[i*2]}+{1'b0,bitmap[i*2+1]};
            for(i=0;i<8;i=i+1)quad_count[i]={1'b0,pair_count[i*2]}+{1'b0,pair_count[i*2+1]};
            for(i=0;i<4;i=i+1)oct_count[i]={1'b0,quad_count[i*2]}+{1'b0,quad_count[i*2+1]};
            for(i=0;i<2;i=i+1)half_count[i]={1'b0,oct_count[i*2]}+{1'b0,oct_count[i*2+1]};
            count_voices={1'b0,half_count[0]}+{1'b0,half_count[1]};
        end
    endfunction
    wire [31:0] active_map=voice_active,held_map=voice_held;
    wire [19:0] legacy_status={TEST_PATTERN!=0,ghost,underrun,score_error,audio_ready,
        score_busy,selected_timbre[1:0],count_voices(held_map),count_voices(active_map)};
    wire [1023:0] waveform;wire [7:0] peak;wire window_valid;
    audio_visualizer monitor(audio_clk,audio_reset,visual_sample_valid,visual_sample,waveform,peak,window_valid);
    wire [63:0] settings_status={3'd0,volume_percent,selected_timbre[2],touch_error_status,touch_ready_status,touch_ui_enabled,touch_enabled,
        tremolo_rate_hz,depth_percent,room_percent,echo_percent,effects_enabled,effect_mode,menu_mode,legacy_status};
    wire [1111:0] source_status={waveform,peak,visual_notes,settings_status};
    wire [1111:0] pixel_status;
    wire status_valid,update_pulse;
    rgb_status_cdc #(.WIDTH(1112)) status_bridge(audio_clk,pixel_clk,common_reset,source_status,
        pixel_status,status_valid,update_pulse);
    wire [10:0] x,y;
    wire de,hs,vs,frame_start;
    rgb_scan_timing #(.H_SYNC(H_SYNC),.H_BACK(H_BACK),.H_FRONT(H_FRONT),
        .V_SYNC(V_SYNC),.V_BACK(V_BACK),.V_FRONT(V_FRONT),
        .HS_ACTIVE(HS_ACTIVE),.VS_ACTIVE(VS_ACTIVE),.DE_ONLY(DE_ONLY))
        scan(pixel_clk,pixel_reset,x,y,de,hs,vs,frame_start);
    wire [23:0] rgb;
    wire [81:0] pixel_more;wire more_valid,more_update;
    rgb_status_cdc #(.WIDTH(82)) more_bridge(audio_clk,pixel_clk,common_reset,more_status,pixel_more,more_valid,more_update);
    wire rendered_de,rendered_hs,rendered_vs;
    rgb_ui_renderer renderer(pixel_clk,pixel_reset,frame_start,status_valid,pixel_status,
        x,y,de,hs,vs,rgb,rendered_de,rendered_hs,rendered_vs,pixel_more);
    // Only the output pin is phase-inverted. It never clocks any internal RTL.
    // At default phase, a panel rising edge has half a pixel period of setup.
    assign lcd_clk=PCLK_INVERT ? ~pixel_clk : pixel_clk;
    // Safe blanking must not depend on a stopped pixel clock producing another edge.
    assign lcd_en=!pixel_reset && rendered_de;
    assign lcd_hs=pixel_reset ? !HS_ACTIVE[0] : rendered_hs;
    assign lcd_vs=pixel_reset ? !VS_ACTIVE[0] : rendered_vs;
    assign lcd_r=pixel_reset ? 6'd0 : rgb[23:18];
    assign lcd_g=pixel_reset ? 6'd0 : rgb[15:10];
    assign lcd_b=pixel_reset ? 6'd0 : rgb[7:2];

    initial if(VOICES<1 || VOICES>32)$fatal(1,"rgb_display supports 1..32 voices");

endmodule

`timescale 1ns/1ps
// Four-phase bundled-data snapshot. The two domains share async_reset;
// assert it whenever EITHER domain resets/loses its clock qualification.
// The source never waits for the display and may change source_data each cycle.
// Only captured data is held; intermediate snapshots may be skipped by design.
module rgb_status_cdc #(
    parameter integer WIDTH=20
)(
    input wire source_clk,pixel_clk,async_reset,
    input wire [WIDTH-1:0] source_data,
    output reg [WIDTH-1:0] pixel_data,
    output reg pixel_valid,
    output reg update_pulse
);
    wire source_reset,pixel_reset;
    reset_sync source_reset_sync(source_clk,async_reset,source_reset);
    reset_sync pixel_reset_sync(pixel_clk,async_reset,pixel_reset);
    reg request,acknowledge;
    (* syn_preserve=1,syn_async_reg=1 *) reg [1:0] request_sync,ack_sync;
    (* syn_preserve=1 *) reg [WIDTH-1:0] held_data;
    // Single-bit control synchronizers; do not synchronize payload bits separately.
    always @(posedge source_clk or posedge async_reset)
        if(async_reset)request_sync<=0;
        else if(source_reset)request_sync<=0;
        else request_sync<={request_sync[0],request};
    always @(posedge pixel_clk or posedge async_reset)
        if(async_reset)ack_sync<=0;
        else if(pixel_reset)ack_sync<=0;
        else ack_sync<={ack_sync[0],acknowledge};

    always @(posedge source_clk or posedge async_reset)begin
        if(async_reset)begin acknowledge<=0;held_data<=0;end
        else if(source_reset)begin acknowledge<=0;held_data<=0;end
        else if(!acknowledge && request_sync[1])begin
            held_data<=source_data;
            acknowledge<=1;
        end else if(acknowledge && !request_sync[1])acknowledge<=0;
    end
    always @(posedge pixel_clk or posedge async_reset)begin
        if(async_reset)begin
            request<=0;pixel_data<=0;pixel_valid<=0;update_pulse<=0;
        end else if(pixel_reset)begin
            request<=0;pixel_data<=0;pixel_valid<=0;update_pulse<=0;
        end else begin
            update_pulse<=0;
            if(!request && !ack_sync[1])request<=1;
            else if(request && ack_sync[1])begin
                // Payload has been held while ACK crossed two pixel registers.
                pixel_data<=held_data;
                pixel_valid<=1;
                update_pulse<=1;
                request<=0;
            end
        end
    end
endmodule
`timescale 1ns/1ps
// No panel-specific timing defaults: zero porches/syncs are invalid sentinels.
// Supply all six values and both polarities from a verified panel profile.
module rgb_scan_timing #(
    parameter integer H_ACTIVE=800,V_ACTIVE=480,
    H_SYNC=0,H_BACK=0,H_FRONT=0,V_SYNC=0,V_BACK=0,V_FRONT=0,
    HS_ACTIVE=0,VS_ACTIVE=0,DE_ONLY=0
)(
    input wire pixel_clk,rst,
    output wire [10:0] x,y,
    output wire de,hs,vs,frame_start
);
    localparam integer H_TOTAL=H_SYNC+H_BACK+H_ACTIVE+H_FRONT;
    localparam integer V_TOTAL=V_SYNC+V_BACK+V_ACTIVE+V_FRONT;
    localparam integer X_START=H_SYNC+H_BACK,Y_START=V_SYNC+V_BACK;
    reg [10:0] hpos,vpos;
    wire visible_h=(hpos>=X_START && hpos<X_START+H_ACTIVE);
    wire visible_v=(vpos>=Y_START && vpos<Y_START+V_ACTIVE);
    // Coordinates outside the active window are deterministic zero; DE gates them.
    assign x=visible_h ? hpos-X_START : 11'd0;
    assign y=visible_v ? vpos-Y_START : 11'd0;
    assign de=!rst && visible_h && visible_v;
    assign hs=(!DE_ONLY && hpos<H_SYNC) ? HS_ACTIVE[0] : !HS_ACTIVE[0];
    assign vs=(!DE_ONLY && vpos<V_SYNC) ? VS_ACTIVE[0] : !VS_ACTIVE[0];
    // Origin is inside vertical AND horizontal blanking, before any active pixel.
    assign frame_start=!rst && hpos==0 && vpos==0;
    always @(posedge pixel_clk)begin
        if(rst)begin hpos<=0;vpos<=0;end
        else if(hpos==H_TOTAL-1)begin
            hpos<=0;
            if(vpos==V_TOTAL-1)vpos<=0;
            else vpos<=vpos+1'b1;
        end else hpos<=hpos+1'b1;
    end

    initial begin
        if(H_ACTIVE<1 || V_ACTIVE<1 || H_SYNC<0 || V_SYNC<0 ||
           (!DE_ONLY && (H_SYNC<1 || V_SYNC<1)) ||
           H_BACK<1 || V_BACK<1 || H_FRONT<1 || V_FRONT<1 ||
           H_TOTAL>2048 || V_TOTAL>2048 ||
           (HS_ACTIVE!=0 && HS_ACTIVE!=1) || (VS_ACTIVE!=0 && VS_ACTIVE!=1))
            $fatal(1,"rgb_scan_timing requires an explicit, valid panel timing profile");
    end

endmodule
`timescale 1ns/1ps
// British black/gold UI. Layout, glyph/ROM and output are three pixel stages.
// One atomic1112-bit snapshot per frame; no framebuffer and no audio stalls.
module rgb_ui_renderer(
 input wire pixel_clk,rst,frame_start,status_valid,input wire [1111:0] status_data,
 input wire [10:0] x,y,input wire de_in,hs_in,vs_in,
 output reg [23:0] rgb,output reg de_out,hs_out,vs_out,input wire [81:0] more_data);
// Shared actions and half-open rectangles for the British UI,800x480.
localparam [5:0] UI_SINE=0,UI_FLUTE=1,UI_REED=2,UI_ECHO=3,UI_ROOM=4,
 UI_TREMOLO=5,UI_FX=6,UI_MODE=7,UI_LESS=8,UI_MORE=9,
 UI_SLOWER=10,UI_FASTER=11,UI_DEFAULTS=12,UI_CELLO=13,UI_PIANO=14,
 UI_GUITAR=15,UI_VIBES=16,UI_PREV=17,UI_NEXT=18,UI_VOLUME_DOWN=19,UI_VOLUME_UP=20,
 UI_OPEN_MORE=21,UI_MORE_BACK=22,UI_SONG_PREV=23,UI_SONG_NEXT=24,UI_SONG_PLAY=25,
 UI_SONG_PAUSE=26,UI_SONG_RESUME=27,UI_SONG_STOP=28,UI_SONG_LOAD=29,UI_SONG_SAVE=30,
 UI_SONG_DELETE=31,UI_FLASH_INFO=32,UI_NONE=63;
function automatic ui_inside(input integer px,py,left,top,width,height);
 begin ui_inside=px>=left && px<left+width && py>=top && py<top+height;end
endfunction
function automatic integer timbre_x(input integer id);
 begin timbre_x=28+(id%2)*124;end
endfunction
function automatic integer timbre_y(input integer id);
 begin timbre_y=132+(id/2)*64;end
endfunction
function automatic [5:0] timbre_action(input integer id);
 begin case(id)
 0:timbre_action=UI_SINE;1:timbre_action=UI_FLUTE;2:timbre_action=UI_REED;
 3:timbre_action=UI_CELLO;4:timbre_action=UI_PIANO;5:timbre_action=UI_GUITAR;
 6:timbre_action=UI_VIBES;default:timbre_action=UI_NONE;endcase end
endfunction
function automatic [5:0] ui_hit(input integer px,py,input [1:0] fx,input menu);
 integer i;
 begin
  ui_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))ui_hit=UI_MODE;
  else if(menu)begin
   for(i=0;i<7;i=i+1)
    if(ui_inside(px,py,timbre_x(i),timbre_y(i),112,52))ui_hit=timbre_action(i);
   if(ui_inside(px,py,152,324,112,52))ui_hit=UI_FX;
   if(ui_inside(px,py,308,124,148,48))ui_hit=UI_ECHO;
   if(ui_inside(px,py,464,124,148,48))ui_hit=UI_ROOM;
   if(ui_inside(px,py,620,124,148,48))ui_hit=UI_TREMOLO;
   if(ui_inside(px,py,308,240,52,48))ui_hit=UI_LESS;
   if(ui_inside(px,py,716,240,52,48))ui_hit=UI_MORE;
   if(fx==2 && ui_inside(px,py,308,344,52,48))ui_hit=UI_SLOWER;
   if(fx==2 && ui_inside(px,py,716,344,52,48))ui_hit=UI_FASTER;
   if(ui_inside(px,py,24,420,44,44))ui_hit=UI_VOLUME_DOWN;
   if(ui_inside(px,py,272,420,44,44))ui_hit=UI_VOLUME_UP;
   if(ui_inside(px,py,664,420,116,44))ui_hit=UI_DEFAULTS;
   if(ui_inside(px,py,550,420,104,44))ui_hit=UI_OPEN_MORE;
  end
 end
endfunction
function automatic [5:0] more_hit(input integer px,py);
 begin
  more_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))more_hit=UI_MORE_BACK;
  if(ui_inside(px,py,24,200,160,40))more_hit=UI_SONG_PREV;
  if(ui_inside(px,py,204,200,160,40))more_hit=UI_SONG_NEXT;
  if(ui_inside(px,py,384,200,160,40))more_hit=UI_SONG_LOAD;
  if(ui_inside(px,py,564,200,160,40))more_hit=UI_SONG_PLAY;
  if(ui_inside(px,py,24,252,160,40))more_hit=UI_SONG_PAUSE;
  if(ui_inside(px,py,204,252,160,40))more_hit=UI_SONG_RESUME;
  if(ui_inside(px,py,384,252,160,40))more_hit=UI_SONG_STOP;
  if(ui_inside(px,py,24,304,160,40))more_hit=UI_SONG_SAVE;
  if(ui_inside(px,py,204,304,160,40))more_hit=UI_SONG_DELETE;
  if(ui_inside(px,py,384,304,160,40))more_hit=UI_FLASH_INFO;
 end
endfunction
 localparam [23:0] BG=24'h101214,PANEL=24'h191c20,GOLD=24'hd6b979,
  CREAM=24'hf2e6c9,INK=24'h17191b,DIM=24'h9c987f,LINE=24'h4b4534,
  WINE=24'h67333e,GREEN=24'h8bc79b,RED=24'hef8f85;
 reg [1111:0] state;
 reg [81:0] more_state;
 wire [2:0] timbre={state[53],state[13:12]};
 wire [1:0] fx=state[22:21];wire menu=state[20],enabled=state[23];
 wire [6:0] percent=fx==0 ? state[30:24] : fx==1 ? state[37:31] : state[44:38];
 wire [3:0] rate=state[48:45];
 wire [6:0] volume=state[60:54];
 wire [5:0] voices=state[5:0]>32 ? 6'd32 : state[5:0];
 wire [7:0] peak=state[87:80];
 reg [23:0] base,fg,base_pipe,fg_pipe;
 reg [319:0] text;
 reg [5:0] len,ci;
 reg [10:0] tx,ty;
 reg signed [11:0] dx,dy;
 integer px,py,i,k,left,top,note_index;
 reg [6:0] bin;
 integer point_y,previous_y,minimum_y,maximum_y,pc;
 reg [7:0] ch;reg [11:0] font_addr;reg [3:0] font_bit,bit_pipe;
 reg text_ink,ink_pipe,de_pipe,hs_pipe,vs_pipe;
 reg [7:0] glyph_char;
 reg [319:0] glyph_text;reg [5:0] glyph_len;
 reg signed [11:0] glyph_dx,glyph_dy;
 reg glyph_title,glyph_allow;
 reg [11:0] title_address;
 reg [3:0] title_bit;
 reg [23:0] base_layout,fg_layout;
 reg de_layout,hs_layout,vs_layout;
 always @*begin
  font_addr=0;font_bit=0;text_ink=0;ci=0;glyph_char=0;
  if(glyph_allow && glyph_len>0 && glyph_dx>=0 && glyph_dx<glyph_len*12'd10 && glyph_dy>=0 && glyph_dy<16)begin
   ci=glyph_dx/12'd10;glyph_char=glyph_text[(glyph_len-6'd1-ci)*8+:8];
   if(glyph_char>=32 && glyph_char<128)begin font_addr=(glyph_char-8'd32)*12'd16+glyph_dy;font_bit=15-(glyph_dx%12'd10);text_ink=1;end
  end
  if(glyph_title)begin font_addr=title_address;font_bit=title_bit;text_ink=1;end
 end
 reg [15:0] font_rom[0:4095],font_row;
 initial $readmemh("src/rom/british_font.hex",font_rom);
 function automatic [7:0] digit(input integer value);
  begin digit=8'd48+value;end
 endfunction
 function automatic [7:0] hex_digit(input [3:0] value);
  begin hex_digit=value<10?8'd48+value:8'd65+value-8'd10;end
 endfunction
 function automatic [79:0] timbre_name(input [2:0] id);
  begin case(id)
   1:timbre_name="FLUTE";2:timbre_name="REED";3:timbre_name="CELLO";
   4:timbre_name="PIANO";5:timbre_name="GUITAR";6:timbre_name="VIBRAPHONE";
   default:timbre_name="SINE";endcase end
 endfunction
 function automatic integer name_length(input [2:0] id);
  begin case(id)1,3,4:name_length=5;2,0:name_length=4;5:name_length=6;default:name_length=10;endcase end
 endfunction
 function automatic [23:0] card(input integer xx,yy,l,t,w,h,input selected);
  begin
   card=selected ? CREAM : PANEL;
   if(xx<l+1 || xx>=l+w-1 || yy<t+1 || yy>=t+h-1)card=selected ? GOLD : LINE;
  end
 endfunction
 always @*begin
  px=integer'(x);py=integer'(y);base=BG;fg=CREAM;text=0;len=0;tx=0;ty=0;
  dx=0;dy=0;i=0;k=0;left=0;top=0;note_index=0;pc=0;
  bin=0;point_y=234;previous_y=234;minimum_y=234;maximum_y=234;
  ch=0;
  // Sparse faint celestial motifs. Ornament is kept outside touch controls.
  if((py==78 && px>=20 && px<780) || (py==410 && px>=20 && px<780))base=LINE;
  if(px>398 && px<632 && py<72)begin
   if((px==412 && py>=6 && py<=14) || (py==10 && px>=408 && px<=416) ||
      (px==628 && py>=60 && py<=68) || (py==64 && px>=624 && px<=632))base=GOLD;
  end
  if(ui_inside(px,py,648,16,132,48))base=card(px,py,648,16,132,48,1'b0);
  if(menu)begin
   if(ui_inside(px,py,20,92,260,310) || ui_inside(px,py,296,92,484,88) ||
      ui_inside(px,py,296,194,484,102) || ui_inside(px,py,296,306,484,96))base=PANEL;
   for(i=0;i<7;i=i+1)begin
    left=timbre_x(i);top=timbre_y(i);
    if(ui_inside(px,py,left,top,112,52))begin
     base=card(px,py,left,top,112,52,timbre==i);
     fg=timbre==i ? INK : CREAM;text=timbre_name(i);len=name_length(i);
     tx=left+(112-len*10)/2;ty=top+18;
    end
   end
   if(ui_inside(px,py,152,324,112,52))begin
    base=card(px,py,152,324,112,52,enabled);fg=enabled ? INK : DIM;
    text=enabled ? "FX ON" : "FX OFF";len=enabled ? 5 : 6;tx=enabled ? 183 : 178;ty=342;
   end
   for(i=0;i<3;i=i+1)begin
    left=308+156*i;
    if(ui_inside(px,py,left,124,148,48))begin
     base=card(px,py,left,124,148,48,fx==i);fg=fx==i ? INK : CREAM;
     text=i==0 ? "ECHO" : i==1 ? "ROOM" : "TREMOLO";len=i==2 ? 7 : 4;
     tx=left+(148-len*10)/2;ty=140;
    end
   end
   if(ui_inside(px,py,308,240,52,48) || ui_inside(px,py,716,240,52,48) ||
      (fx==2 && (ui_inside(px,py,308,344,52,48) || ui_inside(px,py,716,344,52,48))))begin
    left=px<400 ? 308 : 716;top=py<300 ? 240 : 344;
    base=card(px,py,left,top,52,48,1'b0);fg=GOLD;text=px<400 ? "-" : "+";len=1;tx=left+21;ty=top+16;
   end
   if(px>=380 && px<680 && py>=260 && py<270)base=(px-380)<integer'(percent)*3 ? GOLD : BG;
   if(fx==2 && px>=380 && px<680 && py>=366 && py<376)base=(px-380)<integer'(rate)*30 ? WINE : BG;
   if(py>=98 && py<118)begin
    if(px<280)begin text="Timbre";len=6;tx=32;ty=100;fg=GOLD;end
    else begin text="Effect";len=6;tx=308;ty=100;fg=GOLD;end
   end
   if(py>=208 && py<228 && px>=308)begin
    ty=210;fg=GOLD;
    if(px<536)begin text=fx==2 ? "DEPTH" : "AMOUNT";len=fx==2 ? 5 : 6;tx=308;end
    else begin text={(percent==100 ? 8'd49 : 8'd32),(percent>=10 ? digit((percent/10)%10) : 8'd32),digit(percent%10),"%"};len=4;tx=696;end
   end
   if(py>=314 && py<336 && px>=308)begin
    text=fx==0 ? "DELAY TIME" : fx==1 ? "ROOM MODEL" : "RATE";len=fx==2 ? 4 : 10;tx=308;ty=316;fg=DIM;
    if(px>=656 && fx==2)begin text={rate==10 ? 8'd49 : 8'd32,digit(rate%10)," HZ"};len=5;tx=688;fg=GOLD;end
   end
   if(fx!=2 && py>=344 && py<384 && px>=380)begin
    text=fx==0 ? "150 MS" : "SMALL ROOM";len=fx==0 ? 6 : 10;tx=fx==0 ? 510 : 490;ty=356;fg=CREAM;
   end
   if(ui_inside(px,py,664,420,116,44))begin
    base=card(px,py,664,420,116,44,1'b0);text="RESET";len=5;tx=697;ty=434;fg=GOLD;
   end
  end else begin
   if(ui_inside(px,py,20,128,552,196) || ui_inside(px,py,588,128,192,196) || ui_inside(px,py,20,338,760,68))base=PANEL;
   if(py>=94 && py<114)begin
    ty=96;fg=GOLD;
    if(px<296)begin text=timbre_name(timbre);len=name_length(timbre);tx=24;end
    else if(px<560)begin text=enabled ? (fx==0 ? "ECHO ON" : fx==1 ? "ROOM ON" : "TREMOLO ON") : "EFFECTS OFF";len=enabled ? (fx==2 ? 10 : 7) : 11;tx=310;end
    else begin text=state[14] ? "AUTO SCORE" : "LIVE KEYS";len=state[14] ? 10 : 9;tx=620;fg=DIM;end
   end
   if(ui_inside(px,py,32,164,512,140))begin
    if((px-32)%64==0 || (py-164)%35==0)base=24'h292c2c;
    bin=(px-32)>>2;
    point_y=234-($signed(state[88+bin*8+:8])>>>1);
    if(bin>0)previous_y=234-($signed(state[88+(bin-1)*8+:8])>>>1);else previous_y=point_y;
    minimum_y=point_y<previous_y ? point_y : previous_y;
    maximum_y=point_y>previous_y ? point_y : previous_y;
    if(py==point_y || ((px-32)%4==0 && py>=minimum_y && py<=maximum_y))base=GOLD;
   end
   if(py>=138 && py<158)begin
    ty=140;fg=DIM;
    if(px<390)begin text="OUTPUT WAVEFORM";len=15;tx=32;end
    else if(px<572)begin text="X8 DISPLAY";len=10;tx=440;end
    else begin text="LEVEL";len=5;tx=608;end
   end
   if(px>=608 && px<760 && py>=200 && py<224)base=(px-608)<(integer'(peak)*152>>8) ? (peak>=248 ? RED : GOLD) : BG;
   if(py>=244 && py<264 && px>=608)begin
    pc=(integer'(peak)*100+127)/255;
    text={pc==100 ? 8'd49 : 8'd32,pc>=10 ? digit((pc/10)%10) : 8'd32,digit(pc%10),"% PEAK"};len=9;tx=608;ty=246;fg=DIM;
   end
   if(py>=280 && py<300 && px>=608)begin text=peak>=248 ? "NEAR FULL" : "PCM OUTPUT";len=peak>=248 ? 9 : 10;tx=608;ty=282;fg=peak>=248 ? RED : DIM;end
   if(py>=348 && py<396 && px>=32 && px<768)begin
    note_index=(px-32)/46;left=32+note_index*46;
    if(px<left+42)begin
     base=state[64+note_index] ? GOLD : BG;fg=state[64+note_index] ? INK : DIM;
     // Exact chromatic MIDI60..75; these are monitors, not touch piano keys.
     case(note_index%12)
      0:ch="C";1:ch="C";2:ch="D";3:ch="D";4:ch="E";5:ch="F";
      6:ch="F";7:ch="G";8:ch="G";9:ch="A";10:ch="A";default:ch="B";
     endcase
     text={ch,(note_index%12==1 || note_index%12==3 || note_index%12==6 || note_index%12==8 || note_index%12==10) ? 8'd35 : 8'd32,digit(note_index<12 ? 4 : 5)};
     len=3;tx=left+6;ty=364;
    end
   end
  end
  // Shared header/status and mode action appear on both pages.
  if(py>=16 && py<64 && px>=648)begin
   text=menu ? "RETURN" : "SETTINGS";len=menu ? 6 : 8;tx=menu ? 684 : 674;ty=32;fg=GOLD;
  end
  if(px>=420 && px<640 && py>=22 && py<62)begin
   tx=430;fg=DIM;
   if(py<42)begin text={"VOICES ",digit(voices/10),digit(voices%10),"/32"};len=12;ty=24;end
   else begin text=state[15] ? "AUDIO READY" : "STARTING";len=state[15] ? 11 : 8;ty=46;fg=state[15] ? GREEN : GOLD;end
  end
  if(py>=420 && py<464 && px<648 && !(menu && px<336))begin
   tx=24;fg=DIM;
   if(py<440)begin
    text=menu ? "R4C2 PREV / R4C3 NEXT TIMBRE" : "S0 HOLD: SETTINGS";len=menu ? 28 : 17;ty=422;
    if(px>=336)begin
     if(!state[49])begin text="TOUCH OFF";len=9;end
     else if(state[52])begin text="TOUCH ERROR";len=11;fg=RED;end
     else if(!state[51])begin text="TOUCH WAIT";len=10;end
     else if(!state[50])begin text="TOUCH MONITOR";len=13;end
     else begin text="TOUCH READY";len=11;fg=GREEN;end
     tx=360;
    end
   end else begin
    text=menu ? "S1-/S2+ VOLUME" : "NOTE MONITOR C4-D#5 / 10.7 MS WINDOW";
    len=menu ? 14 : 36;ty=446;if(menu)tx=360;
    if(state[16] || state[17] || state[18])begin text=state[18] ? "GHOST KEYS" : "AUDIO ERROR";len=state[18] ? 10 : 11;fg=RED;end
   end
  end
  if(menu && ui_inside(px,py,24,420,292,44))begin
   fg=GOLD;ty=434;
   if(px<68 || px>=272)begin
    left=px<68 ? 24 : 272;base=card(px,py,left,420,44,44,0);
    text=px<68 ? "-" : "+";len=1;tx=left+17;
   end else begin
    text={"VOL ",volume==100 ? 8'd49 : 8'd32,volume>=10 ? digit((volume/10)%10) : 8'd32,digit(volume%10),"%"};len=8;tx=116;
   end
  end
  if(menu && ui_inside(px,py,550,420,104,44))begin
   base=card(px,py,550,420,104,44,0);fg=GOLD;text="more";len=4;tx=582;ty=434;
  end
  // Minimal fixed character rows; original two pages retain their layout.
  if(menu && more_state[81])begin
   base=BG;fg=CREAM;text=0;len=0;tx=24;ty=32;
   if(py<80)begin
    if(px<648)begin text="MORE";len=4;end else begin text="BACK";len=4;tx=680;fg=GOLD;end
   end else if(py<124)begin text="BT  16 VOICES / 4096 NOTES";len=26;ty=100;end
   else if(py<180)begin
    text={"SONG S",digit((integer'(more_state[4:0])+1)/100),digit(((integer'(more_state[4:0])+1)/10)%10),digit((integer'(more_state[4:0])+1)%10),more_state[5]?" VALID":" EMPTY"};len=15;ty=148;
   end else if(py>=200 && py<240)begin
    i=px<204?0:px<384?1:px<564?2:3;tx=24+i*180;ty=212;
    case(i)0:begin text="PREV";len=4;end 1:begin text="NEXT";len=4;end 2:begin text="LOAD";len=4;end default:begin text="PLAY";len=4;end endcase
   end else if(py>=252 && py<292)begin
    i=px<204?0:px<384?1:2;tx=24+i*180;ty=264;
    case(i)0:begin text="PAUSE";len=5;end 1:begin text="RESUME";len=6;end default:begin text="STOP";len=4;end endcase
   end else if(py>=304 && py<344)begin
    i=px<204?0:px<384?1:2;tx=24+i*180;ty=316;fg=GOLD;
    case(i)0:begin text="SAVE";len=4;end 1:begin text="DELETE";len=6;end default:begin text="FLASH INFO";len=10;end endcase
   end else if(py>=356 && py<388)begin
    text={more_state[6]?"BUSY ":"READY"," ID ",hex_digit(more_state[57:54]),hex_digit(more_state[53:50]),hex_digit(more_state[49:46]),hex_digit(more_state[45:42]),hex_digit(more_state[41:38]),hex_digit(more_state[37:34])};len=15;ty=364;
    if(!more_state[58])begin text="FLASH UNKNOWN / READ ONLY";len=25;fg=GOLD;end
    if(more_state[79])begin
     text={"JOB ",hex_digit(more_state[76:73]),hex_digit(more_state[72:69]),hex_digit(more_state[68:65]),hex_digit(more_state[64:61])," NOTES ",hex_digit(more_state[33:30]),hex_digit(more_state[29:26]),hex_digit(more_state[25:22]),hex_digit(more_state[21:18])};len=19;fg=GOLD;
    end
   end else if(py>=400 && py<428)begin
    text={"ERROR ",hex_digit(more_state[15:12]),hex_digit(more_state[11:8]),"   ",more_state[17:16]==1?"PLAYING":more_state[17:16]==2?"PAUSED ":"STOPPED"};len=18;ty=406;fg=more_state[15:8]!=0?RED:DIM;
   end else if(py>=436 && py<468)begin
    text=more_state[80]?"DELETE AGAIN TO CONFIRM / BACK CANCEL":"R4C4 BACK / S0 HOLD EXIT";len=more_state[80]?37:24;ty=442;fg=GOLD;
   end
  end
  dx=$signed({1'b0,x})-$signed({1'b0,tx});dy=$signed({1'b0,y})-$signed({1'b0,ty});
  if(ui_inside(px,py,24,4,384,64))fg=GOLD;
  if(state[19])begin
   case(px/100)
    0:base=24'hffffff;1:base=24'hffff00;2:base=24'h00ffff;3:base=24'h00ff00;
    4:base=24'hff00ff;5:base=24'hff0000;6:base=24'h0000ff;default:base=0;
   endcase
   if(px==0 || px==799 || py==0 || py==479)base=CREAM;
  end
  if(!de_in || px>=800 || py>=480)begin base=0;end
 end
 // Synchronous font ROM; RGB/DE/HS/VS all traverse the same three stages.
 always @(posedge pixel_clk)begin
  font_row<=font_rom[font_addr];
  if(rst)begin glyph_text<=0;glyph_len<=0;glyph_dx<=0;glyph_dy<=0;glyph_title<=0;glyph_allow<=0;
   title_address<=0;title_bit<=0;base_layout<=0;fg_layout<=0;de_layout<=0;hs_layout<=0;vs_layout<=0;state<=0;base_pipe<=0;fg_pipe<=0;bit_pipe<=0;ink_pipe<=0;
   de_pipe<=0;hs_pipe<=0;vs_pipe<=0;rgb<=0;de_out<=0;hs_out<=0;vs_out<=0;more_state<=0;end
  else begin
   if(frame_start && status_valid)begin state<=status_data;more_state<=more_data[81]===1'b1 ? more_data : 82'd0;end
   glyph_text<=text;glyph_len<=len;glyph_dx<=dx;glyph_dy<=dy;
   glyph_allow<=de_in && x<800 && y<480 && !state[19];
   glyph_title<=de_in && !state[19] && !(menu && more_state[81]) && ui_inside(px,py,24,4,384,64);
   title_address<=1536+(py-4)*24+((px-24)>>4);title_bit<=15-((px-24)%16);
   base_layout<=base;fg_layout<=fg;de_layout<=de_in && x<800 && y<480;hs_layout<=hs_in;vs_layout<=vs_in;
   base_pipe<=base_layout;fg_pipe<=fg_layout;
   bit_pipe<=font_bit;ink_pipe<=text_ink;de_pipe<=de_layout;hs_pipe<=hs_layout;vs_pipe<=vs_layout;
   rgb<=ink_pipe && font_row[bit_pipe] ? fg_pipe : base_pipe;
   de_out<=de_pipe;hs_out<=hs_pipe;vs_out<=vs_pipe;
  end
 end
endmodule
`timescale 1ns/1ps
// Read-only sensor configuration: reads ID/resolution/status/first point and
// clears consumed status. Never rewrites the panel's sensor tuning/configuration.
module gt9110_touch #(
    parameter integer RESET_CYCLES=1000000,STRAP_CYCLES=300000,BOOT_CYCLES=2500000,
    POLL_CYCLES=500000,I2C_HALF_CYCLES=250,I2C_TIMEOUT_CYCLES=50000
)(
    input wire clk,rst,
    inout wire touch_scl,touch_sda,touch_int,touch_rst_n,
    output reg ready,error,touch_down,report_pulse,
    output reg [3:0] touch_count,
    output reg [15:0] touch_x,touch_y,touch_size,
    output reg [7:0] track_id,
    output reg [31:0] product_id,
    output reg [15:0] resolution_x,resolution_y
);
    localparam RESET=0,STRAP=1,BOOT=2,ID_START=3,ID_WAIT=4,RES_START=5,RES_WAIT=6,
        POLL_START=7,POLL_WAIT=8,CLEAR_START=9,CLEAR_WAIT=10,DELAY=11;
    reg [3:0] state,retry_state;
    reg [31:0] counter;
    reg start,read_request;
    reg [15:0] address;
    reg [3:0] length;
    wire scl_low,sda_low,busy,done,bus_error;
    wire [71:0] data;
    reg [3:0] pending_count;
    reg [15:0] pending_x,pending_y,pending_size;
    reg [7:0] pending_id;
    reg pending_bad;
    // Low INT during reset selects 8-bit BA/BB, i.e. 7-bit device address 5D.
    // Release means high impedance: external module pull-ups provide HIGH.
    assign touch_scl=scl_low?1'b0:1'bz;
    assign touch_sda=sda_low?1'b0:1'bz;
    assign touch_rst_n=(rst || state==RESET)?1'b0:1'bz;
    assign touch_int=(rst || state==RESET || state==STRAP)?1'b0:1'bz;
    i2c_register_master #(.HALF_CYCLES(I2C_HALF_CYCLES),.TIMEOUT_CYCLES(I2C_TIMEOUT_CYCLES))
        bus(clk,rst,start,read_request,address,8'd0,length,touch_scl,touch_sda,
            scl_low,sda_low,busy,done,bus_error,data);
    task begin_read(input [15:0] reg_addr,input [3:0] bytes,input [3:0] next_state);
        begin address<=reg_addr;length<=bytes;read_request<=1;start<=1;state<=next_state;end
    endtask
    task failed(input [3:0] retry);
        begin
            error<=1;touch_down<=0;touch_count<=0;report_pulse<=1;
            retry_state<=retry;counter<=0;state<=DELAY;
        end
    endtask
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=RESET;retry_state<=ID_START;counter<=0;start<=0;read_request<=1;
            address<=0;length<=1;ready<=0;error<=0;touch_down<=0;report_pulse<=0;
            touch_count<=0;touch_x<=0;touch_y<=0;touch_size<=0;track_id<=0;
            product_id<=0;resolution_x<=0;resolution_y<=0;
            pending_count<=0;pending_x<=0;pending_y<=0;pending_size<=0;pending_id<=0;pending_bad<=0;
        end else begin
            start<=0;report_pulse<=0;
            case(state)
                RESET:if(counter==RESET_CYCLES-1)begin counter<=0;state<=STRAP;end
                    else counter<=counter+1'b1;
                STRAP:if(counter==STRAP_CYCLES-1)begin counter<=0;state<=BOOT;end
                    else counter<=counter+1'b1;
                BOOT:if(counter==BOOT_CYCLES-1)begin counter<=0;state<=ID_START;end
                    else counter<=counter+1'b1;
                ID_START:if(!busy)begin_read(16'h8140,4,ID_WAIT);
                ID_WAIT:if(done)begin
                    if(bus_error)failed(ID_START);
                    else begin product_id<=data[31:0];state<=RES_START;end
                end
                RES_START:if(!busy)begin_read(16'h8146,4,RES_WAIT);
                RES_WAIT:if(done)begin
                    if(bus_error)failed(RES_START);
                    else begin
                        resolution_x<=data[15:0];resolution_y<=data[31:16];
                        ready<=1;error<=0;state<=POLL_START;
                    end
                end
                POLL_START:if(!busy)begin_read(16'h814e,9,POLL_WAIT);
                POLL_WAIT:if(done)begin
                    if(bus_error)failed(POLL_START);
                    else if(!data[7])begin
                        counter<=0;retry_state<=POLL_START;state<=DELAY;
                    end else begin
                        pending_count<=data[3:0];pending_bad<=data[3:0]>10;
                        pending_id<=data[15:8];pending_x<=data[31:16];
                        pending_y<=data[47:32];pending_size<=data[63:48];state<=CLEAR_START;
                    end
                end
                CLEAR_START:if(!busy)begin
                    address<=16'h814e;length<=1;read_request<=0;start<=1;state<=CLEAR_WAIT;
                end
                CLEAR_WAIT:if(done)begin
                    if(bus_error || pending_bad)failed(POLL_START);
                    else begin
                        touch_count<=pending_count;touch_down<=pending_count!=0;report_pulse<=1;
                        touch_x<=pending_count!=0?pending_x:16'd0;
                        touch_y<=pending_count!=0?pending_y:16'd0;
                        touch_size<=pending_count!=0?pending_size:16'd0;
                        track_id<=pending_count!=0?pending_id:8'd0;error<=0;
                        counter<=0;retry_state<=POLL_START;state<=DELAY;
                    end
                end
                DELAY:if(counter==POLL_CYCLES-1)begin counter<=0;state<=retry_state;end
                    else counter<=counter+1'b1;
                default:begin state<=RESET;counter<=0;ready<=0;touch_down<=0;end
            endcase
        end
    end

    initial if(RESET_CYCLES<1 || STRAP_CYCLES<1 || BOOT_CYCLES<1 || POLL_CYCLES<1)
        $fatal(1,"GT9110 delay parameters must be positive");

endmodule
`timescale 1ns/1ps
// Single-master, open-drain I2C register transactions: 16-bit register address,
// one-byte writes or 1..9-byte reads, repeated START, clock stretching, timeout.
// All state uses clk + counters; SCL is never an internal clock.
module i2c_register_master #(
    parameter integer HALF_CYCLES=250,TIMEOUT_CYCLES=50000,
    DATA_HOLD_CYCLES=(HALF_CYCLES+9)/10,
    parameter [6:0] DEVICE_ADDR=7'h5d
)(
    input wire clk,rst,start,read_request,
    input wire [15:0] register_addr,
    input wire [7:0] write_data,
    input wire [3:0] read_bytes,
    input wire scl_in,sda_in,
    output reg scl_low,sda_low,busy,done,error,
    output reg [71:0] read_data
);
    localparam IDLE=0,FREE=1,START_HOLD=2,TX_LOW=3,TX_RISE=4,TX_HIGH=5,
        ACK_LOW=6,ACK_RISE=7,ACK_HIGH=8,RX_LOW=9,RX_RISE=10,RX_HIGH=11,
        MACK_LOW=12,MACK_RISE=13,MACK_HIGH=14,RE_LOW=15,RE_RISE=16,RE_HIGH=17,
        STOP_LOW=18,STOP_RISE=19,STOP_HIGH=20,STOP_FREE=21;
    reg [4:0] state;
    reg [31:0] timer,timeout_count;
    reg [15:0] address;
    reg [7:0] tx,rx,write_byte;
    reg [3:0] length,byte_index;
    reg [2:0] bit_index,stage;
    reg reading,repeated;
    reg next_sda_low;
    (* syn_preserve=1,syn_async_reg=1 *) reg [1:0] scl_sync,sda_sync;
    always @(posedge clk or posedge rst)
        if(rst)begin scl_sync<=3;sda_sync<=3;end
        else begin scl_sync<={scl_sync[0],scl_in};sda_sync<={sda_sync[0],sda_in};end

    task low_phase(input bit next_low,input [4:0] next_state);
        begin
            // Hold the observed previous data through SCL falling, then change
            // SDA inside the low interval (default 25 clocks = 0.5us at 50MHz).
            scl_low<=1;sda_low<=!sda_sync[1];next_sda_low<=next_low;
            timer<=HALF_CYCLES-1;state<=next_state;
        end
    endtask
    task send_byte(input [7:0] value,input [2:0] phase);
        begin
            tx<=value;stage<=phase;bit_index<=7;
            low_phase(!value[7],TX_LOW);
        end
    endtask
    task stop_bus;
        begin low_phase(1'b1,STOP_LOW);end
    endtask
    task abort_bus;
        begin scl_low<=0;sda_low<=0;busy<=0;done<=1;error<=1;state<=IDLE;end
    endtask
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=IDLE;timer<=0;timeout_count<=0;address<=0;tx<=0;rx<=0;write_byte<=0;
            length<=0;byte_index<=0;bit_index<=0;stage<=0;reading<=0;repeated<=0;
            next_sda_low<=0;
            scl_low<=0;sda_low<=0;busy<=0;done<=0;error<=0;read_data<=0;
        end else begin
            done<=0;
            case(state)
                IDLE:if(start)begin
                    error<=0;read_data<=0;address<=register_addr;write_byte<=write_data;
                    reading<=read_request;length<=read_bytes;byte_index<=0;repeated<=0;
                    busy<=1;timer<=HALF_CYCLES-1;timeout_count<=0;state<=FREE;
                    if(read_request && (read_bytes<1 || read_bytes>9))abort_bus();
                end
                FREE:begin
                    if(timeout_count==TIMEOUT_CYCLES-1)abort_bus();
                    else begin
                        timeout_count<=timeout_count+1'b1;
                        if(scl_sync[1] && sda_sync[1])begin
                            if(timer==0)begin sda_low<=1;timer<=HALF_CYCLES-1;state<=START_HOLD;end
                            else timer<=timer-1'b1;
                        end else timer<=HALF_CYCLES-1;
                    end
                end
                START_HOLD:if(timer!=0)timer<=timer-1'b1;
                    else if(repeated)send_byte({DEVICE_ADDR,1'b1},3);
                    else send_byte({DEVICE_ADDR,1'b0},0);
                TX_LOW,ACK_LOW,RX_LOW,MACK_LOW,RE_LOW,STOP_LOW:begin
                    if(timer==HALF_CYCLES-DATA_HOLD_CYCLES)sda_low<=next_sda_low;
                    if(timer!=0)timer<=timer-1'b1;
                    else begin
                        scl_low<=0;timeout_count<=0;
                        case(state)
                            TX_LOW:state<=TX_RISE;ACK_LOW:state<=ACK_RISE;
                            RX_LOW:state<=RX_RISE;MACK_LOW:state<=MACK_RISE;
                            RE_LOW:state<=RE_RISE;STOP_LOW:state<=STOP_RISE;
                        endcase
                    end
                end
                TX_RISE,ACK_RISE,RX_RISE,MACK_RISE,RE_RISE,STOP_RISE:begin
                    if(scl_sync[1])begin
                        timer<=HALF_CYCLES-1;
                        case(state)
                            TX_RISE:state<=TX_HIGH;ACK_RISE:state<=ACK_HIGH;
                            RX_RISE:state<=RX_HIGH;MACK_RISE:state<=MACK_HIGH;
                            RE_RISE:state<=RE_HIGH;STOP_RISE:state<=STOP_HIGH;
                        endcase
                    end else if(timeout_count==TIMEOUT_CYCLES-1)abort_bus();
                    else timeout_count<=timeout_count+1'b1;
                end
                TX_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else begin
                        if(bit_index!=0)begin
                            bit_index<=bit_index-1'b1;low_phase(!tx[bit_index-1],TX_LOW);
                        end else low_phase(1'b0,ACK_LOW);
                    end
                ACK_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else if(sda_sync[1]!==1'b0)begin error<=1;stop_bus();end
                    else case(stage)
                        0:send_byte(address[15:8],1);
                        1:send_byte(address[7:0],2);
                        2:if(reading)begin
                            low_phase(1'b0,RE_LOW);
                        end else send_byte(write_byte,4);
                        3:begin
                            bit_index<=7;rx<=0;low_phase(1'b0,RX_LOW);
                        end
                        4:stop_bus();
                        default:abort_bus();
                    endcase
                RE_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else begin sda_low<=1;repeated<=1;timer<=HALF_CYCLES-1;state<=START_HOLD;end
                RX_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else begin
                        rx<={rx[6:0],sda_sync[1]};
                        if(bit_index!=0)begin bit_index<=bit_index-1'b1;low_phase(1'b0,RX_LOW);end
                        else begin
                            read_data[byte_index*8+:8]<={rx[6:0],sda_sync[1]};
                            low_phase(byte_index+1<length,MACK_LOW);
                        end
                    end
                MACK_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else if(byte_index+1==length)stop_bus();
                    else begin
                        byte_index<=byte_index+1'b1;bit_index<=7;
                        rx<=0;low_phase(1'b0,RX_LOW);
                    end
                STOP_HIGH:if(timer!=0)timer<=timer-1'b1;
                    else begin sda_low<=0;timer<=HALF_CYCLES-1;state<=STOP_FREE;end
                STOP_FREE:if(timer!=0)timer<=timer-1'b1;
                    else if(scl_sync[1]!==1'b1 || sda_sync[1]!==1'b1)abort_bus();
                    else begin busy<=0;done<=1;state<=IDLE;end
                default:abort_bus();
            endcase
        end
    end

    initial if(HALF_CYCLES<4 || TIMEOUT_CYCLES<HALF_CYCLES*2 ||
        DATA_HOLD_CYCLES<1 || DATA_HOLD_CYCLES>=HALF_CYCLES-1)
        $fatal(1,"I2C half period must cover input synchronization and timeout must allow bus settling");

endmodule
`timescale 1ns/1ps
// One selectable effect after the shared mixer. Every engine advances once
// per accepted sample, including bypass. No internal derived clocks.
module audio_effects #(
    parameter integer DELAY_SAMPLES=7200,D0=1499,D1=1601,D2=1867,D3=2053,
    ECHO_WET=64,ROOM_WET=64,TREMOLO_MIN=128,
    parameter [31:0] LFO_STEP=32'd447392)(
    input wire clk,rst,enable,input wire [1:0] mode,
    input wire in_valid,input wire signed [15:0] in_sample,
    output wire in_ready,output reg out_valid,output reg signed [15:0] out_sample,
    // Atomic parameter snapshot, all in clk domain. Pulse valid only with
    // defined fields; disconnected legacy valid is ignored in simulation.
    input wire cfg_valid,input wire [8:0] cfg_echo_wet,cfg_room_wet,cfg_tremolo_depth,
    input wire [3:0] cfg_tremolo_rate_hz,output wire cfg_ready,output reg cfg_applied);
    wire echo_ready,echo_valid,room_ready,room_valid;
    wire signed [15:0] echo_dry,echo_history,room_sample;
    reg [2:0] stage;
    reg [1:0] active_mode,used_mode,requested_mode;
    reg [8:0] fade_level,used_fade;
    reg signed [15:0] dry,tremolo_sample;
    reg signed [31:0] candidate;
    reg [31:0] lfo_phase,phase_step;
    reg [8:0] echo_target,room_target,depth_target;
    reg [8:0] echo_level,room_level,depth_level,used_echo,used_room;
    assign cfg_ready=!rst;
    function automatic [8:0] clamp_amount(input [8:0] value);
        begin
            if (value > 9'd256)
                clamp_amount = 9'd256;
            else
                clamp_amount = value;
        end
    endfunction
    // round(hz * 2^32 / 48000); no division or variable frequency clock.
    function automatic [31:0] rate_step(input [3:0] hz);
        begin case(hz)
            0,1:rate_step=32'd89478;
            2:rate_step=32'd178957;
            3:rate_step=32'd268435;
            4:rate_step=32'd357914;
            5:rate_step=32'd447392;
            6:rate_step=32'd536871;
            7:rate_step=32'd626349;
            8:rate_step=32'd715828;
            9:rate_step=32'd805306;
            default:rate_step=32'd894785;
        endcase end
    endfunction
    function automatic [8:0] slew(input [8:0] current,input [8:0] target);
        begin slew=current<target?current+9'd1:current>target?current-9'd1:current;end
    endfunction
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            echo_target<=ECHO_WET;room_target<=ROOM_WET;
            depth_target<=256-TREMOLO_MIN;phase_step<=LFO_STEP;cfg_applied<=0;
        end else begin
            cfg_applied<=0;
            if(cfg_valid)begin
                echo_target<=clamp_amount(cfg_echo_wet);
                room_target<=clamp_amount(cfg_room_wet);
                depth_target<=clamp_amount(cfg_tremolo_depth);
                phase_step<=rate_step(cfg_tremolo_rate_hz);cfg_applied<=1;
            end
        end
    end
    wire [7:0] triangle=lfo_phase[31]?~lfo_phase[30:23]:lfo_phase[30:23];
    wire [16:0] depth_product={9'd0,triangle}*{8'd0,depth_level};
    wire [8:0] tremolo_gain=(9'd256-depth_level)+depth_product[16:8];
    wire signed [31:0] input_ext={{16{in_sample[15]}},in_sample};
    wire signed [31:0] gain_ext=$signed({23'd0,tremolo_gain});
    wire signed [31:0] tremolo_product=input_ext*gain_ext;
    wire signed [31:0] dry_ext={{16{dry[15]}},dry};
    wire signed [31:0] echo_ext={{16{echo_history[15]}},echo_history};
    wire signed [31:0] room_ext={{16{room_sample[15]}},room_sample};
    wire signed [31:0] echo_weight=$signed({23'd0,used_echo});
    wire signed [31:0] room_weight=$signed({23'd0,used_room});
    wire signed [31:0] fade_ext=$signed({23'd0,used_fade});
    wire signed [31:0] blend=(dry_ext<<<8)+(candidate-dry_ext)*fade_ext;
    wire signed [31:0] result=blend>>>8;
    assign in_ready=!rst && stage==0 && echo_ready && room_ready;
    wire accept=in_valid && in_ready;
    // Unconnected legacy mode inputs retain the original echo selection.
    always @* case(mode)
        2'd1:requested_mode=1;
        2'd2:requested_mode=2;
        default:requested_mode=0;
    endcase
    audio_delay #(.DELAY_SAMPLES(DELAY_SAMPLES)) echo(
        .clk(clk),.rst(rst),.enable(1'b0),.in_valid(accept),.in_sample(in_sample),
        .in_ready(echo_ready),.out_valid(echo_valid),.out_sample(echo_dry),
        .out_history(echo_history));
    audio_reverb #(.D0(D0),.D1(D1),.D2(D2),.D3(D3)) room(
        .clk(clk),.rst(rst),.in_valid(accept),.in_sample(in_sample),
        .in_ready(room_ready),.out_valid(room_valid),.out_sample(room_sample));
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            stage<=0;active_mode<=0;used_mode<=0;fade_level<=0;used_fade<=0;
            dry<=0;candidate<=0;tremolo_sample<=0;lfo_phase<=0;out_valid<=0;out_sample<=0;
            echo_level<=ECHO_WET;room_level<=ROOM_WET;depth_level<=256-TREMOLO_MIN;
            used_echo<=ECHO_WET;used_room<=ROOM_WET;
        end else begin
            out_valid<=0;
            if(accept)begin
                stage<=1;dry<=in_sample;used_mode<=active_mode;used_fade<=fade_level;
                tremolo_sample<=tremolo_product>>>8;lfo_phase<=lfo_phase+phase_step;
                used_echo<=echo_level;used_room<=room_level;
                echo_level<=slew(echo_level,echo_target);
                room_level<=slew(room_level,room_target);
                depth_level<=slew(depth_level,depth_target);
                // Reach exact dry before changing algorithms, then fade in.
                if(requested_mode!=active_mode)begin
                    if(fade_level!=0)fade_level<=fade_level-1'b1;
                    else active_mode<=requested_mode;
                end else if(enable)begin
                    if(fade_level<256)fade_level<=fade_level+1'b1;
                end else if(fade_level!=0)fade_level<=fade_level-1'b1;
            end else if(stage==1)stage<=2;
            else if(stage==2)begin
                case(used_mode)
                    1:candidate<=((dry_ext*(32'sd256-room_weight))+room_ext*room_weight)>>>8;
                    2:candidate<=tremolo_sample;
                    default:candidate<=((dry_ext*(32'sd256-echo_weight))+echo_ext*echo_weight)>>>8;
                endcase
                stage<=3;
            end else if(stage==3)begin
                if(result>32767)out_sample<=16'sh7fff;
                else if(result < -32768)out_sample<=16'sh8000;
                else out_sample<=result[15:0];
                out_valid<=1;stage<=0;
            end
        end
    end
    // synthesis translate_off
    initial if(ECHO_WET<0 || ECHO_WET>256 || ROOM_WET<0 || ROOM_WET>256 ||
        TREMOLO_MIN<0 || TREMOLO_MIN>256)$fatal(1,"Invalid effect amount");
    always @(posedge clk)if(!rst && stage==2 && (!echo_valid || !room_valid))
        $fatal(1,"Effect engine latency mismatch");
    // synthesis translate_on
endmodule
`timescale 1ns/1ps
// Four normalized parallel feedback combs: a small, deliberately simple room.
// The recurrence (input + delayed)/2 is bounded and rounds toward zero so
// negative quantization residues cannot circulate forever. No bulk RAM reset.
module audio_reverb #(
    parameter integer D0=1499,D1=1601,D2=1867,D3=2053)(
    input wire clk,rst,in_valid,input wire signed [15:0] in_sample,
    output wire in_ready,output reg out_valid,output reg signed [15:0] out_sample);
    reg busy;
    reg signed [15:0] dry;
    wire signed [15:0] taps[0:3];
    assign in_ready=!rst && !busy;
    wire accept=in_valid && in_ready;
    function automatic signed [15:0] half_zero(input signed [31:0] value);
        begin half_zero=value<0 ? -((-value)>>>1) : value>>>1;end
    endfunction
    for(genvar b=0;b<4;b=b+1)begin: combs
        localparam integer N=b==0?D0:b==1?D1:b==2?D2:D3;
        localparam integer AW=N>1?$clog2(N):1,FW=$clog2(N+1);
        reg signed [15:0] memory[0:N-1];
        reg signed [15:0] history;
        reg [AW-1:0] pointer;
        reg [FW-1:0] filled;
        reg history_valid;
        assign taps[b]=history_valid?history:16'sd0;
        wire signed [31:0] input_ext={{16{dry[15]}},dry};
        wire signed [31:0] history_ext={{16{taps[b][15]}},taps[b]};
        always @(posedge clk)if(!rst)begin
            if(accept)history<=memory[pointer];
            if(busy)memory[pointer]<=half_zero(input_ext+history_ext);
        end
        always @(posedge clk or posedge rst)begin
            if(rst)begin pointer<=0;filled<=0;history_valid<=0;end
            else begin
                if(accept)history_valid<=filled==N;
                if(busy)begin
                    pointer<=pointer==N-1?0:pointer+1'b1;
                    if(filled<N)filled<=filled+1'b1;
                end
            end
        end
    end
    wire signed [31:0] tap0={{16{taps[0][15]}},taps[0]};
    wire signed [31:0] tap1={{16{taps[1][15]}},taps[1]};
    wire signed [31:0] tap2={{16{taps[2][15]}},taps[2]};
    wire signed [31:0] tap3={{16{taps[3][15]}},taps[3]};
    wire signed [31:0] sum=(tap0+tap1)+(tap2+tap3);
    always @(posedge clk or posedge rst)begin
        if(rst)begin busy<=0;dry<=0;out_valid<=0;out_sample<=0;end
        else begin
            out_valid<=0;
            if(accept)begin dry<=in_sample;busy<=1;end
            else if(busy)begin out_sample<=sum>>>2;out_valid<=1;busy<=0;end
        end
    end
    // synthesis translate_off
    initial if(D0<1 || D1<1 || D2<1 || D3<1)$fatal(1,"Invalid room delays");
    // synthesis translate_on
endmodule
`timescale 1ns/1ps






































// File-backed event source. No melody, harmony, keyboard mapping or synthesis
// logic lives here. ROM is initialized at FPGA configuration, not runtime I/O.
module score_player #(
    parameter SCORE_FILE="src/scores/twinkle.hex",
    parameter integer SCORE_WORDS=512,ENABLE=1,BEAT_FRAMES=(48000/2),
    TAIL_FRAMES=((48000/5)+4))(
    input wire clk,rst,input_ready,frame_ce,note_ready,
    output wire note_valid,note_on,output wire [6:0] note_id,
    output wire [31:0] note_fcw,output wire [2:0] note_timbre,
    output wire busy,done,output reg error);
    localparam integer AW=SCORE_WORDS>1?$clog2(SCORE_WORDS):1;
    localparam integer TICK_FRAMES=BEAT_FRAMES/4;
    localparam integer MAX_FRAMES=TICK_FRAMES>TAIL_FRAMES?TICK_FRAMES:TAIL_FRAMES;
    localparam integer CW=MAX_FRAMES>0?$clog2(MAX_FRAMES+1):1;
    localparam [3:0] WAIT_START=0,FETCH=1,DECODE=2,SEND=3,WAIT_TIME=4,
        TAIL=5,DONE=6,NEXT=7,FAULT=8;
    reg [63:0] rom[0:SCORE_WORDS-1];
    reg [63:0] instruction;
    reg [AW-1:0] pc;
    reg [3:0] state;
    reg [31:0] ticks_left;
    reg [CW-1:0] elapsed;
    initial if(ENABLE)$readmemh(SCORE_FILE,rom);
    // Synchronous read, matching the project's waveform ROM convention.
    always @(posedge clk)if(ENABLE)instruction<=rom[pc];
    assign busy=ENABLE && state!=DONE;
    assign done=!ENABLE || state==DONE;
    assign note_valid=!rst && ENABLE && state==SEND;
    assign note_on=instruction[63:60]==4'h2;
    assign note_id=instruction[40:34];
    assign note_timbre={instruction[41],instruction[33:32]};
    assign note_fcw=instruction[31:0];
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=ENABLE?WAIT_START:DONE;pc<=0;elapsed<=0;ticks_left<=0;error<=0;
        end else case(state)
            WAIT_START:if(input_ready)state<=FETCH;
            FETCH:state<=DECODE;
            DECODE:case(instruction[63:60])
                4'h0:begin elapsed<=0;state<=TAIL_FRAMES==0?DONE:TAIL;end
                4'h1:begin
                    elapsed<=0;ticks_left<=instruction[31:0];
                    state<=instruction[31:0]==0?NEXT:WAIT_TIME;
                end
                4'h2,4'h3:state<=SEND;
                default:begin state<=FAULT;error<=1;end
            endcase
            SEND:if(note_ready)state<=NEXT;
            WAIT_TIME:if(frame_ce)begin
                if(elapsed==TICK_FRAMES-1)begin
                    elapsed<=0;
                    if(ticks_left==1)state<=NEXT;
                    else ticks_left<=ticks_left-1'b1;
                end else elapsed<=elapsed+1'b1;
            end
            NEXT:if(pc==SCORE_WORDS-1)begin state<=FAULT;error<=1;end
                 else begin pc<=pc+1'b1;state<=FETCH;end
            TAIL:if(frame_ce)begin
                if(elapsed==TAIL_FRAMES-1)begin state<=DONE;elapsed<=0;end
                else elapsed<=elapsed+1'b1;
            end
            DONE:state<=DONE;
            FAULT:state<=FAULT; // Invalid ROM never hands an unfinished score to the keyboard.
            default:begin state<=FAULT;error<=1;end
        endcase
    end
    // synthesis translate_off
    integer score_fd;
    initial begin
        if(SCORE_WORDS<1 || BEAT_FRAMES<4 || BEAT_FRAMES%4!=0 || TAIL_FRAMES<0)
            $fatal(1,"Invalid score configuration: beat frames must be a positive multiple of four");
        if(ENABLE)begin
            score_fd=$fopen(SCORE_FILE,"r");
            if(!score_fd)$fatal(1,"Cannot open score file: %s",SCORE_FILE);
            $fclose(score_fd);
        end
    end
    always @(posedge clk)if(!rst && ENABLE && state==DECODE)begin
        if((^instruction)===1'bx)$fatal(1,"Uninitialized score ROM at address %0d",pc);
        if((instruction[63:60]==2 || instruction[63:60]==3) &&
           (instruction[59:42]!=0 || {instruction[41],instruction[33:32]}>6 || instruction[31:0]==0))
            $fatal(1,"Invalid score event at address %0d",pc);
    end
    // synthesis translate_on
endmodule
`timescale 1ns/1ps
// Single feed-forward echo. Memory is never bulk-reset: fill count masks stale
// samples, including across resets. Read and write occupy different cycles.
module audio_delay #(parameter integer DELAY_SAMPLES=7200)(
    input wire clk,rst,enable,in_valid,input wire signed [15:0] in_sample,
    output wire in_ready,output reg out_valid,output reg signed [15:0] out_sample,output reg signed [15:0] out_history);
    localparam integer AW=DELAY_SAMPLES>1?$clog2(DELAY_SAMPLES):1;
    localparam integer FW=$clog2(DELAY_SAMPLES+1);
    reg signed [15:0] memory[0:DELAY_SAMPLES-1];
    reg [AW-1:0] pointer;
    reg [FW-1:0] filled;
    reg busy,history_valid;
    reg signed [15:0] dry,history;
    reg [6:0] wet_level,used_level;
    wire accept=in_valid && in_ready;
    assign in_ready=!rst && !busy;
    // 64/256 wet when enabled. Fade one step per accepted audio sample.
    // Weighted average bounds the output without increasing the dry peak.
    wire signed [31:0] dry_ext={{16{dry[15]}},dry};
    wire signed [31:0] delayed_ext=history_valid?{{16{history[15]}},history}:32'sd0;
    wire signed [31:0] level_ext=$signed({25'd0,used_level});
    wire signed [31:0] blend=(dry_ext <<< 8)+(delayed_ext-dry_ext)*level_ext;
    wire signed [31:0] result=blend >>> 8;
    always @(posedge clk)begin
        if(!rst)begin
            if(accept)history<=memory[pointer];
            if(busy)memory[pointer]<=dry;
        end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            pointer<=0;filled<=0;busy<=0;history_valid<=0;dry<=0;
            wet_level<=0;used_level<=0;out_valid<=0;out_sample<=0;out_history<=0;
        end else begin
            out_valid<=0;
            if(accept)begin
                dry<=in_sample;history_valid<=filled==DELAY_SAMPLES;
                used_level<=wet_level;busy<=1;
                case(enable)
                    1'b1:if(wet_level<64)wet_level<=wet_level+1'b1;
                    default:if(wet_level!=0)wet_level<=wet_level-1'b1;
                endcase
            end else if(busy)begin
                // Arithmetic is signed, with floor rounding for negatives.
                if(result>32767)out_sample<=16'sh7fff;
                else if(result < -32768)out_sample<=16'sh8000;
                else out_sample<=result[15:0];
                out_history<=delayed_ext[15:0];out_valid<=1;busy<=0;
                if(pointer==DELAY_SAMPLES-1)pointer<=0;else pointer<=pointer+1'b1;
                if(filled<DELAY_SAMPLES)filled<=filled+1'b1;
            end
        end
    end
    // synthesis translate_off
    initial if(DELAY_SAMPLES<1)$fatal(1,"Delay length must be positive");
    // synthesis translate_on
endmodule
`timescale 1ns/1ps






































// Independent active-low Dock S0..S3 buttons; no matrix-keyboard dependency.
module timbre_control #(parameter integer DEBOUNCE_CYCLES=(61440000/100),
    LONG_PRESS_CYCLES=(61440000*4/5))(
    input wire clk,rst,input wire [3:0] buttons_n,
    output reg [2:0] selected,output reg effects_enabled,output reg [1:0] effect_mode,
    input wire ui_action_valid,input wire [5:0] ui_action,input wire cfg_ready,
    output reg menu_mode,output reg cfg_valid,
    output reg [8:0] echo_wet,room_wet,tremolo_depth,
    output reg [3:0] cfg_tremolo_rate_hz,
    output reg [6:0] echo_percent,room_percent,depth_percent,
    output reg [3:0] tremolo_rate_hz,output reg [6:0] volume_percent);
    localparam integer CW=DEBOUNCE_CYCLES>1?$clog2(DEBOUNCE_CYCLES):1;
    (* async_reg="true" *) reg [3:0] sync_meta,sync_buttons;
    reg [3:0] stable_buttons,press_event,release_event;
    localparam integer HW=LONG_PRESS_CYCLES>1?$clog2(LONG_PRESS_CYCLES):1;
    reg [HW-1:0] hold_count;
    reg holding,long_fired;
    reg [HW-1:0] menu_hold;
    reg menu_holding,menu_fired;
// Shared actions and half-open rectangles for the British UI,800x480.
localparam [5:0] UI_SINE=0,UI_FLUTE=1,UI_REED=2,UI_ECHO=3,UI_ROOM=4,
 UI_TREMOLO=5,UI_FX=6,UI_MODE=7,UI_LESS=8,UI_MORE=9,
 UI_SLOWER=10,UI_FASTER=11,UI_DEFAULTS=12,UI_CELLO=13,UI_PIANO=14,
 UI_GUITAR=15,UI_VIBES=16,UI_PREV=17,UI_NEXT=18,UI_VOLUME_DOWN=19,UI_VOLUME_UP=20,
 UI_OPEN_MORE=21,UI_MORE_BACK=22,UI_SONG_PREV=23,UI_SONG_NEXT=24,UI_SONG_PLAY=25,
 UI_SONG_PAUSE=26,UI_SONG_RESUME=27,UI_SONG_STOP=28,UI_SONG_LOAD=29,UI_SONG_SAVE=30,
 UI_SONG_DELETE=31,UI_FLASH_INFO=32,UI_NONE=63;
function automatic ui_inside(input integer px,py,left,top,width,height);
 begin ui_inside=px>=left && px<left+width && py>=top && py<top+height;end
endfunction
function automatic integer timbre_x(input integer id);
 begin timbre_x=28+(id%2)*124;end
endfunction
function automatic integer timbre_y(input integer id);
 begin timbre_y=132+(id/2)*64;end
endfunction
function automatic [5:0] timbre_action(input integer id);
 begin case(id)
 0:timbre_action=UI_SINE;1:timbre_action=UI_FLUTE;2:timbre_action=UI_REED;
 3:timbre_action=UI_CELLO;4:timbre_action=UI_PIANO;5:timbre_action=UI_GUITAR;
 6:timbre_action=UI_VIBES;default:timbre_action=UI_NONE;endcase end
endfunction
function automatic [5:0] ui_hit(input integer px,py,input [1:0] fx,input menu);
 integer i;
 begin
  ui_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))ui_hit=UI_MODE;
  else if(menu)begin
   for(i=0;i<7;i=i+1)
    if(ui_inside(px,py,timbre_x(i),timbre_y(i),112,52))ui_hit=timbre_action(i);
   if(ui_inside(px,py,152,324,112,52))ui_hit=UI_FX;
   if(ui_inside(px,py,308,124,148,48))ui_hit=UI_ECHO;
   if(ui_inside(px,py,464,124,148,48))ui_hit=UI_ROOM;
   if(ui_inside(px,py,620,124,148,48))ui_hit=UI_TREMOLO;
   if(ui_inside(px,py,308,240,52,48))ui_hit=UI_LESS;
   if(ui_inside(px,py,716,240,52,48))ui_hit=UI_MORE;
   if(fx==2 && ui_inside(px,py,308,344,52,48))ui_hit=UI_SLOWER;
   if(fx==2 && ui_inside(px,py,716,344,52,48))ui_hit=UI_FASTER;
   if(ui_inside(px,py,24,420,44,44))ui_hit=UI_VOLUME_DOWN;
   if(ui_inside(px,py,272,420,44,44))ui_hit=UI_VOLUME_UP;
   if(ui_inside(px,py,664,420,116,44))ui_hit=UI_DEFAULTS;
   if(ui_inside(px,py,550,420,104,44))ui_hit=UI_OPEN_MORE;
  end
 end
endfunction
function automatic [5:0] more_hit(input integer px,py);
 begin
  more_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))more_hit=UI_MORE_BACK;
  if(ui_inside(px,py,24,200,160,40))more_hit=UI_SONG_PREV;
  if(ui_inside(px,py,204,200,160,40))more_hit=UI_SONG_NEXT;
  if(ui_inside(px,py,384,200,160,40))more_hit=UI_SONG_LOAD;
  if(ui_inside(px,py,564,200,160,40))more_hit=UI_SONG_PLAY;
  if(ui_inside(px,py,24,252,160,40))more_hit=UI_SONG_PAUSE;
  if(ui_inside(px,py,204,252,160,40))more_hit=UI_SONG_RESUME;
  if(ui_inside(px,py,384,252,160,40))more_hit=UI_SONG_STOP;
  if(ui_inside(px,py,24,304,160,40))more_hit=UI_SONG_SAVE;
  if(ui_inside(px,py,204,304,160,40))more_hit=UI_SONG_DELETE;
  if(ui_inside(px,py,384,304,160,40))more_hit=UI_FLASH_INFO;
 end
endfunction
    function automatic [8:0] amount(input [6:0] percent);
        begin case(percent)
            7'd0:amount=9'd0;
            7'd5:amount=9'd13;
            7'd10:amount=9'd26;
            7'd15:amount=9'd38;
            7'd20:amount=9'd51;
            7'd25:amount=9'd64;
            7'd30:amount=9'd77;
            7'd35:amount=9'd90;
            7'd40:amount=9'd102;
            7'd45:amount=9'd115;
            7'd50:amount=9'd128;
            7'd55:amount=9'd141;
            7'd60:amount=9'd154;
            7'd65:amount=9'd166;
            7'd70:amount=9'd179;
            7'd75:amount=9'd192;
            7'd80:amount=9'd205;
            7'd85:amount=9'd218;
            7'd90:amount=9'd230;
            7'd95:amount=9'd243;
            7'd100:amount=9'd256;
            default:amount=9'd64;
        endcase end
    endfunction
    // Hold a submitted tuple under backpressure; coalesce newer UI targets.
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            echo_wet<=64;room_wet<=64;tremolo_depth<=128;cfg_tremolo_rate_hz<=5;cfg_valid<=1;
        end else if(!cfg_valid || cfg_ready)begin
            if(echo_wet!=amount(echo_percent) || room_wet!=amount(room_percent) ||
                tremolo_depth!=amount(depth_percent) || cfg_tremolo_rate_hz!=tremolo_rate_hz)begin
                echo_wet<=amount(echo_percent);room_wet<=amount(room_percent);
                tremolo_depth<=amount(depth_percent);cfg_tremolo_rate_hz<=tremolo_rate_hz;cfg_valid<=1;
            end else cfg_valid<=0;
        end
    end
    wire menu_long=menu_holding && !stable_buttons[0] && !menu_fired && menu_hold==LONG_PRESS_CYCLES-1;
    wire effect_long=holding && !stable_buttons[3] && !long_fired && hold_count==LONG_PRESS_CYCLES-1;
    wire board_event=(|press_event) || (|release_event) || menu_long || effect_long;
    wire [6:0] current_percent=effect_mode==0?echo_percent:effect_mode==1?room_percent:depth_percent;
    always @(posedge clk or posedge rst)begin
        if(rst)begin sync_meta<=4'hf;sync_buttons<=4'hf;end
        else begin sync_meta<=buttons_n;sync_buttons<=sync_meta;end
    end
    for(genvar b=0;b<4;b=b+1)begin: debounce
        reg [CW-1:0] count;
        always @(posedge clk or posedge rst)begin
            if(rst)begin count<=0;stable_buttons[b]<=1'b1;press_event[b]<=0;release_event[b]<=0;end
            else begin
                press_event[b]<=0;release_event[b]<=0;
                if(sync_buttons[b]==stable_buttons[b])count<=0;
                else if(count==DEBOUNCE_CYCLES-1)begin
                    count<=0;stable_buttons[b]<=sync_buttons[b];
                    if(!sync_buttons[b])press_event[b]<=1;else release_event[b]<=1;
                end else count<=count+1'b1;
            end
        end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin selected<=0;effects_enabled<=0;effect_mode<=0;hold_count<=0;holding<=0;long_fired<=0;
            menu_mode<=0;menu_hold<=0;menu_holding<=0;menu_fired<=0;
            echo_percent<=25;room_percent<=25;depth_percent<=50;tremolo_rate_hz<=5;volume_percent<=100;
        end
        else begin
            // S0 is a release action so a long menu press preserves timbre.
            // Board events take priority over a simultaneous UI action.
            if(release_event[0] && menu_holding && !menu_fired)selected<=0;
            else if(!menu_mode && !press_event[0] && press_event[1])selected<=1;
            else if(!menu_mode && !press_event[0] && press_event[2])selected<=2;
            if(menu_mode && press_event[1])volume_percent<=volume_percent>=5 ? volume_percent-7'd5 : 7'd0;
            else if(menu_mode && press_event[2])volume_percent<=volume_percent<=95 ? volume_percent+7'd5 : 7'd100;
            if(press_event[0])begin menu_holding<=1;menu_fired<=0;menu_hold<=0;end
            else if(menu_holding)begin
                if(release_event[0])menu_holding<=0;
                else if(!stable_buttons[0] && !menu_fired)begin
                    if(menu_long)begin menu_mode<=!menu_mode;menu_fired<=1;end
                    else menu_hold<=menu_hold+1'b1;
                end
            end
            if(ui_action_valid && !board_event)begin
                case(ui_action)
                    UI_SINE:selected<=0;UI_FLUTE:selected<=1;UI_REED:selected<=2;
                    UI_CELLO:selected<=3;UI_PIANO:selected<=4;UI_GUITAR:selected<=5;UI_VIBES:selected<=6;
                    UI_PREV:if(selected==0)selected<=6;else selected<=selected-1'b1;
                    UI_NEXT:if(selected==6)selected<=0;else selected<=selected+1'b1;
                    UI_ECHO:begin effect_mode<=0;effects_enabled<=1;end
                    UI_ROOM:begin effect_mode<=1;effects_enabled<=1;end
                    UI_TREMOLO:begin effect_mode<=2;effects_enabled<=1;end
                    UI_VOLUME_DOWN:volume_percent<=volume_percent>=5 ? volume_percent-7'd5 : 7'd0;
                    UI_VOLUME_UP:volume_percent<=volume_percent<=95 ? volume_percent+7'd5 : 7'd100;
                    UI_FX:effects_enabled<=!effects_enabled;
                    UI_MODE:menu_mode<=!menu_mode;
                    UI_LESS,UI_MORE:begin
                        case(effect_mode)
                            0:echo_percent<=ui_action==UI_MORE?(current_percent<100?current_percent+7'd5:7'd100):(current_percent>0?current_percent-7'd5:7'd0);
                            1:room_percent<=ui_action==UI_MORE?(current_percent<100?current_percent+7'd5:7'd100):(current_percent>0?current_percent-7'd5:7'd0);
                            default:depth_percent<=ui_action==UI_MORE?(current_percent<100?current_percent+7'd5:7'd100):(current_percent>0?current_percent-7'd5:7'd0);
                        endcase
                        
                    end
                    UI_SLOWER:if(effect_mode==2)begin
                        if(tremolo_rate_hz>1)tremolo_rate_hz<=tremolo_rate_hz-1'b1;
                    end
                    UI_FASTER:if(effect_mode==2)begin
                        if(tremolo_rate_hz<10)tremolo_rate_hz<=tremolo_rate_hz+1'b1;
                    end
                    UI_DEFAULTS:begin
                        volume_percent<=100;
                        echo_percent<=25;room_percent<=25;depth_percent<=50;tremolo_rate_hz<=5;
                        effect_mode<=0;effects_enabled<=0;
                    end
                    default:begin end
                endcase
            end
            if(press_event[3])begin holding<=1;long_fired<=0;hold_count<=0;end
            else if(holding)begin
                if(release_event[3])begin
                    holding<=0;
                    if(!long_fired)effects_enabled<=!effects_enabled;
                end else if(!stable_buttons[3] && !long_fired)begin
                    if(hold_count==LONG_PRESS_CYCLES-1)begin
                        effect_mode<=effect_mode==2?0:effect_mode+1'b1;
                        effects_enabled<=1;long_fired<=1;
                    end else hold_count<=hold_count+1'b1;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(DEBOUNCE_CYCLES<1 || LONG_PRESS_CYCLES<1)$fatal(1,"Button debounce must be at least one cycle");
    // synthesis translate_on
endmodule
`timescale 1ns/1ps








































// 50 us per column, 200 us per scan. Fifteen scans qualify a change.













































// Four quarter-second steps without audio-ready enter status diagnostics.
// Zero disables the diagnostic display for isolated tests.


module keyboard_top #(
    parameter integer BT_ENABLE=1,BT_EN_ACTIVE_HIGH=1,FLASH_WRITES=1,
    parameter integer LCD_ENABLE=1,LCD_TEST_PATTERN=0,LCD_PCLK_INVERT=1,
    TOUCH_ENABLE=1,TOUCH_UI_ENABLE=1,TOUCH_RESET_CYCLES=1000000,TOUCH_STRAP_CYCLES=300000,
    TOUCH_BOOT_CYCLES=2500000,TOUCH_POLL_CYCLES=500000,TOUCH_I2C_HALF=250,
    parameter SCORE_FILE="src/scores/twinkle.hex",
    parameter integer SCORE_WORDS=512,SCORE_ENABLE=0,SCORE_BEAT_FRAMES=(48000/2),
    BUTTON_DEBOUNCE_CYCLES=(61440000/100),BUTTON_LONG_PRESS_CYCLES=(61440000*4/5),
    LED_STEP_CYCLES=(50000000/4),LED_DIAG_STEPS=4,
    LOCK_N=(50000000*2/1000),SLOT_CYCLES=(61440000/20000),
    SETTLE_CYCLES=(61440000/100000),DEBOUNCE_SCANS=15,
    MUTE=480,FADE=240,ATTACK=(48000/100),
    DECAY=(48000/10),SUSTAIN=17'd45875,RELEASE=(48000/5))(
    input wire bt_rx,output wire bt_tx,bt_en,
    input wire clk,rst,input wire [3:0] board_buttons_n,input wire [3:0] key_row,inout wire [3:0] key_col,
    output wire HP_BCK,HP_WS,HP_DIN,PA_EN,DBG_BCK,DBG_WS,DBG_DIN,DBG_PA_EN,
    output wire MAX_BCLK,MAX_LRCLK,MAX_DIN,MAX_SD_MODE,
    output wire [4:0] led_n,
    output wire lcd_clk,lcd_hs,lcd_vs,lcd_en,output wire [5:0] lcd_r,lcd_g,lcd_b,
    inout wire touch_scl,touch_sda,touch_int,touch_rst_n,
    output wire flash_cs_n,flash_sck,flash_mosi,input wire flash_miso,output wire flash_wp_n,flash_hold_n);
    wire effects_enabled;
    wire synth_pa_enable;
    reg [1:0] max_clock_frames;
    wire visual_sample_valid;wire signed [15:0] visual_sample;wire [15:0] visual_notes;
    wire [1:0] effect_mode;
    wire [2:0] selected_timbre,event_timbre,key_timbre,score_timbre;
    wire key_valid,key_on,score_valid,score_on,score_busy,score_done,score_error;
    wire [6:0] key_id,score_id;
    wire [31:0] key_fcw,score_fcw;
    wire mid_clk,audio_clk,lock1,lock2,pll1_reset,pll2_reset,audio_reset;
    wire [3:0] col_enable,last_key;
    wire [15:0] keys;
    wire [16:0] envelope_level;
    wire underrun,ghost,gate,key_gate,frame_ce,input_ready,note_ready,note_valid,note_on;
    wire [6:0] note_id;
    wire [31:0] note_fcw;
    wire [32-1:0] voice_active,voice_held;
    wire menu_mode,inhibit_notes,cfg_valid,cfg_ready,cfg_applied;
    wire [8:0] echo_wet,room_wet,tremolo_depth;
    wire [6:0] echo_percent,room_percent,depth_percent,volume_percent;
    wire [3:0] tremolo_rate_hz,cfg_rate_hz;
    wire matrix_action_valid,touch_action_valid;
    wire [5:0] matrix_action,touch_action;
    wire ui_action_valid=matrix_action_valid || touch_action_valid;
    wire [5:0] ui_action=matrix_action_valid?matrix_action:touch_action;
    wire more_open,delete_confirm,more_command_valid,more_command_ready,more_info;
    wire [3:0] more_command;
    wire [79:0] service_status,service_audio;wire service_audio_valid,service_update;
    ui_more_actions more_controls(audio_clk,audio_reset,menu_mode,ui_action_valid,ui_action,
        more_open,delete_confirm,more_command_valid,more_command_ready,more_command,more_info);
    wire touch_ready,touch_error,touch_down,touch_report;
    wire [3:0] touch_count;
    wire [15:0] touch_x,touch_y,touch_size,touch_resolution_x,touch_resolution_y;
    wire [7:0] touch_track_id;wire [31:0] touch_product_id;
    wire [38:0] touch_status={touch_ready,touch_error,touch_down,touch_count,touch_x,touch_y};
    wire [70:0] touch_audio;
    wire touch_audio_valid,touch_update;
    wire bt_inhibit,bt_valid,bt_ready,bt_flush,bt_note_on;
    wire [6:0] bt_note_id,bt_velocity,bt_pitch;
    wire [2:0] bt_timbre;
    wire [31:0] bt_fcw;
    reg score_cancelled;
    reg bt_flush_d;
    always @(posedge audio_clk or posedge audio_reset)begin
        if(audio_reset)bt_flush_d<=0;else bt_flush_d<=bt_flush;
    end
    wire local_score_busy=score_busy && !score_cancelled;
    wire take_bt=bt_inhibit || bt_valid || bt_flush;
    assign bt_en=BT_EN_ACTIVE_HIGH ? 1'b1 : 1'b0;
    always @(posedge audio_clk or posedge audio_reset)begin
        if(audio_reset)score_cancelled<=0;
        else if(bt_inhibit || bt_valid)score_cancelled<=1;
    end
    if(BT_ENABLE)begin: bluetooth_on
        wire ev_valid,ev_ready;wire [1:0] kind;
        wire [6:0] ident,pitch,velocity;
        wire source_valid,source_ready,source_inhibit,source_reset;
        wire [1:0] source_kind;wire [6:0] source_id,source_pitch,source_velocity;
        wire song_valid,upload_active;wire [1:0] play_state;wire [15:0] total_notes;
        wire [31:0] song_duration,song_crc;
        wire local_valid,local_ready,local_done;wire [1:0] local_command;wire [7:0] local_error;
        wire storage_lock,storage_ready,storage_write,storage_invalidate,storage_import,storage_done;
        wire [11:0] storage_address;wire [63:0] storage_wdata,storage_rdata;
        wire [15:0] storage_count;wire [31:0] storage_crc;wire [7:0] storage_error;
        wire extension_valid,extension_ready,extension_response_valid,extension_response_ready;
        wire [7:0] extension_command;wire [8:0] extension_length;wire [63:0] extension_payload;
        wire [4:0] extension_response_length;wire [159:0] extension_response;
        wire action_valid,action_ready;wire [3:0] action;
        wire channel_reset=pll1_reset || audio_reset;
        reset_sync bt_reset(clk,channel_reset,source_reset);
        (* syn_async_reg=1, async_reg="true" *) reg inhibit_meta,inhibit_sync;
        always @(posedge audio_clk or posedge audio_reset)begin
            if(audio_reset)begin inhibit_meta<=0;inhibit_sync<=0;end
            else begin inhibit_meta<=source_inhibit;inhibit_sync<=inhibit_meta;end
        end
        assign bt_inhibit=inhibit_sync;
        bluetooth_score_link #(.CLOCK_HZ(50000000),.MAX_NOTES(4096),.MAX_VOICES(16),.LIBRARY_EXTENSION(1)) link(
            .clk(clk),.rst(source_reset),.uart_rx_pin(bt_rx),.uart_tx_pin(bt_tx),
            .event_valid(source_valid),.event_ready(source_ready),.event_kind(source_kind),.event_id(source_id),
            .event_pitch(source_pitch),.event_velocity(source_velocity),.manual_inhibit(source_inhibit),
            .song_valid(song_valid),.upload_active(upload_active),.play_state(play_state),.total_notes(total_notes),.song_duration(song_duration),.song_crc(song_crc),
            .local_valid(local_valid),.local_ready(local_ready),.local_command(local_command),.local_done(local_done),.local_error(local_error),
            .storage_lock(storage_lock),.storage_ready(storage_ready),.storage_write(storage_write),.storage_invalidate(storage_invalidate),
            .storage_address(storage_address),.storage_wdata(storage_wdata),.storage_rdata(storage_rdata),
            .storage_import(storage_import),.storage_count(storage_count),.storage_crc(storage_crc),.storage_done(storage_done),.storage_error(storage_error),
            .extension_valid(extension_valid),.extension_ready(extension_ready),.extension_command(extension_command),.extension_length(extension_length),.extension_payload(extension_payload),
            .extension_response_valid(extension_response_valid),.extension_response_ready(extension_response_ready),.extension_response_length(extension_response_length),.extension_response(extension_response));
        bt_event_cdc #(.WIDTH(4)) local_actions(audio_clk,clk,channel_reset,more_command_valid,more_command_ready,more_command,action_valid,action_ready,action);
        score_services #(.FLASH_WRITES(FLASH_WRITES)) services(.clk(clk),.rst(source_reset),.action_valid(action_valid),.action_ready(action_ready),.action(action),.status(service_status),
            .song_valid(song_valid),.upload_active(upload_active),.play_state(play_state),.total_notes(total_notes),.song_duration(song_duration),.song_crc(song_crc),
            .local_valid(local_valid),.local_ready(local_ready),.local_command(local_command),.local_done(local_done),.local_error(local_error),
            .storage_lock(storage_lock),.storage_ready(storage_ready),.storage_write(storage_write),.storage_invalidate(storage_invalidate),
            .storage_address(storage_address),.storage_wdata(storage_wdata),.storage_rdata(storage_rdata),
            .storage_import(storage_import),.storage_count(storage_count),.storage_crc(storage_crc),.storage_done(storage_done),.storage_error(storage_error),
            .extension_valid(extension_valid),.extension_ready(extension_ready),.extension_command(extension_command),.extension_length(extension_length),.extension_payload(extension_payload),
            .extension_response_valid(extension_response_valid),.extension_response_ready(extension_response_ready),.extension_response_length(extension_response_length),.extension_response(extension_response),
            .flash_cs_n(flash_cs_n),.flash_sck(flash_sck),.flash_mosi(flash_mosi),.flash_miso(flash_miso),.flash_wp_n(flash_wp_n),.flash_hold_n(flash_hold_n));
        // Automatic IDs 0..15; manual keyboard IDs 60..75 remain separate.
        bt_event_cdc #(.WIDTH(23)) events(clk,audio_clk,channel_reset,
            source_valid,source_ready,{source_kind,source_id,source_pitch,source_velocity},
            ev_valid,ev_ready,{kind,ident,pitch,velocity});
        bluetooth_audio_bridge bridge(.clk(audio_clk),.rst(audio_reset),.frame_ce(frame_ce),
            .event_valid(ev_valid),.event_ready(ev_ready),.event_kind(kind),
            .event_id(ident),.event_pitch(pitch),.event_velocity(velocity),.inhibit(bt_inhibit),
            .note_valid(bt_valid),.note_ready(bt_ready),.note_on(bt_note_on),
            .note_id(bt_note_id),.note_fcw(bt_fcw),.note_velocity(bt_velocity),.flush(bt_flush),
            .selected_timbre(selected_timbre),.note_timbre(bt_timbre),.note_pitch(bt_pitch),.audio_ready(input_ready));
    end else begin: bluetooth_off
        assign bt_tx=1;assign bt_inhibit=0;assign bt_valid=0;assign bt_flush=0;
        assign bt_note_on=0;assign bt_note_id=0;assign bt_fcw=0;assign bt_velocity=127;assign bt_pitch=0;assign bt_timbre=0;
        assign service_status=0;assign more_command_ready=1;
        assign flash_cs_n=1;assign flash_sck=0;assign flash_mosi=0;assign flash_wp_n=1;assign flash_hold_n=1;
    end
    rgb_status_cdc #(.WIDTH(80)) service_bridge(clk,audio_clk,pll1_reset || audio_reset,
        service_status,service_audio,service_audio_valid,service_update);
    assign bt_ready=note_ready && take_bt && !bt_flush;
    // Start the external amplifier only after I2S clocks have crossed two
    // frame boundaries. The existing production mute interval then supplies
    // more than 7.5 ms of digital silence before audio is admitted.
    always @(posedge audio_clk or posedge audio_reset)begin
        if(audio_reset)max_clock_frames<=0;
        else if(frame_ce && max_clock_frames!=2)max_clock_frames<=max_clock_frames+1'b1;
    end
    assign MAX_SD_MODE=!audio_reset && max_clock_frames==2;
    // Retired onboard PT8211/PA and scope-mirror pads remain parked low.
    assign HP_BCK=0;assign HP_WS=0;assign HP_DIN=0;assign PA_EN=0;
    assign DBG_BCK=0;assign DBG_WS=0;assign DBG_DIN=0;assign DBG_PA_EN=0;
    if(TOUCH_ENABLE)begin: touch_on
        gt9110_touch #(.RESET_CYCLES(TOUCH_RESET_CYCLES),.STRAP_CYCLES(TOUCH_STRAP_CYCLES),
            .BOOT_CYCLES(TOUCH_BOOT_CYCLES),.POLL_CYCLES(TOUCH_POLL_CYCLES),
            .I2C_HALF_CYCLES(TOUCH_I2C_HALF)) touch_reader(
            .clk(clk),.rst(pll1_reset),.touch_scl(touch_scl),.touch_sda(touch_sda),
            .touch_int(touch_int),.touch_rst_n(touch_rst_n),.ready(touch_ready),
            .error(touch_error),.touch_down(touch_down),.report_pulse(touch_report),
            .touch_count(touch_count),.touch_x(touch_x),.touch_y(touch_y),.touch_size(touch_size),
            .track_id(touch_track_id),.product_id(touch_product_id),
            .resolution_x(touch_resolution_x),.resolution_y(touch_resolution_y));
        rgb_status_cdc #(.WIDTH(71)) touch_bridge(clk,audio_clk,pll1_reset || audio_reset,
            {touch_resolution_x,touch_resolution_y,touch_status},touch_audio,touch_audio_valid,touch_update);
    end else begin: touch_off
        assign touch_scl=1'bz;assign touch_sda=1'bz;assign touch_int=1'bz;assign touch_rst_n=1'bz;
        assign touch_ready=0;assign touch_error=0;assign touch_down=0;assign touch_report=0;
        assign touch_count=0;assign touch_x=0;assign touch_y=0;assign touch_size=0;
        assign touch_track_id=0;assign touch_product_id=0;assign touch_resolution_x=0;assign touch_resolution_y=0;
        assign touch_audio=0;assign touch_audio_valid=0;assign touch_update=0;
    end
    ui_touch_actions touch_commands(.clk(audio_clk),.rst(audio_reset),
        .enabled(TOUCH_ENABLE!=0 && TOUCH_UI_ENABLE!=0),.snapshot_valid(touch_audio_valid),
        .ready(touch_audio[38]),.error(touch_audio[37]),.down(touch_audio[36]),.count(touch_audio[35:32]),
        .x(touch_audio[31:16]),.y(touch_audio[15:0]),.resolution_x(touch_audio[70:55]),
        .resolution_y(touch_audio[54:39]),.effect_mode(effect_mode),.menu_mode(menu_mode),
        .action_valid(touch_action_valid),.action(touch_action),.more_mode(more_open));
    ui_keypad_router #(.RELEASE_CYCLES(SLOT_CYCLES*4*(DEBOUNCE_SCANS+1))) menu_keys(.clk(audio_clk),.rst(audio_reset),.menu_mode(menu_mode || take_bt),
        .ghost(ghost),.keys(keys),.inhibit_notes(inhibit_notes),
        .action_valid(matrix_action_valid),.action(matrix_action),.more_mode(more_open));
    if(LCD_ENABLE)begin: lcd_on
        rgb_display #(.VOICES(32),.TEST_PATTERN(LCD_TEST_PATTERN),
            .PCLK_INVERT(LCD_PCLK_INVERT)) display_driver(
            .ref_clk(clk),.pll_reset(pll1_reset),.audio_clk(audio_clk),.audio_reset(audio_reset),
            .voice_active(voice_active),.voice_held(voice_held),.selected_timbre(selected_timbre),
            .visual_sample_valid(visual_sample_valid),.visual_sample(visual_sample),.visual_notes(visual_notes),
            .score_busy(local_score_busy || bt_inhibit),.audio_ready(input_ready),.score_error(score_error),
            .underrun(underrun),.ghost(ghost),.lcd_clk(lcd_clk),.lcd_hs(lcd_hs),
            .lcd_vs(lcd_vs),.lcd_en(lcd_en),.lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b),
            .menu_mode(menu_mode),.effects_enabled(effects_enabled),.effect_mode(effect_mode),
            .echo_percent(echo_percent),.room_percent(room_percent),.depth_percent(depth_percent),
            .volume_percent(volume_percent),.tremolo_rate_hz(tremolo_rate_hz),.touch_enabled(TOUCH_ENABLE!=0),
            .touch_ui_enabled(TOUCH_UI_ENABLE!=0 && touch_audio_valid && touch_audio[70:55]==800 && touch_audio[54:39]==480),.touch_ready_status(touch_audio[38]),.touch_error_status(touch_audio[37]),
            .more_status({more_open,delete_confirm,more_info,service_audio[78:0]}));
    end else begin: lcd_off
        assign lcd_clk=0;assign lcd_hs=1;assign lcd_vs=1;assign lcd_en=0;
        assign lcd_r=0;assign lcd_g=0;assign lcd_b=0;
    end
    // A source owns the event interface through its final release/tail. The
    // keyboard is admitted only after the one-shot score has fully completed.
    assign note_valid=bt_flush ? 1'b0 : take_bt ? bt_valid : local_score_busy ? score_valid : key_valid;
    assign note_on=take_bt?bt_note_on:local_score_busy?score_on:key_on;
    assign note_id=take_bt?bt_note_id:local_score_busy?score_id:key_id;
    assign note_fcw=take_bt?bt_fcw:local_score_busy?score_fcw:key_fcw;
    assign event_timbre=take_bt?bt_timbre:local_score_busy?score_timbre:key_timbre;
    score_player #(.SCORE_FILE(SCORE_FILE),.SCORE_WORDS(SCORE_WORDS),.ENABLE(SCORE_ENABLE),
        .BEAT_FRAMES(SCORE_BEAT_FRAMES),.TAIL_FRAMES(RELEASE+4))
        score(.clk(audio_clk),.rst(audio_reset),.input_ready(input_ready),.frame_ce(frame_ce),
        .note_ready(score_cancelled || (note_ready && local_score_busy && !take_bt)),.note_valid(score_valid),.note_on(score_on),
        .note_id(score_id),.note_fcw(score_fcw),.note_timbre(score_timbre),.busy(score_busy),.done(score_done),.error(score_error));
    timbre_control #(.DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES),.LONG_PRESS_CYCLES(BUTTON_LONG_PRESS_CYCLES)) timbre_buttons(
        .clk(audio_clk),.rst(audio_reset),.buttons_n(board_buttons_n),
        .selected(selected_timbre),.effects_enabled(effects_enabled),.effect_mode(effect_mode),
        .ui_action_valid(ui_action_valid),.ui_action(ui_action),.cfg_ready(cfg_ready),
        .menu_mode(menu_mode),.cfg_valid(cfg_valid),.cfg_tremolo_rate_hz(cfg_rate_hz),.echo_wet(echo_wet),.room_wet(room_wet),
        .tremolo_depth(tremolo_depth),.echo_percent(echo_percent),.room_percent(room_percent),
        .depth_percent(depth_percent),.tremolo_rate_hz(tremolo_rate_hz),.volume_percent(volume_percent));
    wire [5:0] diagnostic_leds;
    assign led_n={diagnostic_leds[5],diagnostic_leds[3:0]};
    run_leds #(.STEP_CYCLES(LED_STEP_CYCLES),.DIAG_STEPS(LED_DIAG_STEPS)) status_leds(
        .clk(clk),.audio_ready_async(!audio_reset),.key_active_async(gate),
        .pll1_lock_async(lock1),.pll2_lock_async(lock2),.reset_active_async(rst),.led_n(diagnostic_leds));
    pll_pair clocks(clk,pll1_reset,pll2_reset,mid_clk,audio_clk,lock1,lock2);
    clock_reset #(.LOCK_N(LOCK_N)) reset_control(clk,rst,lock1,lock2,audio_clk,
        pll1_reset,pll2_reset,audio_reset);
    for(genvar c=0;c<4;c=c+1)begin: columns
        assign key_col[c]=col_enable[c]?1'b0:1'bz;
    end
    keyboard_core #(.SLOT_CYCLES(SLOT_CYCLES),.SETTLE_CYCLES(SETTLE_CYCLES),
        .DEBOUNCE_SCANS(DEBOUNCE_SCANS)) core(
        .clk(audio_clk),.rst(audio_reset),.input_ready(input_ready && !local_score_busy && !take_bt),.note_ready(note_ready && !local_score_busy && !take_bt),
        .key_row(key_row),.col_enable(col_enable),.keys(keys),.ghost(ghost),
        .note_valid(key_valid),.note_on(key_on),.note_id(key_id),.note_fcw(key_fcw),
        .gate(key_gate),.last_key(last_key),
        .selected_timbre(selected_timbre),.note_timbre(key_timbre),.inhibit_notes(inhibit_notes));
    synth_core #(.MUTE(MUTE),.FADE(FADE),.ATTACK(ATTACK),.DECAY(DECAY),
        .SUSTAIN(SUSTAIN),.RELEASE(RELEASE)) sound(
        .clk(audio_clk),.rst(audio_reset),.note_valid(note_valid),.note_on(note_on),
        .note_pitch(take_bt ? bt_pitch : note_id),.volume_percent(volume_percent),.flush(bt_flush),.velocity_valid(take_bt),.note_velocity(bt_velocity),
        .note_id(note_id),.note_fcw(note_fcw),.note_timbre(event_timbre),.effects_enable(effects_enabled),.effect_mode(effect_mode),
        .effect_cfg_valid(cfg_valid || bt_flush_d),.effect_echo_wet(echo_wet),.effect_room_wet(room_wet),
        .effect_tremolo_depth(tremolo_depth),.effect_tremolo_rate_hz(cfg_rate_hz),
        .effect_cfg_ready(cfg_ready),.effect_cfg_applied(cfg_applied),
        .bck(MAX_BCLK),.ws(MAX_LRCLK),.din(MAX_DIN),.pa_enable(synth_pa_enable),.underrun(underrun),
        .frame_ce(frame_ce),.note_ready(note_ready),.input_ready(input_ready),
        .gate(gate),.voice_active(voice_active),.voice_held(voice_held),.envelope_level(envelope_level),
        .visual_sample_valid(visual_sample_valid),.visual_sample(visual_sample),.visual_notes(visual_notes));
endmodule


`timescale 1ns/1ps






































module adsr_envelope #(
    parameter integer ATTACK=(48000/100),DECAY=(48000/10),
    SUSTAIN=17'd45875,RELEASE=(48000/5))(
    input wire clk,rst,sample_ce,note_on,note_off,
    output reg [16:0] level,output wire active,input wire restart,
    input wire seed_valid,input wire [16:0] seed_level);
    localparam integer MAX_AD=ATTACK>DECAY?ATTACK:DECAY;
    localparam integer MAX_N=MAX_AD>RELEASE?MAX_AD:RELEASE;
    localparam integer CW=MAX_N>0?$clog2(MAX_N+1):1;
    localparam integer A_DEN=ATTACK>0?ATTACK:1,D_DEN=DECAY>0?DECAY:1,R_DEN=RELEASE>0?RELEASE:1;
    localparam [2:0] IDLE=0,A=1,D=2,S=3,R=4;
    reg [2:0] state;
    reg [CW-1:0] remaining,length,remainder,error;
    reg [16:0] base;
    wire [CW:0] error_sum={1'b0,error}+{1'b0,remainder};
    wire carry=error_sum>={1'b0,length};
    wire [17:0] delta={1'b0,base}+(carry?18'd1:18'd0);
    wire [16:0] start_level=restart ? 17'd0 : (seed_valid===1'b1 ? seed_level : level);
    assign active=state!=IDLE;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            state<=IDLE;level<=0;remaining<=0;length<=1;remainder<=0;error<=0;base<=0;
        end else if(sample_ce)begin
            if(note_off && !restart)begin
                if(RELEASE==0 || level==0)begin state<=IDLE;level<=0;end
                else begin
                    state<=R;remaining<=RELEASE;length<=RELEASE;
                    base<=level/R_DEN;remainder<=level%R_DEN;error<=0;
                end
            end else if(note_on)begin
                // Same-note retrigger preserves level; a newly owned voice starts at zero.
                if(restart)level<=0;
                else if(seed_valid===1'b1)level<=seed_level;
                if(ATTACK>0)begin
                    state<=A;remaining<=ATTACK;length<=ATTACK;
                    base<=(17'd65536-start_level)/A_DEN;
                    remainder<=(17'd65536-start_level)%A_DEN;error<=0;
                end else if(DECAY>0)begin
                    state<=D;level<=65536;remaining<=DECAY;length<=DECAY;
                    base<=(65536-SUSTAIN)/D_DEN;remainder<=(65536-SUSTAIN)%D_DEN;error<=0;
                end else begin state<=S;level<=SUSTAIN;end
            end else if(restart)begin
                state<=IDLE;level<=0;remaining<=0;error<=0;
            end else if(state==A || state==D || state==R)begin
                if(remaining==1)begin
                    error<=0;
                    if(state==A)begin
                        if(DECAY>0)begin
                            level<=65536;state<=D;remaining<=DECAY;length<=DECAY;
                            base<=(65536-SUSTAIN)/D_DEN;remainder<=(65536-SUSTAIN)%D_DEN;
                        end else begin level<=SUSTAIN;state<=S;end
                    end else if(state==D)begin level<=SUSTAIN;state<=S;end
                    else begin level<=0;state<=IDLE;end
                end else begin
                    remaining<=remaining-1'b1;
                    error<=carry?error_sum-length:error_sum;
                    if(state==A)level<=level+delta;else level<=level-delta;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(ATTACK<0 || DECAY<0 || RELEASE<0 || SUSTAIN<0 || SUSTAIN>65536)
        $fatal(1,"Invalid ADSR parameters");
    // synthesis translate_on
endmodule
`timescale 1ns/1ps






































module audio_timing #(parameter integer HALF_CYCLES=(61440000/(48000*16*2*2)))(
    input wire clk, rst, output reg bck, output wire rise_ce, fall_ce,frame_ce,
    output reg [4:0] bit_index);
    localparam integer CW=$clog2(HALF_CYCLES+1);
    reg [CW-1:0] count;
    reg frame_boundary;
    assign frame_ce=!rst && frame_boundary;
    assign fall_ce=!rst && count==HALF_CYCLES-1 && bck;
    assign rise_ce=!rst && count==HALF_CYCLES-1 && !bck;
    // Predict the same boundary one clock ahead so the high-fanout envelope
    // CE is a register output, not counter/decode logic in every ADSR path.
    always @(posedge clk or posedge rst) begin
        if(rst) begin count<=0; bck<=1; bit_index<=0;frame_boundary<=HALF_CYCLES==1;end
        else begin
        if(HALF_CYCLES==1)frame_boundary<=!bck && bit_index==31;
        else frame_boundary<=count==HALF_CYCLES-2 && bck && bit_index==0;
        if(count==HALF_CYCLES-1) begin
            count<=0; bck<=~bck;
            if(!bck) bit_index<=bit_index+1'b1;
        end else count<=count+1'b1;
        end
    end
endmodule
`timescale 1ns/1ps






































module clock_reset #(parameter integer LOCK_N=(50000000*2/1000))(
    input wire ref_clk,external_reset,lock1,lock2,
    input wire audio_clk,output wire pll1_reset,pll2_reset,audio_reset);
    reg [5:0] por_count=0;
    wire por=~por_count[5];
    always @(posedge ref_clk) if(por) por_count<=por_count+1'b1;
    wire ref_reset;
    wire good1,good2;
    reset_sync ref_sync(ref_clk,external_reset|por,ref_reset);
    assign pll1_reset=ref_reset;
    lock_guard #(.STABLE_CYCLES(LOCK_N)) g1(ref_clk,ref_reset,lock1,good1);
    assign pll2_reset=ref_reset|!good1;
    lock_guard #(.STABLE_CYCLES(LOCK_N)) g2(ref_clk,pll2_reset,lock2,good2);
    reset_sync audio_sync(audio_clk,
        ref_reset|!good1|!good2|!lock1|!lock2,audio_reset);
endmodule
`timescale 1ns/1ps






































// Independent phase contexts share one synchronous wavetable read port.
module dds_sine #(parameter integer VOICES=1,INDEX_W=VOICES>1?$clog2(VOICES):1)(
    input wire clk,rst,sample_ce,input wire [32-1:0] fcw,
    output wire signed [16-1:0] sample,output reg valid,
    output wire [VOICES*32-1:0] phase,input wire restart,
    input wire [INDEX_W-1:0] voice_index,input wire [2:0] timbre);
    reg [32-1:0] phases[0:VOICES-1];
    wire [32-1:0] sample_phase=restart?{32{1'b0}}:phases[voice_index];
    for(genvar v=0;v<VOICES;v=v+1)begin: context_outputs
        assign phase[v*32+:32]=phases[v];
    end
    wire signed [15:0] sine_sample,flute_sample,reed_sample;
    wire signed [15:0] cello_sample,piano_sample,guitar_sample,vibes_sample;
    reg [2:0] sampled_timbre;
    // An omitted timbre port retains legacy sine behaviour in older adapters.
    always @(posedge clk or posedge rst)
        if(rst)sampled_timbre<=0;
        else if(sample_ce)case(timbre)
            3'd1:sampled_timbre<=1;
            3'd2:sampled_timbre<=2;
                3'd3:sampled_timbre<=3;3'd4:sampled_timbre<=4;3'd5:sampled_timbre<=5;3'd6:sampled_timbre<=6;
            default:sampled_timbre<=0;
        endcase
    assign sample=sampled_timbre==1?flute_sample:
                  sampled_timbre==2 ? reed_sample :
                  sampled_timbre==3 ? cello_sample : sampled_timbre==4 ? piano_sample :
                  sampled_timbre==5 ? guitar_sample : sampled_timbre==6 ? vibes_sample : sine_sample;
    sine_rom #(.ROM_FILE("src/rom/flute4096.hex")) flute_rom(
        .clk(clk),.ce(sample_ce && !rst),
        .addr(sample_phase[32-1 -: 12]),.q(flute_sample));
    sine_rom #(.ROM_FILE("src/rom/reed4096.hex")) reed_rom(
        .clk(clk),.ce(sample_ce && !rst),
        .addr(sample_phase[32-1 -: 12]),.q(reed_sample));
    sine_rom #(.ROM_FILE("src/rom/cello4096.hex")) cello_rom(clk,sample_ce && !rst,sample_phase[31:20],cello_sample);
    sine_rom #(.ROM_FILE("src/rom/piano4096.hex")) piano_rom(clk,sample_ce && !rst,sample_phase[31:20],piano_sample);
    sine_rom #(.ROM_FILE("src/rom/guitar4096.hex")) guitar_rom(clk,sample_ce && !rst,sample_phase[31:20],guitar_sample);
    sine_rom #(.ROM_FILE("src/rom/vibraphone4096.hex")) vibes_rom(clk,sample_ce && !rst,sample_phase[31:20],vibes_sample);
    sine_rom rom(.clk(clk),.ce(sample_ce && !rst),
        .addr(sample_phase[32-1 -: 12]),.q(sine_sample));
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            valid<=0;
            for(integer v=0;v<VOICES;v=v+1)phases[v]<=0;
        end else begin
            valid<=sample_ce;
            if(sample_ce)phases[voice_index]<=sample_phase+fcw;
        end
    end
    // synthesis translate_off
    always @(posedge clk)if(!rst && sample_ce && voice_index>=VOICES)$fatal(1,"DDS context out of range");
    initial if(VOICES<1 || VOICES>32)$fatal(1,"Invalid DDS voice count");
    // synthesis translate_on
endmodule

`timescale 1ns/1ps
module frame_buffer(input wire clk,rst,frame_ce,sample_valid,
    output wire sample_ready, input wire signed [15:0] sample_l,sample_r,
    output wire [15:0] frame_l,frame_r,output reg underrun);
    reg [15:0] pending_l,pending_r,active_l,active_r;
    reg pending_valid,seen_frame;
    assign sample_ready=!pending_valid || frame_ce;
    // At the boundary consume the OLD pending pair; a simultaneous handshake
    // fills the next frame. The serializer sees this pair before the NBA update.
    assign frame_l=frame_ce ? (pending_valid?pending_l:16'b0) : active_l;
    assign frame_r=frame_ce ? (pending_valid?pending_r:16'b0) : active_r;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            pending_l<=0;pending_r<=0;active_l<=0;active_r<=0;
            pending_valid<=0;seen_frame<=0;underrun<=0;
        end else begin
            if(frame_ce) begin
                active_l<=pending_valid?pending_l:16'b0;
                active_r<=pending_valid?pending_r:16'b0;
                pending_valid<=0;
                if(seen_frame && !pending_valid) underrun<=1;
                seen_frame<=1;
            end
            if(sample_valid && sample_ready) begin
                pending_l<=sample_l;pending_r<=sample_r;pending_valid<=1;
            end
        end
    end
endmodule
`timescale 1ns/1ps








// Replaceable matrix adapter. Voice allocation and all audio stay in synth_core.
module keyboard_core #(
    parameter integer SLOT_CYCLES=(61440000/20000),SETTLE_CYCLES=(61440000/100000),
    DEBOUNCE_SCANS=15)(
    input wire clk,rst,input_ready,note_ready,input wire [3:0] key_row,
    output wire [3:0] col_enable,output wire [15:0] keys,output wire ghost,
    output wire note_valid,note_on,output wire [6:0] note_id,
    output wire [31:0] note_fcw,output wire gate,output wire [3:0] last_key,
    input wire [2:0] selected_timbre,output wire [2:0] note_timbre,input wire inhibit_notes);
    wire scan_valid;
    wire [15:0] note_keys=(inhibit_notes===1'b1) ? 16'd0 : keys;
    matrix_keypad #(.SLOT_CYCLES(SLOT_CYCLES),.SETTLE_CYCLES(SETTLE_CYCLES),.DEBOUNCE_SCANS(DEBOUNCE_SCANS))
        keyboard(clk,rst,key_row,col_enable,keys,scan_valid,ghost);
    key_note_events control(clk,rst,input_ready,note_keys,note_ready,
        note_valid,note_on,note_id,note_fcw,gate,last_key,selected_timbre,note_timbre);
endmodule

`timescale 1ns/1ps






































// Generic note-event synthesis; physical keyboard logic stays in its adapter.
module synth_core #(
    parameter integer VOICES=32,MUTE=480,FADE=240,
    ATTACK=(48000/100),DECAY=(48000/10),
    SUSTAIN=17'd45875,RELEASE=(48000/5),
    DELAY_SAMPLES=7200,ROOM_D0=1499,ROOM_D1=1601,ROOM_D2=1867,ROOM_D3=2053)(
    input wire clk,rst,note_valid,note_on,input wire [6:0] note_id,input wire [31:0] note_fcw,
    output wire note_ready,input_ready,bck,ws,din,pa_enable,underrun,frame_ce,gate,
    output wire [VOICES-1:0] voice_active,voice_held,output reg [16:0] envelope_level,input wire [2:0] note_timbre,input wire effects_enable,input wire [1:0] effect_mode,
    input wire effect_cfg_valid,input wire [8:0] effect_echo_wet,effect_room_wet,effect_tremolo_depth,
    input wire [3:0] effect_tremolo_rate_hz,output wire effect_cfg_ready,effect_cfg_applied,
    output wire visual_sample_valid,output wire signed [15:0] visual_sample,
    output reg [15:0] visual_notes,
    input wire flush,input wire velocity_valid,input wire [6:0] note_velocity,
    input wire [6:0] volume_percent,input wire [6:0] note_pitch);
    wire engine_reset=rst || (flush===1'b1);
    // Bounded automatic context table; manual/legacy MIDI identities use unity.
    reg [8:0] velocities[0:15];
    reg [6:0] automatic_pitch[0:15];
    reg [8:0] velocity_scale;
    function automatic [8:0] velocity_gain(input [6:0] value);
    begin case(value)
        7'd0:velocity_gain=9'd0;
        7'd1:velocity_gain=9'd2;
        7'd2:velocity_gain=9'd4;
        7'd3:velocity_gain=9'd6;
        7'd4:velocity_gain=9'd8;
        7'd5:velocity_gain=9'd10;
        7'd6:velocity_gain=9'd12;
        7'd7:velocity_gain=9'd14;
        7'd8:velocity_gain=9'd16;
        7'd9:velocity_gain=9'd18;
        7'd10:velocity_gain=9'd20;
        7'd11:velocity_gain=9'd22;
        7'd12:velocity_gain=9'd24;
        7'd13:velocity_gain=9'd26;
        7'd14:velocity_gain=9'd28;
        7'd15:velocity_gain=9'd30;
        7'd16:velocity_gain=9'd32;
        7'd17:velocity_gain=9'd34;
        7'd18:velocity_gain=9'd36;
        7'd19:velocity_gain=9'd38;
        7'd20:velocity_gain=9'd40;
        7'd21:velocity_gain=9'd42;
        7'd22:velocity_gain=9'd44;
        7'd23:velocity_gain=9'd46;
        7'd24:velocity_gain=9'd48;
        7'd25:velocity_gain=9'd50;
        7'd26:velocity_gain=9'd52;
        7'd27:velocity_gain=9'd54;
        7'd28:velocity_gain=9'd56;
        7'd29:velocity_gain=9'd58;
        7'd30:velocity_gain=9'd60;
        7'd31:velocity_gain=9'd62;
        7'd32:velocity_gain=9'd65;
        7'd33:velocity_gain=9'd67;
        7'd34:velocity_gain=9'd69;
        7'd35:velocity_gain=9'd71;
        7'd36:velocity_gain=9'd73;
        7'd37:velocity_gain=9'd75;
        7'd38:velocity_gain=9'd77;
        7'd39:velocity_gain=9'd79;
        7'd40:velocity_gain=9'd81;
        7'd41:velocity_gain=9'd83;
        7'd42:velocity_gain=9'd85;
        7'd43:velocity_gain=9'd87;
        7'd44:velocity_gain=9'd89;
        7'd45:velocity_gain=9'd91;
        7'd46:velocity_gain=9'd93;
        7'd47:velocity_gain=9'd95;
        7'd48:velocity_gain=9'd97;
        7'd49:velocity_gain=9'd99;
        7'd50:velocity_gain=9'd101;
        7'd51:velocity_gain=9'd103;
        7'd52:velocity_gain=9'd105;
        7'd53:velocity_gain=9'd107;
        7'd54:velocity_gain=9'd109;
        7'd55:velocity_gain=9'd111;
        7'd56:velocity_gain=9'd113;
        7'd57:velocity_gain=9'd115;
        7'd58:velocity_gain=9'd117;
        7'd59:velocity_gain=9'd119;
        7'd60:velocity_gain=9'd121;
        7'd61:velocity_gain=9'd123;
        7'd62:velocity_gain=9'd125;
        7'd63:velocity_gain=9'd127;
        7'd64:velocity_gain=9'd129;
        7'd65:velocity_gain=9'd131;
        7'd66:velocity_gain=9'd133;
        7'd67:velocity_gain=9'd135;
        7'd68:velocity_gain=9'd137;
        7'd69:velocity_gain=9'd139;
        7'd70:velocity_gain=9'd141;
        7'd71:velocity_gain=9'd143;
        7'd72:velocity_gain=9'd145;
        7'd73:velocity_gain=9'd147;
        7'd74:velocity_gain=9'd149;
        7'd75:velocity_gain=9'd151;
        7'd76:velocity_gain=9'd153;
        7'd77:velocity_gain=9'd155;
        7'd78:velocity_gain=9'd157;
        7'd79:velocity_gain=9'd159;
        7'd80:velocity_gain=9'd161;
        7'd81:velocity_gain=9'd163;
        7'd82:velocity_gain=9'd165;
        7'd83:velocity_gain=9'd167;
        7'd84:velocity_gain=9'd169;
        7'd85:velocity_gain=9'd171;
        7'd86:velocity_gain=9'd173;
        7'd87:velocity_gain=9'd175;
        7'd88:velocity_gain=9'd177;
        7'd89:velocity_gain=9'd179;
        7'd90:velocity_gain=9'd181;
        7'd91:velocity_gain=9'd183;
        7'd92:velocity_gain=9'd185;
        7'd93:velocity_gain=9'd187;
        7'd94:velocity_gain=9'd189;
        7'd95:velocity_gain=9'd191;
        7'd96:velocity_gain=9'd194;
        7'd97:velocity_gain=9'd196;
        7'd98:velocity_gain=9'd198;
        7'd99:velocity_gain=9'd200;
        7'd100:velocity_gain=9'd202;
        7'd101:velocity_gain=9'd204;
        7'd102:velocity_gain=9'd206;
        7'd103:velocity_gain=9'd208;
        7'd104:velocity_gain=9'd210;
        7'd105:velocity_gain=9'd212;
        7'd106:velocity_gain=9'd214;
        7'd107:velocity_gain=9'd216;
        7'd108:velocity_gain=9'd218;
        7'd109:velocity_gain=9'd220;
        7'd110:velocity_gain=9'd222;
        7'd111:velocity_gain=9'd224;
        7'd112:velocity_gain=9'd226;
        7'd113:velocity_gain=9'd228;
        7'd114:velocity_gain=9'd230;
        7'd115:velocity_gain=9'd232;
        7'd116:velocity_gain=9'd234;
        7'd117:velocity_gain=9'd236;
        7'd118:velocity_gain=9'd238;
        7'd119:velocity_gain=9'd240;
        7'd120:velocity_gain=9'd242;
        7'd121:velocity_gain=9'd244;
        7'd122:velocity_gain=9'd246;
        7'd123:velocity_gain=9'd248;
        7'd124:velocity_gain=9'd250;
        7'd125:velocity_gain=9'd252;
        7'd126:velocity_gain=9'd254;
        7'd127:velocity_gain=9'd256;
        default:velocity_gain=256;
    endcase end endfunction
    always @(posedge clk or posedge engine_reset)begin
        if(engine_reset)begin
            for(integer a=0;a<16;a=a+1)begin velocities[a]<=256;automatic_pitch[a]<=a;end
        end else if(note_valid && note_ready && note_on && note_id<16)begin
            for(integer a=0;a<16;a=a+1)if(note_id==a)begin
                velocities[a]<=velocity_valid===1'b1 ? velocity_gain(note_velocity) : 9'd256;
                automatic_pitch[a]<=velocity_valid===1'b1 ? note_pitch : note_id;
            end
        end
    end
    localparam integer INDEX_W=VOICES>1?$clog2(VOICES):1;
    localparam integer RENDER_BUDGET=32+16*VOICES;
    localparam integer CYCLE_W=$clog2(RENDER_BUDGET+1);
    wire rise_ce,fall_ce;
    wire [4:0] bit_index;
    wire [16:0] startup_level;
    wire [VOICES-1:0] voice_start,voice_stop,voice_restart;
    wire [VOICES*32-1:0] voice_fcw;
    wire [VOICES*7-1:0] voice_ids;
    wire [16:0] voice_level[0:VOICES-1];
    wire [VOICES*3-1:0] voice_timbres;
    reg [VOICES*3-1:0] frame_timbres;
    reg render_busy;
    reg [CYCLE_W-1:0] render_cycle;
    reg [VOICES*32-1:0] frame_fcw;
    reg [VOICES-1:0] frame_restart;
    wire in_slots=render_busy && render_cycle>=16 && render_cycle<16+16*VOICES;
    wire [INDEX_W-1:0] selected_voice=in_slots?((render_cycle >> 4)-1'b1):{INDEX_W{1'b0}};
    wire dds_ce=in_slots && render_cycle[3:0]==0;
    wire signed [15:0] raw_sample;
    wire raw_valid,gain_valid,mix_valid,ready;
    wire effect_ready,effect_valid;
    wire signed [15:0] effect_sample;
    wire [VOICES*32-1:0] phase;
    reg [33:0] level_product;
    wire [25:0] scaled_level=level_product[32:16]*velocity_scale;
    reg [16:0] combined_level;
    reg gain_request,first_sample,last_sample;
    reg [INDEX_W-1:0] sample_voice;
    wire signed [24-1:0] gain_sample;
    wire signed [15:0] mix_sample;
    wire [15:0] frame_l,frame_r;
    reg [15:0] note_scan;
    // Metadata read, automatic lookup, then bitmap update occupy separate clocks.
    // Avoid a render-counter -> context mux -> dynamic shift -> bitmap path.
    reg [6:0] scanning_id,scanning_pitch;
    reg scanning_held,scanning_first,scanning_last;
    wire [15:0] note_bit=(scanning_held && scanning_pitch>=60 && scanning_pitch<76) ? (16'b1 << (scanning_pitch-7'd60)) : 16'd0;
    always @(posedge clk or posedge engine_reset)begin
        if(engine_reset)begin note_scan<=0;visual_notes<=0;scanning_id<=0;scanning_pitch<=0;scanning_held<=0;scanning_first<=0;scanning_last<=0;end
        else begin
            if(dds_ce)begin
                scanning_id<=voice_ids[selected_voice*7+:7];scanning_held<=voice_held[selected_voice];
                scanning_first<=selected_voice==0;scanning_last<=selected_voice==VOICES-1;
            end
            if(in_slots && render_cycle[3:0]==1)scanning_pitch<=scanning_id<16 ? automatic_pitch[scanning_id[3:0]] : scanning_id;
            if(in_slots && render_cycle[3:0]==2)begin
                if(scanning_first)note_scan<=note_bit;else note_scan<=note_scan | note_bit;
                if(scanning_last)visual_notes<=scanning_first ? note_bit : note_scan | note_bit;
            end
        end
    end
    wire output_valid;wire signed [15:0] output_sample;
    // Flush drops buffered audio but must not reset the user's volume ramp.
    master_volume volume_control(clk,rst,effect_valid,effect_sample,volume_percent,output_valid,output_sample);
    assign visual_sample_valid=output_valid;
    assign visual_sample=output_sample;
    audio_timing timing(clk,rst,bck,rise_ce,fall_ce,frame_ce,bit_index);
    startup_envelope #(.MUTE(MUTE),.FADE(FADE)) startup(clk,rst,frame_ce,input_ready,startup_level);
    assign pa_enable=input_ready;
    assign gate=|voice_held;
    // Freeze ownership while rendering; external producers retain valid/data.
    voice_allocator #(.VOICES(VOICES)) allocator(
        .clk(clk),.rst(engine_reset),.enabled(input_ready && !render_busy),.frame_ce(frame_ce),
        .note_valid(note_valid),.note_on(note_on),.note_id(note_id),.note_fcw(note_fcw),
        .voice_active(voice_active),.note_ready(note_ready),.voice_start(voice_start),
        .voice_stop(voice_stop),.voice_restart(voice_restart),.voice_held(voice_held),
        .voice_fcw(voice_fcw),.voice_ids(voice_ids),
        .note_timbre(note_timbre),.voice_timbres(voice_timbres));
    for(genvar v=0;v<VOICES;v=v+1)begin: voices
        instrument_envelope #(.ATTACK(ATTACK),.DECAY(DECAY),.SUSTAIN(SUSTAIN),.RELEASE(RELEASE)) envelope(
            .clk(clk),.rst(engine_reset),.sample_ce(frame_ce),.note_on(voice_start[v]),.note_off(voice_stop[v]),
            .level(voice_level[v]),.active(voice_active[v]),.restart(voice_restart[v]),.timbre(voice_timbres[v*3+:3]));
    end
    dds_sine #(.VOICES(VOICES)) dds(.clk(clk),.rst(engine_reset),.sample_ce(dds_ce),
        .fcw(frame_fcw[selected_voice*32+:32]),.sample(raw_sample),.valid(raw_valid),
        .phase(phase),.restart(frame_restart[selected_voice]),.voice_index(selected_voice),.timbre(frame_timbres[selected_voice*3+:3]));
    always @(posedge clk or posedge engine_reset)begin
        if(engine_reset)begin
            render_busy<=0;render_cycle<=0;frame_fcw<=0;frame_restart<=0;frame_timbres<=0;
            level_product<=0;combined_level<=0;gain_request<=0;
            first_sample<=0;last_sample<=0;sample_voice<=0;velocity_scale<=256;
        end else begin
            gain_request<=in_slots && render_cycle[3:0]==3;
            if(in_slots && render_cycle[3:0]==2)combined_level<=scaled_level[24:8];
            if(frame_ce)begin
                render_busy<=1;render_cycle<=0;
                frame_fcw<=voice_fcw;frame_restart<=voice_restart;frame_timbres<=voice_timbres;
            end else if(render_busy)begin
                if(render_cycle==RENDER_BUDGET-2)render_busy<=0;
                else render_cycle<=render_cycle+1'b1;
            end
            if(dds_ce)begin
                level_product<=voice_level[selected_voice]*startup_level;
                sample_voice<=selected_voice;
                first_sample<=selected_voice==0;
                last_sample<=selected_voice==VOICES-1;
            end
            if(in_slots && render_cycle[3:0]==1)velocity_scale<=scanning_id<16 ? velocities[scanning_id[3:0]] : 9'd256;
        end
    end
    tone_gain #(.OUTPUT_W(24)) gain(clk,engine_reset,gain_request,raw_sample,combined_level,gain_valid,gain_sample);
    voice_mixer mixer(clk,engine_reset,gain_valid,gain_sample,first_sample,last_sample,mix_valid,mix_sample);
    always @* begin
        envelope_level=0;
        for(integer v=0;v<VOICES;v=v+1)
            if(voice_level[v]>envelope_level)envelope_level=voice_level[v];
    end
    audio_effects #(.DELAY_SAMPLES(DELAY_SAMPLES),.D0(ROOM_D0),.D1(ROOM_D1),.D2(ROOM_D2),.D3(ROOM_D3)) effect(
        .clk(clk),.rst(engine_reset),.enable(effects_enable),.mode(effect_mode),.in_valid(mix_valid),.in_sample(mix_sample),
        .in_ready(effect_ready),.out_valid(effect_valid),.out_sample(effect_sample),
        .cfg_valid(effect_cfg_valid),.cfg_echo_wet(effect_echo_wet),.cfg_room_wet(effect_room_wet),
        .cfg_tremolo_depth(effect_tremolo_depth),.cfg_tremolo_rate_hz(effect_tremolo_rate_hz),
        .cfg_ready(effect_cfg_ready),.cfg_applied(effect_cfg_applied));
    frame_buffer buffer(clk,engine_reset,frame_ce,output_valid,ready,output_sample,output_sample,frame_l,frame_r,underrun);
    i2s_tx tx(clk,rst,fall_ce,bit_index,frame_l,frame_r,ws,din);
    // synthesis translate_off
    initial if(VOICES<1 || VOICES>32 || RENDER_BUDGET>=((61440000/(48000*16*2*2))*2*16*2))$fatal(1,"Invalid render budget");
    always @(posedge clk)if(!rst)begin
        if(frame_ce && render_busy)$fatal(1,"Frame renderer missed deadline");
        if(mix_valid && !effect_ready)$fatal(1,"Effect rejected render result");
        if(output_valid && !ready)$fatal(1,"Frame buffer rejected effect result");
    end
    // synthesis translate_on
endmodule


`timescale 1ns/1ps
// Audio-domain adapter only. Delete requires two released activations.
module ui_more_actions(
 input wire clk,rst,menu_mode,action_valid,input wire [5:0] action,
 output reg open,delete_confirm,output reg command_valid,input wire command_ready,output reg [3:0] command,output reg info);
// Shared actions and half-open rectangles for the British UI,800x480.
localparam [5:0] UI_SINE=0,UI_FLUTE=1,UI_REED=2,UI_ECHO=3,UI_ROOM=4,
 UI_TREMOLO=5,UI_FX=6,UI_MODE=7,UI_LESS=8,UI_MORE=9,
 UI_SLOWER=10,UI_FASTER=11,UI_DEFAULTS=12,UI_CELLO=13,UI_PIANO=14,
 UI_GUITAR=15,UI_VIBES=16,UI_PREV=17,UI_NEXT=18,UI_VOLUME_DOWN=19,UI_VOLUME_UP=20,
 UI_OPEN_MORE=21,UI_MORE_BACK=22,UI_SONG_PREV=23,UI_SONG_NEXT=24,UI_SONG_PLAY=25,
 UI_SONG_PAUSE=26,UI_SONG_RESUME=27,UI_SONG_STOP=28,UI_SONG_LOAD=29,UI_SONG_SAVE=30,
 UI_SONG_DELETE=31,UI_FLASH_INFO=32,UI_NONE=63;
function automatic ui_inside(input integer px,py,left,top,width,height);
 begin ui_inside=px>=left && px<left+width && py>=top && py<top+height;end
endfunction
function automatic integer timbre_x(input integer id);
 begin timbre_x=28+(id%2)*124;end
endfunction
function automatic integer timbre_y(input integer id);
 begin timbre_y=132+(id/2)*64;end
endfunction
function automatic [5:0] timbre_action(input integer id);
 begin case(id)
 0:timbre_action=UI_SINE;1:timbre_action=UI_FLUTE;2:timbre_action=UI_REED;
 3:timbre_action=UI_CELLO;4:timbre_action=UI_PIANO;5:timbre_action=UI_GUITAR;
 6:timbre_action=UI_VIBES;default:timbre_action=UI_NONE;endcase end
endfunction
function automatic [5:0] ui_hit(input integer px,py,input [1:0] fx,input menu);
 integer i;
 begin
  ui_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))ui_hit=UI_MODE;
  else if(menu)begin
   for(i=0;i<7;i=i+1)
    if(ui_inside(px,py,timbre_x(i),timbre_y(i),112,52))ui_hit=timbre_action(i);
   if(ui_inside(px,py,152,324,112,52))ui_hit=UI_FX;
   if(ui_inside(px,py,308,124,148,48))ui_hit=UI_ECHO;
   if(ui_inside(px,py,464,124,148,48))ui_hit=UI_ROOM;
   if(ui_inside(px,py,620,124,148,48))ui_hit=UI_TREMOLO;
   if(ui_inside(px,py,308,240,52,48))ui_hit=UI_LESS;
   if(ui_inside(px,py,716,240,52,48))ui_hit=UI_MORE;
   if(fx==2 && ui_inside(px,py,308,344,52,48))ui_hit=UI_SLOWER;
   if(fx==2 && ui_inside(px,py,716,344,52,48))ui_hit=UI_FASTER;
   if(ui_inside(px,py,24,420,44,44))ui_hit=UI_VOLUME_DOWN;
   if(ui_inside(px,py,272,420,44,44))ui_hit=UI_VOLUME_UP;
   if(ui_inside(px,py,664,420,116,44))ui_hit=UI_DEFAULTS;
   if(ui_inside(px,py,550,420,104,44))ui_hit=UI_OPEN_MORE;
  end
 end
endfunction
function automatic [5:0] more_hit(input integer px,py);
 begin
  more_hit=UI_NONE;
  if(ui_inside(px,py,648,16,132,48))more_hit=UI_MORE_BACK;
  if(ui_inside(px,py,24,200,160,40))more_hit=UI_SONG_PREV;
  if(ui_inside(px,py,204,200,160,40))more_hit=UI_SONG_NEXT;
  if(ui_inside(px,py,384,200,160,40))more_hit=UI_SONG_LOAD;
  if(ui_inside(px,py,564,200,160,40))more_hit=UI_SONG_PLAY;
  if(ui_inside(px,py,24,252,160,40))more_hit=UI_SONG_PAUSE;
  if(ui_inside(px,py,204,252,160,40))more_hit=UI_SONG_RESUME;
  if(ui_inside(px,py,384,252,160,40))more_hit=UI_SONG_STOP;
  if(ui_inside(px,py,24,304,160,40))more_hit=UI_SONG_SAVE;
  if(ui_inside(px,py,204,304,160,40))more_hit=UI_SONG_DELETE;
  if(ui_inside(px,py,384,304,160,40))more_hit=UI_FLASH_INFO;
 end
endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin open<=0;delete_confirm<=0;command_valid<=0;command<=0;info<=0;end
  else begin
   if(command_valid && command_ready)command_valid<=0;
   if(!menu_mode)begin open<=0;delete_confirm<=0;info<=0;end
   else if(action_valid)begin
    if(action==UI_OPEN_MORE)begin open<=1;delete_confirm<=0;info<=0;end
    else if(open && action==UI_MORE_BACK)begin open<=0;delete_confirm<=0;end
    else if(open && !command_valid)begin
     if(action>=UI_SONG_PREV && action<=UI_SONG_SAVE)begin command<=action-UI_SONG_PREV;command_valid<=1;delete_confirm<=0;end
     else if(action==UI_SONG_DELETE)begin
      if(delete_confirm)begin command<=8;command_valid<=1;delete_confirm<=0;end else delete_confirm<=1;
     end else begin delete_confirm<=0;if(action==UI_FLASH_INFO)info<=!info;end
    end
   end
  end
 end
endmodule
`timescale 1ns/1ps
// Reference-domain composition only: independent control, protocol, library,
// and physical Flash driver. No UI rendering or audio synthesis here.
module score_services #(parameter integer FLASH_WRITES=1)(
 input wire clk,rst,action_valid,output wire action_ready,input wire [3:0] action,
 output wire [79:0] status,
 input wire song_valid,upload_active,input wire [1:0] play_state,
 input wire [15:0] total_notes,input wire [31:0] song_duration,song_crc,
 output wire local_valid,input wire local_ready,output wire [1:0] local_command,input wire local_done,input wire [7:0] local_error,
 output wire storage_lock,input wire storage_ready,output wire storage_write,storage_invalidate,
 output wire [11:0] storage_address,output wire [63:0] storage_wdata,input wire [63:0] storage_rdata,
 output wire storage_import,output wire [15:0] storage_count,output wire [31:0] storage_crc,input wire storage_done,input wire [7:0] storage_error,
 input wire extension_valid,output wire extension_ready,input wire [7:0] extension_command,input wire [8:0] extension_length,input wire [63:0] extension_payload,
 output wire extension_response_valid,input wire extension_response_ready,output wire [4:0] extension_response_length,output wire [159:0] extension_response,
 output wire flash_cs_n,flash_sck,flash_mosi,input wire flash_miso,output wire flash_wp_n,flash_hold_n);
 wire library_ready,library_busy,library_init,library_done,loaded_valid;
 wire [4:0] selected,loaded_index;wire [31:0] entries;
 wire [15:0] job_id;wire [1:0] job_state;wire [7:0] library_error,control_error;
 wire control_busy,control_done,local_library_valid,remote_library_valid;
 wire [1:0] local_library_command,remote_library_command;wire [4:0] local_library_index,remote_library_index;
 wire [55:0] remote_name;wire [4:0] remote_lookup;
 wire [159:0] lookup_data;
 wire remote_pending=extension_valid || !extension_ready || extension_response_valid;
 wire [4:0] lookup_index=remote_pending?remote_lookup:selected;
 reg [4:0] previous_lookup,selected_meta_index;reg [159:0] selected_meta;
 wire fr,fv,fd,fi,fs,bw;wire [1:0] fo;wire [23:0] fa,jedec;wire [8:0] fl;
 wire [7:0] fe,bi,bd,ri,rd,s1,s2,s3;
 wire writable=FLASH_WRITES!=0 && fs && s1[7:2]==0 && !s1[0] && !s2[6] && !s2[0] && !s2[7] && !s3[2];
 assign action_ready=!control_busy && !remote_pending;
 assign status={3'd0,job_id,job_state,fs,jedec,(selected_meta_index==selected?selected_meta[31:16]:16'd0),play_state,
  (control_error!=0?control_error:library_error),library_init,library_busy,entries[selected],selected};
 always @(posedge clk or posedge rst)begin
  if(rst)begin previous_lookup<=0;selected_meta_index<=0;selected_meta<=0;end
  else begin previous_lookup<=lookup_index;if(lookup_index==selected && previous_lookup==selected)begin selected_meta<=lookup_data;selected_meta_index<=selected;end end
 end
 local_score_control control(.clk(clk),.rst(rst),.action_valid(action_valid && action_ready),.action(action),.entries(entries),
 .upload_active(upload_active),.library_busy(library_busy || remote_pending),.song_valid(song_valid),.loaded_valid(loaded_valid),.loaded_index(loaded_index),
 .selected(selected),.busy(control_busy),.done(control_done),.error(control_error),
 .player_valid(local_valid),.player_ready(local_ready),.player_command(local_command),.player_done(local_done),.player_error(local_error),
 .library_valid(local_library_valid),.library_ready(library_ready && !remote_pending),.library_command(local_library_command),.library_index(local_library_index),
 .library_done(library_done),.library_error(library_error));
 score_library_protocol protocol(.clk(clk),.rst(rst),.request_valid(extension_valid),.request_ready(extension_ready),
 .command(extension_command),.length(extension_length),.payload(extension_payload),.response_valid(extension_response_valid),.response_ready(extension_response_ready),
 .response_length(extension_response_length),.response(extension_response),.initialized(library_init),.supported(fs),.writable(writable),
 .library_busy(library_busy),.local_busy(control_busy),.storage_ready(storage_ready),.jedec_id(jedec),.status1(s1),.status2(s2),.status3(s3),.library_error(library_error),
 .job_id(job_id),.job_state(job_state),.ram_crc(song_crc),.library_valid(remote_library_valid),.library_ready(library_ready),.library_command(remote_library_command),
 .library_index(remote_library_index),.library_name(remote_name),.lookup_index(remote_lookup),.lookup_data(lookup_data));
 flash_song_library song_library(.clk(clk),.rst(rst),.request_valid(remote_library_valid || (local_library_valid && !remote_pending)),.request_ready(library_ready),
 .command(remote_library_valid?remote_library_command:local_library_command),.song_index(remote_library_valid?remote_library_index:local_library_index),
 .song_name(remote_library_valid?remote_name:56'd0),.busy(library_busy),.initialized(library_init),.job_id(job_id),.job_state(job_state),.error(library_error),.done(library_done),
 .entries(entries),.loaded_valid(loaded_valid),.loaded_index(loaded_index),.lookup_index(lookup_index),.lookup_data(lookup_data),
 .ram_valid(song_valid),.ram_count(total_notes),.ram_duration(song_duration),.ram_crc(song_crc),
 .storage_lock(storage_lock),.storage_ready(storage_ready),.storage_write(storage_write),.storage_invalidate(storage_invalidate),.storage_address(storage_address),
 .storage_wdata(storage_wdata),.storage_rdata(storage_rdata),.storage_import(storage_import),.storage_count(storage_count),.storage_crc(storage_crc),.storage_done(storage_done),.storage_error(storage_error),
 .upload_active(upload_active),.flash_initialized(fi),.flash_supported(fs),.flash_ready(fr),.flash_valid(fv),.flash_op(fo),.flash_address(fa),.flash_length(fl),.flash_done(fd),.flash_error(fe),
 .buffer_write(bw),.buffer_index(bi),.buffer_wdata(bd),.read_index(ri),.read_data(rd));
 spi_nor_flash flash(.clk(clk),.rst(rst),.request_valid(fv),.request_ready(fr),.operation(fo),.address(fa),.length(fl),.writes_enabled(FLASH_WRITES!=0),
 .done(fd),.error(fe),.initialized(fi),.supported(fs),.jedec_id(jedec),.status1(s1),.status2(s2),.status3(s3),
 .buffer_write(bw),.buffer_index(bi),.buffer_wdata(bd),.read_index(ri),.read_data(rd),
 .cs_n(flash_cs_n),.sck(flash_sck),.mosi(flash_mosi),.miso(flash_miso),.wp_n(flash_wp_n),.hold_n(flash_hold_n));
endmodule
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
`timescale 1ns/1ps
// Fixed-slot copy-on-write song library. All interfaces are in the ref domain.
// Two 4KiB directory sectors, 33 x64KiB payload slots for32 entries +1 spare.
module flash_song_library #(parameter integer MAX_NOTES=4096,AW=(MAX_NOTES>1?$clog2(MAX_NOTES):1))(
 input wire clk,rst,request_valid,output wire request_ready,input wire [1:0] command,
 input wire [4:0] song_index,input wire [55:0] song_name,
 output wire busy,output reg initialized,output reg [15:0] job_id,
 output reg [1:0] job_state,output reg [7:0] error,output reg done,
 output reg [31:0] entries,output reg loaded_valid,output reg [4:0] loaded_index,
 input wire [4:0] lookup_index,output reg [159:0] lookup_data,
 input wire ram_valid,input wire [15:0] ram_count,input wire [31:0] ram_duration,ram_crc,
 output wire storage_lock,input wire storage_ready,output reg storage_write,storage_invalidate,
 output reg [AW-1:0] storage_address,output reg [63:0] storage_wdata,input wire [63:0] storage_rdata,
 output wire storage_import,output reg [15:0] storage_count,output reg [31:0] storage_crc,
 input wire storage_done,input wire [7:0] storage_error,input wire upload_active,
 input wire flash_initialized,flash_supported,flash_ready,
 output wire flash_valid,output reg [1:0] flash_op,output reg [23:0] flash_address,output reg [8:0] flash_length,
 input wire flash_done,input wire [7:0] flash_error,
 output reg buffer_write,output reg [7:0] buffer_index,buffer_wdata,
 output reg [7:0] read_index,input wire [7:0] read_data);
 localparam integer DIR_BYTES=1056;
 localparam [6:0] BOOT=0,READY=1,JOB_START=2,LOOKUP_WAIT=3,LOOKUP_LATCH=4,
 ALLOC_START=5,ALLOC_READ=6,ALLOC_WAIT=7,ALLOC_SLOT=8,ERASE_DATA=9,ERASE_NEXT=10,
 SAVE_WORD=11,SAVE_WAIT=12,SAVE_LATCH=13,SAVE_BYTE=14,PROGRAM_PAGE=15,READ_PAYLOAD=16,
 PAYLOAD_FETCH=17,PAYLOAD_WAIT=18,PAYLOAD_BYTE=19,PAYLOAD_NEXT=20,LOAD_WRITE=21,IMPORT=22,
 BUILD_HEADER=23,BUILD_META=24,BUILD_META_WAIT=25,BUILD_ENTRY=26,BUILD_CRC=27,DIR_ERASE=28,
 DIR_FILL=29,DIR_FILL_WAIT=30,DIR_FILL_BYTE=31,DIR_PROGRAM=32,DIR_WRITE_NEXT=33,
 DIR_READ=34,DIR_FETCH=35,DIR_WAIT=36,DIR_BYTE=37,DIR_NEXT=38,DIR_CHECK=39,
 APPLY=40,BOOT_NEXT=41,MARK_FILL=42,MARK_PROGRAM=43,MARK_READ=44,MARK_FETCH=45,MARK_WAIT=46,MARK_CHECK=47,
 FINISH=48,IO_SEND=49,IO_WAIT=50;
 reg [6:0] state,io_return;reg [1:0] operation;reg [4:0] target;
 reg [159:0] catalog[0:31],candidates[0:31],catalog_read,meta_shift,new_meta;
 reg [7:0] directory[0:DIR_BYTES-1],directory_data;
 reg [4:0] meta_index;reg [5:0] meta_byte;reg [10:0] offset;
 reg [31:0] generation,candidate_generation,crc,stored_crc,magic,marker;
 reg [31:0] candidate_entries;reg [32:0] used_slots;reg [5:0] slot;
 reg active_bank,have_directory,scan_bank,verify_directory,boot_failed,bad_directory,bank_nonblank,any_nonblank;
 reg [7:0] format,entry_limit;reg [15:0] record_no;reg [63:0] word_shift;
 reg [15:0] payload_bytes;reg [7:0] page;reg [3:0] sector;reg [8:0] byte_no,page_length;
 reg [23:0] payload_base,dir_base;reg [7:0] commit_index;
 reg [31:0] expected_duration;
 wire [4:0] catalog_address=state==READY ? lookup_index : meta_index;
 wire [31:0] crc_next=crc_byte(crc,read_data);
 wire [159:0] parsed_meta={read_data,meta_shift[159:8]};
 wire skip_crc=(offset>=12 && offset<20);
 wire [23:0] current_page=payload_base+{8'd0,page,8'd0};
 assign request_ready=state==READY && initialized && !rst;
 assign busy=state!=READY;
 assign storage_lock=state!=READY && initialized;
 assign storage_import=state==IMPORT;
 assign flash_valid=state==IO_SEND;
 function automatic [31:0] crc_byte(input [31:0] c,input [7:0] b);
 reg [31:0] x;begin x=c^{24'd0,b};for(integer k=0;k<8;k++)x=(x>>1)^(x[0]?32'hedb88320:0);crc_byte=x;end endfunction
 function automatic [7:0] header_byte(input [4:0] n,input [31:0] gen);
 begin case(n)
  0:header_byte="F";1:header_byte="S";2:header_byte="C";3:header_byte="1";
  4:header_byte=1;5:header_byte=32;
  8:header_byte=gen[7:0];9:header_byte=gen[15:8];10:header_byte=gen[23:16];11:header_byte=gen[31:24];
  16,17,18,19:header_byte=255;default:header_byte=0;
 endcase end endfunction
 function automatic [7:0] marker_byte(input [1:0] n);
 begin case(n)0:marker_byte="D";1:marker_byte="O";2:marker_byte="N";3:marker_byte="E";endcase end endfunction
 function automatic [55:0] default_name(input [4:0] id);
 begin default_name={8'd0,8'd0,8'd0,8'(48+((id+1)%10)),8'(48+((id+1)/10)),8'd48,8'd83};end endfunction
 task automatic io(input [1:0] op,input [23:0] addr,input [8:0] len,input [6:0] next_state);
 begin flash_op<=op;flash_address<=addr;flash_length<=len;io_return<=next_state;state<=IO_SEND;end endtask
 task automatic finish(input [7:0] e);begin error<=e;job_state<=e==0?2:3;state<=FINISH;end endtask
 task automatic start_directory_read;
 begin offset<=0;page<=0;crc<=32'hffffffff;stored_crc<=0;magic<=0;marker<=0;candidate_generation<=0;
  candidate_entries<=0;bad_directory<=0;bank_nonblank<=0;used_slots<=0;state<=DIR_READ;end endtask
 always @(posedge clk)begin
  catalog_read<=catalog[catalog_address];lookup_data<=entries[lookup_index]?catalog[lookup_index]:160'd0;
  directory_data<=directory[offset];
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=BOOT;io_return<=READY;operation<=0;target<=0;initialized<=0;job_id<=0;job_state<=0;error<=0;done<=0;
   entries<=0;loaded_valid<=0;loaded_index<=0;storage_write<=0;storage_invalidate<=0;storage_address<=0;storage_wdata<=0;storage_count<=0;storage_crc<=0;
   flash_op<=0;flash_address<=0;flash_length<=0;buffer_write<=0;buffer_index<=0;buffer_wdata<=0;read_index<=0;
   meta_shift<=0;new_meta<=0;meta_index<=0;meta_byte<=0;offset<=0;generation<=0;candidate_generation<=0;crc<=0;stored_crc<=0;magic<=0;marker<=0;
   candidate_entries<=0;used_slots<=0;slot<=0;active_bank<=1;have_directory<=0;scan_bank<=0;verify_directory<=0;boot_failed<=0;bad_directory<=0;bank_nonblank<=0;any_nonblank<=0;
   format<=0;entry_limit<=0;record_no<=0;word_shift<=0;payload_bytes<=0;page<=0;sector<=0;byte_no<=0;page_length<=0;payload_base<=0;dir_base<=0;commit_index<=0;expected_duration<=0;
  end else begin
   done<=0;storage_write<=0;storage_invalidate<=0;buffer_write<=0;
   if(upload_active)loaded_valid<=0;
   case(state)
    BOOT:if(flash_initialized && flash_ready)begin dir_base<=0;scan_bank<=0;verify_directory<=0;start_directory_read();end
    READY:if(request_valid)begin
     operation<=command;target<=song_index;meta_index<=song_index;job_id<=job_id+1'b1;job_state<=1;error<=0;
     new_meta<=0;state<=JOB_START;
     if(command==0)begin
      storage_count<=ram_count;storage_crc<=ram_crc;
      new_meta<={8'd0,(song_name==0?default_name(song_index):song_name),ram_crc,ram_duration,ram_count,8'd0,8'd1};
     end
    end
    JOB_START:if(!storage_ready || upload_active)finish(5);
     else if(operation>2)finish(6);
     else if(!flash_supported)finish(8'h21);
     else if(operation==0 && (!ram_valid || storage_count==0 || storage_count>MAX_NOTES))finish(8'h0e);
     else if(operation!=0 && !entries[target])finish(8'h0e);
     else state<=LOOKUP_WAIT;
    LOOKUP_WAIT:state<=LOOKUP_LATCH;
    LOOKUP_LATCH:if(operation==0)begin used_slots<=0;meta_index<=0;state<=ALLOC_READ;end
     else if(operation==2)begin offset<=0;crc<=32'hffffffff;state<=BUILD_HEADER;end
     else begin
      storage_count<=catalog_read[31:16];storage_crc<=catalog_read[95:64];payload_bytes<=catalog_read[31:16]<<3;expected_duration<=catalog_read[63:32];
      payload_base<=24'h010000+{catalog_read[15:8],16'd0};page<=0;record_no<=0;
      storage_invalidate<=1;loaded_valid<=0;crc<=32'hffffffff;state<=READ_PAYLOAD;
     end
    ALLOC_READ:state<=ALLOC_WAIT;
    ALLOC_WAIT:begin
     if(entries[meta_index])used_slots[catalog_read[13:8]]<=1;
     if(meta_index==31)begin slot<=0;state<=ALLOC_SLOT;end else begin meta_index<=meta_index+1'b1;state<=ALLOC_READ;end
    end
    ALLOC_SLOT:if(!used_slots[slot])begin
      new_meta[15:8]<={2'd0,slot};payload_base<=24'h010000+{2'd0,slot,16'd0};payload_bytes<=storage_count<<3;
      sector<=0;page<=0;record_no<=0;crc<=32'hffffffff;state<=ERASE_DATA;
     end else if(slot==32)finish(8);else slot<=slot+1'b1;
    ERASE_DATA:io(3,payload_base+{8'd0,sector,12'd0},1,ERASE_NEXT);
    ERASE_NEXT:if(({12'd0,sector}+1)*4096>=payload_bytes)begin byte_no<=0;state<=SAVE_WORD;end
     else begin sector<=sector+1'b1;state<=ERASE_DATA;end
    SAVE_WORD:begin storage_address<=record_no[AW-1:0];state<=SAVE_WAIT;end
    SAVE_WAIT:state<=SAVE_LATCH;
    SAVE_LATCH:begin word_shift<=storage_rdata;meta_byte<=0;state<=SAVE_BYTE;end
    SAVE_BYTE:begin
     buffer_write<=1;buffer_index<=byte_no[7:0];buffer_wdata<=word_shift[7:0];word_shift<=word_shift>>8;
     byte_no<=byte_no+1'b1;
     if(meta_byte==7)begin
      record_no<=record_no+1'b1;
      if(byte_no==255 || record_no+1==storage_count)begin page_length<=byte_no+1'b1;state<=PROGRAM_PAGE;end
      else state<=SAVE_WORD;
     end else meta_byte<=meta_byte+1'b1;
    end
    PROGRAM_PAGE:io(2,current_page,page_length,READ_PAYLOAD);
    READ_PAYLOAD:begin
     byte_no<=0;read_index<=0;
     if(operation==1)page_length<=((payload_bytes-{page,8'd0})>=256)?9'd256:(payload_bytes-{page,8'd0});
     io(1,current_page,operation==0?page_length:(((payload_bytes-{page,8'd0})>=256)?9'd256:(payload_bytes-{page,8'd0})),PAYLOAD_FETCH);
    end
    PAYLOAD_FETCH:begin read_index<=byte_no[7:0];state<=PAYLOAD_WAIT;end
    PAYLOAD_WAIT:state<=PAYLOAD_BYTE;
    PAYLOAD_BYTE:begin
     crc<=crc_next;word_shift<={read_data,word_shift[63:8]};
     if(operation==1 && byte_no[2:0]==7)begin
      storage_wdata<={read_data,word_shift[63:8]};storage_address<=record_no[AW-1:0];storage_write<=1;
      record_no<=record_no+1'b1;state<=LOAD_WRITE;
     end else state<=PAYLOAD_NEXT;
    end
    LOAD_WRITE:state<=PAYLOAD_NEXT;
    PAYLOAD_NEXT:if(byte_no+1==page_length)begin
     if({page,8'd0}+page_length>=payload_bytes)begin
      if((crc^32'hffffffff)!=storage_crc)finish(9);
      else if(operation==1)state<=IMPORT;
      else begin offset<=0;crc<=32'hffffffff;state<=BUILD_HEADER;end
     end else begin page<=page+1'b1;byte_no<=0;state<=operation==0?SAVE_WORD:READ_PAYLOAD;end
    end else begin byte_no<=byte_no+1'b1;state<=PAYLOAD_FETCH;end
    IMPORT:if(storage_done)begin
     if(storage_error==0 && ram_duration==expected_duration)begin loaded_valid<=1;loaded_index<=target;finish(0);end
     else begin storage_invalidate<=1;finish(storage_error==0?8'd9:storage_error);end
    end
    BUILD_HEADER:begin
     directory[offset]<=header_byte(offset[4:0],generation+1'b1);
     if(!skip_crc)crc<=crc_byte(crc,header_byte(offset[4:0],generation+1'b1));
     if(offset==31)begin meta_index<=0;state<=BUILD_META;end else offset<=offset+1'b1;
    end
    BUILD_META:state<=BUILD_META_WAIT;
    BUILD_META_WAIT:begin
     meta_shift<=meta_index==target ? (operation==2?160'd0:new_meta) : (entries[meta_index]?catalog_read:160'd0);
     meta_byte<=0;state<=BUILD_ENTRY;
    end
    BUILD_ENTRY:begin
     directory[32+{meta_index,5'd0}+meta_byte]<=meta_byte<20?meta_shift[7:0]:8'd0;
     crc<=crc_byte(crc,meta_byte<20?meta_shift[7:0]:8'd0);meta_shift<=meta_shift>>8;
     if(meta_byte==31)begin
      if(meta_index==31)begin commit_index<=0;state<=BUILD_CRC;end
      else begin meta_index<=meta_index+1'b1;state<=BUILD_META;end
     end else meta_byte<=meta_byte+1'b1;
    end
    BUILD_CRC:begin
     directory[12+commit_index]<=~crc[7:0];crc<=crc>>8;
     if(commit_index==3)begin dir_base<=active_bank?24'h000000:24'h001000;state<=DIR_ERASE;end
     else commit_index<=commit_index+1'b1;
    end
    DIR_ERASE:begin offset<=0;page<=0;byte_no<=0;io(3,dir_base,1,DIR_FILL);end
    DIR_FILL:state<=DIR_FILL_WAIT;
    DIR_FILL_WAIT:state<=DIR_FILL_BYTE;
    DIR_FILL_BYTE:begin
     buffer_write<=1;buffer_index<=offset[7:0];buffer_wdata<=directory_data;
     if(offset[7:0]==255 || offset==DIR_BYTES-1)begin page_length<={1'b0,offset[7:0]}+1'b1;state<=DIR_PROGRAM;end
     else begin offset<=offset+1'b1;state<=DIR_FILL;end
    end
    DIR_PROGRAM:io(2,dir_base+{8'd0,page,8'd0},page_length,DIR_WRITE_NEXT);
    DIR_WRITE_NEXT:if(offset==DIR_BYTES-1)begin verify_directory<=1;start_directory_read();end
     else begin page<=page+1'b1;offset<=offset+1'b1;state<=DIR_FILL;end
    DIR_READ:begin
     byte_no<=0;page_length<=DIR_BYTES-{page,8'd0}>=256?9'd256:9'(DIR_BYTES-{page,8'd0});
     io(1,dir_base+{8'd0,page,8'd0},DIR_BYTES-{page,8'd0}>=256?9'd256:9'(DIR_BYTES-{page,8'd0}),DIR_FETCH);
    end
    DIR_FETCH:begin read_index<=byte_no[7:0];state<=DIR_WAIT;end
    DIR_WAIT:state<=DIR_BYTE;
    DIR_BYTE:begin
     if(read_data!=8'hff)bank_nonblank<=1;
     if(!skip_crc)crc<=crc_next;
     if(offset<4)magic<={read_data,magic[31:8]};
     if(offset==4)format<=read_data;if(offset==5)entry_limit<=read_data;
     if(offset>=8 && offset<12)candidate_generation<={read_data,candidate_generation[31:8]};
     if(offset>=12 && offset<16)stored_crc<={read_data,stored_crc[31:8]};
     if(offset>=16 && offset<20)marker<={read_data,marker[31:8]};
     if(offset>=32)begin
      if(offset[4:0]<20)meta_shift<={read_data,meta_shift[159:8]};
      if(offset[4:0]==19)begin
       candidates[(offset-32)>>5]<=parsed_meta;
       if((parsed_meta[7:0]!=0 && parsed_meta[7:0]!=1) ||
        (parsed_meta[7:0]==1 && (parsed_meta[15:8]>32 || parsed_meta[31:16]==0 || parsed_meta[31:16]>MAX_NOTES || parsed_meta[63:32]>3600000)))bad_directory<=1;
       if(parsed_meta[7:0]==1 && parsed_meta[15:8]<=32)begin
        candidate_entries[(offset-32)>>5]<=1;
        if(used_slots[parsed_meta[13:8]])bad_directory<=1;
        used_slots[parsed_meta[13:8]]<=1;
       end
      end
     end
     state<=DIR_NEXT;
    end
    DIR_NEXT:if(offset==DIR_BYTES-1)state<=DIR_CHECK;
     else begin
      offset<=offset+1'b1;
      if(byte_no+1==page_length)begin page<=page+1'b1;state<=DIR_READ;end
      else begin byte_no<=byte_no+1'b1;state<=DIR_FETCH;end
     end
    DIR_CHECK:if(magic!=32'h31435346 || format!=1 || entry_limit!=32 || stored_crc!=(crc^32'hffffffff) || bad_directory ||
       marker!=(verify_directory?32'hffffffff:32'h454e4f44))begin
      if(verify_directory)finish(9);else begin if(bank_nonblank)any_nonblank<=1;state<=BOOT_NEXT;end
     end else if(verify_directory)begin commit_index<=0;state<=MARK_FILL;end
     else if(!have_directory || $signed(candidate_generation-generation)>0)begin meta_index<=0;state<=APPLY;end
     else state<=BOOT_NEXT;
    MARK_FILL:begin
     buffer_write<=1;buffer_index<=commit_index;buffer_wdata<=marker_byte(commit_index[1:0]);
     if(commit_index==3)state<=MARK_PROGRAM;else commit_index<=commit_index+1'b1;
    end
    MARK_PROGRAM:io(2,dir_base+24'd16,4,MARK_READ);
    MARK_READ:begin commit_index<=0;io(1,dir_base+24'd16,4,MARK_FETCH);end
    MARK_FETCH:begin read_index<=commit_index;state<=MARK_WAIT;end
    MARK_WAIT:state<=MARK_CHECK;
    MARK_CHECK:if(read_data!=marker_byte(commit_index[1:0]))finish(9);
     else if(commit_index==3)begin meta_index<=0;state<=APPLY;end
     else begin commit_index<=commit_index+1'b1;state<=MARK_FETCH;end
    APPLY:begin
     catalog[meta_index]<=candidates[meta_index];
     if(meta_index==31)begin
      entries<=candidate_entries;generation<=candidate_generation;active_bank<=dir_base[12];have_directory<=1;
      if(verify_directory)begin
       if(operation==2 && loaded_valid && loaded_index==target)loaded_valid<=0;
       finish(0);
      end else state<=BOOT_NEXT;
     end else meta_index<=meta_index+1'b1;
    end
    BOOT_NEXT:if(!scan_bank)begin scan_bank<=1;dir_base<=24'h001000;start_directory_read();end
     else begin initialized<=1;job_state<=0;error<=(!have_directory && (boot_failed || any_nonblank))?8'h24:8'd0;state<=READY;end
    IO_SEND:if(flash_ready)state<=IO_WAIT;
    IO_WAIT:if(flash_done)begin
     if(flash_error!=0)begin
      if(!initialized)begin boot_failed<=1;state<=BOOT_NEXT;end
      else finish(flash_error);
     end else state<=io_return;
    end
    FINISH:begin done<=1;state<=READY;end
    default:finish(8'h24);
   endcase
  end
 end
 // synthesis translate_off
 initial if(MAX_NOTES<1 || MAX_NOTES>4096)$fatal(1,"invalid library song capacity");
 // synthesis translate_on
endmodule
`timescale 1ns/1ps
// Mode 0. Only clk clocks logic; sck is a registered output.
module spi_byte_master #(parameter integer HALF_CYCLES=25)(
 input wire clk,rst,valid,input wire [7:0] tx,output wire ready,
 output reg done,output reg [7:0] rx,output reg sck,mosi,input wire miso);
 localparam integer CW=$clog2(HALF_CYCLES+1);
 reg busy;reg [CW-1:0] divider;reg [2:0] bit_no;reg [7:0] shift,received;
 assign ready=!busy && !rst;
 always @(posedge clk or posedge rst)begin
  if(rst)begin busy<=0;divider<=0;bit_no<=7;shift<=0;received<=0;rx<=0;done<=0;sck<=0;mosi<=0;end
  else begin done<=0;
   if(valid && ready)begin busy<=1;divider<=0;bit_no<=7;shift<=tx;received<=0;mosi<=tx[7];end
   else if(busy)begin
    if(divider==HALF_CYCLES-1)begin
     divider<=0;sck<=!sck;
     if(!sck)received<={received[6:0],miso};
     else if(bit_no==0)begin busy<=0;rx<=received;done<=1;end
     else begin bit_no<=bit_no-1'b1;shift<=shift<<1;mosi<=shift[6];end
    end else divider<=divider+1'b1;
   end
  end
 end
 // synthesis translate_off
 initial if(HALF_CYCLES<4)$fatal(1,"SPI half-period must accommodate synchronized MISO");
 // synthesis translate_on
endmodule
`timescale 1ns/1ps
// U7 only. Buffered 1..256-byte transactions, no chip erase/status writes.
// Known 3.3V W25Q128JV-IQ EF4018 profile; unknown IDs remain read-only.
module spi_nor_flash #(
 parameter integer HALF_CYCLES=25,BOOT_CYCLES=50000,POLL_CYCLES=5000,TIMEOUT_CYCLES=50000000,
 parameter [23:0] REGION_FIRST=24'h000000,REGION_LAST=24'h21ffff)(
 input wire clk,rst,request_valid,output wire request_ready,input wire [1:0] operation,
 input wire [23:0] address,input wire [8:0] length,input wire writes_enabled,
 output reg done,output reg [7:0] error,output reg initialized,output wire supported,
 output reg [23:0] jedec_id,output reg [7:0] status1,status2,status3,
 input wire buffer_write,input wire [7:0] buffer_index,input wire [7:0] buffer_wdata,
 input wire [7:0] read_index,output reg [7:0] read_data,
 output reg cs_n,output wire sck,mosi,input wire miso,output wire wp_n,hold_n);
 // operation:0 probe,1 read,2 page program,3 sector erase.
 localparam [5:0] BOOT=0,IDLE=1,ID=2,ID_DONE=3,SR1=4,SR1_DONE=5,SR2=6,SR2_DONE=7,SR3=8,SR3_DONE=9,
  DISPATCH=10,WREN=11,WREN_DONE=12,WEL=13,WEL_DONE=14,EXEC=15,EXEC_DONE=16,POLL=17,POLL_DONE=18,
  X_PREP=20,X_SEND=21,X_WAIT=22,X_END=23,FINISH=24,BOOT_STATUS=25,BOOT_STATUS_DONE=26,BOOT_POLL=27;
 reg [5:0] state,return_state;reg [31:0] delay_count,timeout_count;
 reg [1:0] op;reg [23:0] location;reg [8:0] size;
 reg [7:0] opcode,spi_tx,received,program_byte;reg [9:0] index,total,capture_first;
 reg with_address;reg [7:0] buffer[0:255];
 (* async_reg="true" *) reg miso_meta,miso_sync;
 wire byte_ready,byte_done;wire [7:0] spi_rx;
 wire write_ok=writes_enabled && supported && status1[7:2]==0 && !status1[0] && !status2[6] && !status2[0] && !status2[7] && !status3[2];
 wire [24:0] last_address={1'b0,location}+{16'd0,size}-1'b1;
 assign supported=jedec_id==24'hef4018;
 assign request_ready=state==IDLE && initialized && !rst;
 assign wp_n=1;assign hold_n=1;
 spi_byte_master #(.HALF_CYCLES(HALF_CYCLES)) bytes(clk,rst,state==X_SEND,spi_tx,byte_ready,byte_done,spi_rx,sck,mosi,miso_sync);
 always @(posedge clk or posedge rst)begin
  if(rst)begin miso_meta<=1;miso_sync<=1;end else begin miso_meta<=miso!==1'b0;miso_sync<=miso_meta;end
 end
 always @(posedge clk)begin
  read_data<=buffer[read_index];program_byte<=buffer[index[7:0]-8'd4];
  if(buffer_write && request_ready)buffer[buffer_index]<=buffer_wdata;
  else if(state==X_WAIT && byte_done && opcode==8'h03 && index>=capture_first)buffer[index[7:0]-8'd4]<=spi_rx;
 end
 task automatic transfer(input [7:0] code,input bit addr,input [8:0] n,input [5:0] next_state);
 begin opcode<=code;with_address<=addr;total<=10'd1+(addr?10'd3:10'd0)+{1'b0,n};capture_first<=addr?4:1;
  index<=0;cs_n<=0;return_state<=next_state;state<=X_PREP;end endtask
 task automatic fail(input [7:0] reason);begin error<=reason;state<=FINISH;cs_n<=1;end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=BOOT;return_state<=IDLE;delay_count<=BOOT_CYCLES;timeout_count<=0;initialized<=0;
   done<=0;error<=0;jedec_id<=0;status1<=0;status2<=0;status3<=0;cs_n<=1;
   op<=0;location<=0;size<=0;opcode<=0;received<=0;index<=0;total<=0;capture_first<=0;with_address<=0;end
  else begin done<=0;
   if(state!=IDLE && state!=BOOT && timeout_count<TIMEOUT_CYCLES)timeout_count<=timeout_count+1'b1;
   if(state!=IDLE && state!=BOOT && state!=FINISH && timeout_count>=TIMEOUT_CYCLES && state!=X_SEND && state!=X_WAIT && state!=X_PREP && state!=X_END)fail(8'h22);
   else case(state)
    // USR resets FPGA logic, not the external NOR. Wait for an in-flight
    // program/erase before JEDEC (many devices ignore9F while WIP=1).
    BOOT:if(delay_count==0)begin op<=0;timeout_count<=0;state<=BOOT_STATUS;end else delay_count<=delay_count-1'b1;
    BOOT_STATUS:transfer(8'h05,0,1,BOOT_STATUS_DONE);
    BOOT_STATUS_DONE:begin
     status1<=received;
     if(received[0] && received!=8'hff)begin delay_count<=POLL_CYCLES;state<=BOOT_POLL;end else state<=ID;
    end
    BOOT_POLL:if(delay_count==0)state<=BOOT_STATUS;else delay_count<=delay_count-1'b1;
    IDLE:if(request_valid)begin op<=operation;location<=address;size<=length;error<=0;timeout_count<=0;state<=operation==0?ID:SR1;end
    ID:begin jedec_id<=0;transfer(8'h9f,0,3,ID_DONE);end
    ID_DONE:state<=SR1;
    SR1:transfer(8'h05,0,1,SR1_DONE);
    SR1_DONE:begin status1<=received;state<=SR2;end
    SR2:transfer(8'h35,0,1,SR2_DONE);
    SR2_DONE:begin status2<=received;state<=SR3;end
    SR3:transfer(8'h15,0,1,SR3_DONE);
    SR3_DONE:begin status3<=received;initialized<=1;state<=DISPATCH;end
    DISPATCH:if(op==0)state<=FINISH;
     else if(location<REGION_FIRST || location>REGION_LAST || size==0 || size>256 || last_address>{1'b0,REGION_LAST})fail(8'h23);
     else if(status1[0])fail(8'h25);
     else if(op==1)state<=EXEC;
     else if(!write_ok)fail(8'h21);
     else if(op==2 && ({1'b0,location[7:0]}+size)>256)fail(8'h23);
     else if(op==3 && (location[11:0]!=0 || ({1'b0,location}+25'd4095)>{1'b0,REGION_LAST}))fail(8'h23);
     else state<=WREN;
    WREN:transfer(8'h06,0,0,WREN_DONE);
    WREN_DONE:state<=WEL;
    WEL:transfer(8'h05,0,1,WEL_DONE);
    WEL_DONE:if(received[1] && !received[0] && received[7:2]==0)state<=EXEC;else fail(8'h21);
    EXEC:if(op==1)transfer(8'h03,1,size,EXEC_DONE);
     else if(op==2)transfer(8'h02,1,size,EXEC_DONE);
     else transfer(8'h20,1,0,EXEC_DONE);
    EXEC_DONE:if(op==1)state<=FINISH;else begin delay_count<=POLL_CYCLES;state<=POLL;end
    POLL:if(delay_count==0)transfer(8'h05,0,1,POLL_DONE);else delay_count<=delay_count-1'b1;
    POLL_DONE:begin status1<=received;if(received[0])begin delay_count<=POLL_CYCLES;state<=POLL;end else state<=FINISH;end
    X_PREP:state<=X_SEND;
    X_SEND:if(byte_ready)state<=X_WAIT;
    X_WAIT:if(byte_done)begin
     if(index>=capture_first)begin received<=spi_rx;if(opcode==8'h9f)jedec_id<={jedec_id[15:0],spi_rx};end
     if(index+1==total)begin cs_n<=1;delay_count<=HALF_CYCLES*2;state<=X_END;end
     else begin index<=index+1'b1;state<=X_PREP;end
    end
    X_END:if(delay_count==0)state<=return_state;else delay_count<=delay_count-1'b1;
    FINISH:begin done<=1;initialized<=1;state<=IDLE;end
    default:fail(8'h24);
   endcase
  end
 end
 always @*begin
  spi_tx=0;
  if(index==0)spi_tx=opcode;
  else if(with_address && index<4)case(index)1:spi_tx=location[23:16];2:spi_tx=location[15:8];3:spi_tx=location[7:0];default:spi_tx=0;endcase
  else if(opcode==8'h02)spi_tx=program_byte;
 end
endmodule
`timescale 1ns/1ps
// UI-independent song control. Pulsed action, held downstream requests.
// Actions: prev,next,play,pause,resume,stop,load,save,delete-confirmed.
module local_score_control(
 input wire clk,rst,action_valid,input wire [3:0] action,input wire [31:0] entries,
 input wire upload_active,library_busy,input wire song_valid,loaded_valid,input wire [4:0] loaded_index,
 output reg [4:0] selected,output wire busy,output reg done,output reg [7:0] error,
 output wire player_valid,input wire player_ready,output reg [1:0] player_command,
 input wire player_done,input wire [7:0] player_error,
 output wire library_valid,input wire library_ready,output reg [1:0] library_command,
 output reg [4:0] library_index,input wire library_done,input wire [7:0] library_error);
 localparam [2:0] IDLE=0,PLAYER_SEND=1,PLAYER_WAIT=2,LIB_SEND=3,LIB_WAIT=4;
 reg [2:0] state;reg play_after_load;
 assign busy=state!=IDLE;
 assign player_valid=state==PLAYER_SEND;
 assign library_valid=state==LIB_SEND;
 task automatic finish(input [7:0] e);begin error<=e;done<=1;state<=IDLE;end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin selected<=0;state<=IDLE;done<=0;error<=0;player_command<=0;library_command<=0;library_index<=0;play_after_load<=0;end
  else begin done<=0;
   case(state)
    IDLE:if(action_valid)begin
     error<=0;play_after_load<=0;
     if(action==0)begin selected<=selected-1'b1;done<=1;end
     else if(action==1)begin selected<=selected+1'b1;done<=1;end
     else if(upload_active || library_busy)finish(5);
     else if(action>=3 && action<=5)begin player_command<=action-2;state<=PLAYER_SEND;end
     else if(action==2 && loaded_valid && loaded_index==selected && song_valid)begin player_command<=0;state<=PLAYER_SEND;end
     else if(action==2 || action==6 || action==7 || action==8)begin
      if(action!=7 && !entries[selected])finish(8'h0e);
      else if(action==7 && !song_valid)finish(8'h0e);
      else begin
       library_command<=action==7?2'd0:action==8?2'd2:2'd1;library_index<=selected;
       play_after_load<=action==2;state<=LIB_SEND;
      end
     end else finish(6);
    end
    PLAYER_SEND:if(player_ready)state<=PLAYER_WAIT;
    PLAYER_WAIT:if(player_done)finish(player_error);
    LIB_SEND:if(library_ready)state<=LIB_WAIT;
    LIB_WAIT:if(library_done)begin
     if(library_error!=0)finish(library_error);
     else if(play_after_load)begin player_command<=0;state<=PLAYER_SEND;end
     else finish(0);
    end
    default:finish(8'h0d);
   endcase
  end
 end
endmodule
`timescale 1ns/1ps
// Shared RAM/Flash-load validator: sequential reads, one CRC byte/clock,
// one overlap context/clock. No all-record or all-voice combinational compare.
module score_validator #(
 parameter integer MAX_NOTES=4096,VOICES=16,NOTE_MIN=48,NOTE_MAX=83,MAX_MS=3600000,
 AW=(MAX_NOTES>1?$clog2(MAX_NOTES):1))(
 input wire clk,rst,start,input wire [15:0] count,input wire [31:0] expected_crc,
 output reg [AW-1:0] address,input wire [63:0] data,
 output wire busy,output reg done,output reg [7:0] error,
 output reg [31:0] duration);
 localparam [3:0] IDLE=0,FETCH=1,WAIT_RAM=2,LATCH=3,CHECK=4,CRC=5,SCAN=6,EVAL=7;
 reg [3:0] state;reg [15:0] index;reg [63:0] record,bytes;
 reg [31:0] crc,last_time;reg [31:0] ends[0:VOICES-1];
 reg [5:0] slot,free_slot;reg found;reg [2:0] byte_no;
 wire [32:0] ending={1'b0,record[31:0]}+{17'b0,record[63:48]};
 assign busy=state!=IDLE;
 function automatic [31:0] crc_byte(input [31:0] c,input [7:0] b);
 reg [31:0] x;begin x=c^{24'd0,b};for(integer k=0;k<8;k++)x=(x>>1)^(x[0]?32'hedb88320:0);crc_byte=x;end endfunction
 task automatic finish(input [7:0] value);begin error<=value;done<=1;state<=IDLE;end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin state<=IDLE;index<=0;address<=0;record<=0;bytes<=0;crc<=0;last_time<=0;duration<=0;
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
    LATCH:begin record<=data;bytes<=data;state<=CHECK;end
    CHECK:if(record[39:32]<NOTE_MIN || record[39:32]>NOTE_MAX || record[47:40]==0 || record[47:40]>127 ||
       record[63:48]==0 || ending>MAX_MS || record[31:0]<last_time)finish(6);
     else begin last_time<=record[31:0];if(ending>duration)duration<=ending[31:0];byte_no<=0;state<=CRC;end
    CRC:begin
     crc<=crc_byte(crc,bytes[7:0]);bytes<=bytes>>8;
     if(byte_no==7)begin slot<=0;free_slot<=0;found<=0;state<=SCAN;end
     else byte_no<=byte_no+1'b1;
    end
    SCAN:begin
     if(!found && ends[slot]<=record[31:0])begin found<=1;free_slot<=slot;end
     if(slot==VOICES-1)state<=EVAL;else slot<=slot+1'b1;
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
`timescale 1ns/1ps
// Keyboard-independent ownership and pending frame commands. Rank is a
// bounded permutation, avoiding the wraparound of timestamp-based stealing.
module voice_allocator #(parameter integer VOICES=4)(
    input wire clk,rst,enabled,frame_ce,note_valid,note_on,
    input wire [6:0] note_id,input wire [31:0] note_fcw,
    input wire [VOICES-1:0] voice_active,
    output wire note_ready,output wire [VOICES-1:0] voice_start,voice_stop,voice_restart,
    output reg [VOICES-1:0] voice_held,
    output wire [VOICES*32-1:0] voice_fcw,
    output wire [VOICES*7-1:0] voice_ids,input wire [2:0] note_timbre,
    output wire [VOICES*3-1:0] voice_timbres);
    localparam integer RW=VOICES>1?$clog2(VOICES):1;
    reg [VOICES-1:0] owned,pending_start,pending_restart,committed_gate;
    reg [6:0] ids [0:VOICES-1];
    reg [31:0] frequencies [0:VOICES-1];
    reg [RW-1:0] rank [0:VOICES-1];
    reg [2:0] timbres[0:VOICES-1];
    // Read one context, then compare its registered metadata. No candidate
    // index feeds another context read in the same cycle. The producer holds
    // the event until OFFER; ownership still changes on its handshake edge.
    localparam [2:0] IDLE=0,READ_CONTEXT=1,COMPARE=2,SELECT=3,OFFER=4;
    reg [2:0] search_state;
    reg [RW-1:0] scan_slot,scan_rank;
    reg scan_match,scan_free,scan_released;
    reg match_found,free_found,released_found,oldest_found;
    reg [RW-1:0] match_slot,free_slot,released_slot,oldest_slot,target;
    reg [RW-1:0] match_rank,free_rank,released_rank,oldest_rank,target_rank;
    reg target_matched;
    reg event_on;
    reg [6:0] event_id;
    reg [31:0] event_fcw;
    reg [2:0] event_timbre;
    assign note_ready=!rst && enabled && !frame_ce && search_state==OFFER;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            search_state<=IDLE;scan_slot<=0;scan_rank<=0;
            scan_match<=0;scan_free<=0;scan_released<=0;
            match_found<=0;free_found<=0;released_found<=0;oldest_found<=0;
            match_slot<=0;free_slot<=0;released_slot<=0;oldest_slot<=0;target<=0;
            match_rank<=0;free_rank<=0;released_rank<=0;oldest_rank<=0;target_rank<=0;
            target_matched<=0;event_on<=0;event_id<=0;event_fcw<=0;event_timbre<=0;
        end else if(frame_ce || !enabled)begin
            // A frame can retire an ownership or change active flags. Cancel
            // the unacknowledged search and retry against the new snapshot.
            search_state<=IDLE;
        end else case(search_state)
            IDLE:if(note_valid)begin
                event_on<=note_on;event_id<=note_id;event_fcw<=note_fcw;
                case(note_timbre)
                    3'd1:event_timbre<=1;
                    3'd2:event_timbre<=2;
                3'd3:event_timbre<=3;3'd4:event_timbre<=4;3'd5:event_timbre<=5;3'd6:event_timbre<=6;
                    default:event_timbre<=0;
                endcase
                scan_slot<=0;match_found<=0;free_found<=0;
                released_found<=0;oldest_found<=0;
                search_state<=READ_CONTEXT;
            end
            READ_CONTEXT:begin
                scan_rank<=rank[scan_slot];
                scan_match<=owned[scan_slot] && ids[scan_slot]==event_id;
                scan_free<=!owned[scan_slot] ||
                    (!voice_active[scan_slot] && !voice_held[scan_slot] &&
                     !pending_start[scan_slot] && !committed_gate[scan_slot]);
                scan_released<=owned[scan_slot] && !voice_held[scan_slot] && !pending_start[scan_slot];
                search_state<=COMPARE;
            end
            COMPARE:begin
                if(scan_match)begin
                    match_found<=1;match_slot<=scan_slot;match_rank<=scan_rank;
                end
                if(scan_free && !free_found)begin
                    free_found<=1;free_slot<=scan_slot;free_rank<=scan_rank;
                end
                if(scan_released && (!released_found || scan_rank<released_rank))begin
                    released_found<=1;released_slot<=scan_slot;released_rank<=scan_rank;
                end
                if(!oldest_found || scan_rank<oldest_rank)begin
                    oldest_found<=1;oldest_slot<=scan_slot;oldest_rank<=scan_rank;
                end
                if(scan_slot==VOICES-1)search_state<=SELECT;
                else begin scan_slot<=scan_slot+1'b1;search_state<=READ_CONTEXT;end
            end
            SELECT:begin
                target_matched<=match_found;
                if(match_found)begin target<=match_slot;target_rank<=match_rank;end
                else if(free_found)begin target<=free_slot;target_rank<=free_rank;end
                else if(released_found)begin target<=released_slot;target_rank<=released_rank;end
                else begin target<=oldest_slot;target_rank<=oldest_rank;end
                search_state<=OFFER;
            end
            OFFER:search_state<=IDLE;
            default:search_state<=IDLE;
        endcase
    end
    for(genvar v=0;v<VOICES;v=v+1)begin: ports
        assign voice_fcw[v*32+:32]=frequencies[v];
        assign voice_ids[v*7+:7]=ids[v];
        assign voice_timbres[v*3+:3]=timbres[v];
        assign voice_start[v]=!rst && frame_ce && pending_start[v];
        assign voice_restart[v]=voice_start[v] && pending_restart[v];
        assign voice_stop[v]=!rst && frame_ce && !pending_start[v] && committed_gate[v] && !voice_held[v];
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            owned<=0;voice_held<=0;pending_start<=0;pending_restart<=0;committed_gate<=0;
            for(integer i=0;i<VOICES;i=i+1)begin ids[i]<=0;frequencies[i]<=0;rank[i]<=i;timbres[i]<=0;end
        end else if(frame_ce)begin
            for(integer i=0;i<VOICES;i=i+1)begin
                if(pending_start[i])begin
                    pending_start[i]<=0;pending_restart[i]<=0;committed_gate[i]<=1;
                end else if(committed_gate[i] && !voice_held[i])committed_gate[i]<=0;
                if(!voice_held[i] && !voice_active[i] && !pending_start[i] && !committed_gate[i])owned[i]<=0;
            end
        end else if(note_valid && note_ready)begin
            // Constant-index writes avoid a variable bit-write barrel network.
            // target_rank was captured during search, not read through target.
            for(integer i=0;i<VOICES;i=i+1)begin
                if(event_on)begin
                    if(target==i)begin
                        owned[i]<=1;voice_held[i]<=1;ids[i]<=event_id;
                        frequencies[i]<=event_fcw;timbres[i]<=event_timbre;
                        pending_start[i]<=1;
                        if(!target_matched)pending_restart[i]<=1;
                        rank[i]<=VOICES-1;
                    end else if(rank[i]>target_rank)rank[i]<=rank[i]-1'b1;
                end else if(target_matched && target==i)begin
                    // Ignore releases for stolen IDs. On+Off before a frame
                    // still starts once and releases on the following frame.
                    voice_held[i]<=0;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(VOICES<1 || VOICES>32)$fatal(1,"Invalid voice count");
    always @(posedge clk)if(!rst)begin
        if(search_state!=IDLE && scan_slot>=VOICES)$fatal(1,"Search context out of range");
        if(note_valid && note_ready &&
           ({note_on,note_id,note_fcw}!=={event_on,event_id,event_fcw}))
            $fatal(1,"Producer changed an unacknowledged note event");
    end
    // synthesis translate_on
endmodule

`timescale 1ns/1ps






































// Registered serial accumulation. The final conversion includes this cycle's
// last voice, avoiding both a long combinational adder chain and stale sums.
module voice_mixer(
    input wire clk,rst,in_valid,input wire signed [24-1:0] voice_sample,
    input wire first,last,output reg out_valid,
    output reg signed [16-1:0] sample);
    reg signed [40-1:0] accumulator;
    wire signed [40-1:0] extended_sample={{(40-24){voice_sample[24-1]}},voice_sample};
    wire signed [40-1:0] total=(first?{40{1'b0}}:accumulator)+extended_sample;
    wire signed [40-1:0] scaled=total >>> (24-16);
    always @(posedge clk or posedge rst)begin
        if(rst)begin accumulator<=0;out_valid<=0;sample<=0;end
        else begin
            out_valid<=in_valid && last;
            if(in_valid)begin
                accumulator<=total;
                if(last)begin
                    if(scaled>32767)sample<=16'sh7fff;
                    else if(scaled < -32768)sample<=16'sh8000;
                    else sample<=scaled[16-1:0];
                end
            end
        end
    end
endmodule
`timescale 1ns/1ps






































module lock_guard #(parameter integer STABLE_CYCLES=(50000000*2/1000))(
    input wire clk, rst, lock_async, output reg qualified);
    localparam integer CW=$clog2(STABLE_CYCLES+1);
    wire arst=rst | ~lock_async;
    (* syn_preserve=1, syn_async_reg=1 *) reg [1:0] lock_sync;
    reg [CW-1:0] count;
    always @(posedge clk or posedge arst) begin
        if(arst) begin lock_sync<=0; count<=0; qualified<=0; end
        else begin
            lock_sync<={lock_sync[0],1'b1};
            if(!lock_sync[1]) begin count<=0; qualified<=0; end
            else if(!qualified) begin
                if(count==STABLE_CYCLES-1) qualified<=1;
                else count<=count+1'b1;
            end
        end
    end
endmodule
`timescale 1ns/1ps








module matrix_keypad #(
    parameter integer SLOT_CYCLES=(61440000/20000),
    SETTLE_CYCLES=(61440000/100000),DEBOUNCE_SCANS=15)(
    input wire clk,rst,input wire [3:0] row_n,
    output wire [3:0] col_enable,
    output reg [15:0] keys,output reg scan_valid,ghost);
    localparam integer SW=$clog2(SLOT_CYCLES+1);
    localparam integer DW=DEBOUNCE_SCANS>1?$clog2(DEBOUNCE_SCANS+1):1;
    (* syn_preserve=1, syn_async_reg=1 *) reg [3:0] rows_meta,rows_sync;
    reg [SW-1:0] slot_count;
    reg [1:0] column;
    reg [15:0] work;
    reg [3:0] early_rows;
    reg [DW-1:0] debounce [0:15];
    reg ambiguous;
    reg [3:0] common_rows;
    integer a,b,k;
    assign col_enable=rst?4'b0:(4'b0001<<column);
    always @* begin
        ambiguous=0;common_rows=0;
        for(integer c=0;c<4;c=c+1)
            for(integer d=c+1;d<4;d=d+1)begin
                for(integer rr=0;rr<4;rr=rr+1)
                    common_rows[rr]=work[rr*4+c] && work[rr*4+d];
                if((common_rows & (common_rows-4'd1))!=0) ambiguous=1;
            end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin rows_meta<=4'hf;rows_sync<=4'hf;end
        else begin rows_meta<=row_n;rows_sync<=rows_meta;end
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            slot_count<=0;column<=0;work<=0;keys<=0;scan_valid<=0;ghost<=0;early_rows<=4'hf;
            for(integer i=0;i<16;i=i+1)debounce[i]<=0;
        end else begin
            scan_valid<=0;
            if(slot_count==SETTLE_CYCLES-1)early_rows<=rows_sync;
            // Require low at both settled and late samples. A row still low
            // from the preceding column must not create a second key.
            if(slot_count==SLOT_CYCLES-2)
                for(integer rr=0;rr<4;rr=rr+1)work[rr*4+column]<=!rows_sync[rr] && !early_rows[rr];
            if(slot_count==SLOT_CYCLES-1)begin
                slot_count<=0;column<=column+1'b1;
                if(column==3)begin
                    scan_valid<=1;ghost<=ambiguous;
                    for(integer i=0;i<16;i=i+1)begin
                        // A rectangle without per-key diodes is ambiguous.
                        // Clear accepted keys immediately; do not invent notes.
                        if(ambiguous)begin keys[i]<=0;debounce[i]<=0;end
                        else if(work[i]==keys[i])debounce[i]<=0;
                        else if(debounce[i]==DEBOUNCE_SCANS-1)begin
                            keys[i]<=work[i];debounce[i]<=0;
                        end else debounce[i]<=debounce[i]+1'b1;
                    end
                end
            end else slot_count<=slot_count+1'b1;
        end
    end
    // synthesis translate_off
    initial begin
        if(SETTLE_CYCLES<3 || SLOT_CYCLES<=SETTLE_CYCLES || DEBOUNCE_SCANS<1)
            $fatal(1,"Invalid matrix scan timing");
    end
    // synthesis translate_on
endmodule
`timescale 1ns/1ps
// Matrix-specific state-to-event adapter. An offered event remains stable
// through backpressure; acknowledged state catches up to the latest keys.
module key_note_events #(parameter integer BASE_NOTE=60)(
    input wire clk,rst,enabled,input wire [15:0] keys,input wire note_ready,
    output reg note_valid,note_on,output reg [6:0] note_id,
    output reg [31:0] note_fcw,output wire gate,output reg [3:0] last_key,
    input wire [2:0] selected_timbre,output reg [2:0] note_timbre);
function automatic [31:0] key_fcw(input [3:0] key);
begin case(key)
4'd0:key_fcw=32'h016534C3; // MIDI 60
4'd1:key_fcw=32'h017A725A; // MIDI 61
4'd2:key_fcw=32'h0190F347; // MIDI 62
4'd3:key_fcw=32'h01A8CAC3; // MIDI 63
4'd4:key_fcw=32'h01C20D2F; // MIDI 64
4'd5:key_fcw=32'h01DCD01D; // MIDI 65
4'd6:key_fcw=32'h01F92A6D; // MIDI 66
4'd7:key_fcw=32'h02173456; // MIDI 67
4'd8:key_fcw=32'h02370783; // MIDI 68
4'd9:key_fcw=32'h0258BF26; // MIDI 69
4'd10:key_fcw=32'h027C780B; // MIDI 70
4'd11:key_fcw=32'h02A250BA; // MIDI 71
4'd12:key_fcw=32'h02CA6987; // MIDI 72
4'd13:key_fcw=32'h02F4E4B4; // MIDI 73
4'd14:key_fcw=32'h0321E68D; // MIDI 74
4'd15:key_fcw=32'h03519586; // MIDI 75
default:key_fcw=32'h016534C3;
endcase end
endfunction
    reg [15:0] reported_keys;
    reg [3:0] offered_key;
    wire [15:0] released=reported_keys & ~keys;
    wire [15:0] pressed=keys & ~reported_keys;
    reg [3:0] candidate;
    always @* begin
        candidate=0;
        // Prefer releases when selecting a NEW event, then lowest key number.
        for(integer k=15;k>=0;k=k-1)
            if((|released)?released[k]:pressed[k])candidate=k;
    end
    assign gate=|reported_keys;
    always @(posedge clk or posedge rst)begin
        if(rst)begin
            reported_keys<=0;offered_key<=0;last_key<=0;
            note_valid<=0;note_on<=0;note_id<=0;note_fcw<=0;note_timbre<=0;
        end else if(note_valid)begin
            if(note_ready)begin
                reported_keys[offered_key]<=note_on;
                if(note_on)last_key<=offered_key;
                note_valid<=0;
            end
        end else if(enabled && (|released || |pressed))begin
            offered_key<=candidate;
            note_on<=!(|released);
            note_id<=BASE_NOTE+candidate;
            note_fcw<=key_fcw(candidate);
            case(selected_timbre)
                3'd1:note_timbre<=1;
                3'd2:note_timbre<=2;
                3'd3:note_timbre<=3;3'd4:note_timbre<=4;3'd5:note_timbre<=5;3'd6:note_timbre<=6;
                default:note_timbre<=0;
            endcase
            note_valid<=1;
        end
    end
    // synthesis translate_off
    initial if(BASE_NOTE<0 || BASE_NOTE+15>127)$fatal(1,"Invalid matrix note range");
    // synthesis translate_on
endmodule

`timescale 1ns/1ps






































// Explicit GW5AST-138 PLL primitive wrapper. Coefficients from UG306.
// IP legality and global routing must be checked by Gowin P&R.
module pll_pair(input wire ref_clk,rst,pll2_rst,
    output wire mid_clk,audio_clk,lock1,lock2);
    PLL #(.FCLKIN("50"),.IDIV_SEL(1),.FBDIV_SEL(1),.MDIV_SEL(16),
        .ODIV0_SEL(25),.CLKFB_SEL("INTERNAL")) pll1(
        .CLKIN(ref_clk),.CLKOUT0(mid_clk),.CLKOUT1(),.CLKOUT2(),.CLKOUT3(),
        .CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.CLKFBOUT(),.LOCK(lock1),.RESET(rst),
        .CLKFB(1'b0),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
        .ENCLK0(1'b1),.ENCLK1(1'b0),.ENCLK2(1'b0),.ENCLK3(1'b0),
        .ENCLK4(1'b0),.ENCLK5(1'b0),.ENCLK6(1'b0),
        .FBDSEL(6'b0),.IDSEL(6'b0),.MDSEL(7'b0),.MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0),.ODSEL0_FRAC(3'b0),.ODSEL1(7'b0),.ODSEL2(7'b0),
        .ODSEL3(7'b0),.ODSEL4(7'b0),.ODSEL5(7'b0),.ODSEL6(7'b0),
        .DT0(4'b0),.DT1(4'b0),.DT2(4'b0),.DT3(4'b0),
        .PSSEL(3'b0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),
        .SSCON(1'b0),.SSCMDSEL(7'b0),.SSCMDSEL_FRAC(3'b0),
        .ICPSEL(6'b0),.LPFRES(3'b0),.LPFCAP(2'b0));
    PLL #(.FCLKIN("32"),.IDIV_SEL(1),.FBDIV_SEL(1),.MDIV_SEL(24),
        .ODIV0_SEL(12),.ODIV0_FRAC_SEL(4),.CLKFB_SEL("INTERNAL")) pll2(
        .CLKIN(mid_clk),.CLKOUT0(audio_clk),.CLKOUT1(),.CLKOUT2(),.CLKOUT3(),
        .CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.CLKFBOUT(),.LOCK(lock2),.RESET(pll2_rst),
        .CLKFB(1'b0),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
        .ENCLK0(1'b1),.ENCLK1(1'b0),.ENCLK2(1'b0),.ENCLK3(1'b0),
        .ENCLK4(1'b0),.ENCLK5(1'b0),.ENCLK6(1'b0),
        .FBDSEL(6'b0),.IDSEL(6'b0),.MDSEL(7'b0),.MDSEL_FRAC(3'b0),
        .ODSEL0(7'b0),.ODSEL0_FRAC(3'b0),.ODSEL1(7'b0),.ODSEL2(7'b0),
        .ODSEL3(7'b0),.ODSEL4(7'b0),.ODSEL5(7'b0),.ODSEL6(7'b0),
        .DT0(4'b0),.DT1(4'b0),.DT2(4'b0),.DT3(4'b0),
        .PSSEL(3'b0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),
        .SSCON(1'b0),.SSCMDSEL(7'b0),.SSCMDSEL_FRAC(3'b0),
        .ICPSEL(6'b0),.LPFRES(3'b0),.LPFCAP(2'b0));
endmodule
`timescale 1ns/1ps
// MAX98357A: standard I2S, 16 bits/channel, LRCLK low=left. Data changes on
// falling BCLK and is sampled on rising BCLK. A WS transition precedes the new
// MSB by one bit; the boundary bit is the PREVIOUS channel's LSB, not padding.
module i2s_tx(input wire clk,rst,fall_ce,input wire [4:0] bit_index,
    input wire [15:0] frame_l,frame_r,output reg ws,din);
    reg [15:0] latched_l,latched_r;
    always @(posedge clk or posedge rst)begin
        if(rst)begin ws<=1;din<=0;latched_l<=0;latched_r<=0;end
        else if(fall_ce)begin
            ws<=bit_index[4];
            if(bit_index==0)begin
                // Atomically take the new pair, while finishing the old right
                // word. frame_buffer supplies its old pending pair at this CE.
                latched_l<=frame_l;latched_r<=frame_r;din<=latched_r[0];
            end else if(bit_index<=16)din<=latched_l[16-bit_index];
            else din<=latched_r[32-bit_index];
        end
    end
endmodule
`timescale 1ns/1ps
module reset_sync(input wire clk, input wire arst, output wire rst);
    (* syn_preserve=1, syn_async_reg=1 *) reg [1:0] pipe;
    always @(posedge clk or posedge arst)
        if (arst) pipe <= 2'b11;
        else pipe <= {pipe[0],1'b0};
    assign rst=pipe[1];
endmodule
`timescale 1ns/1ps








module run_leds #(
    parameter integer STEP_CYCLES=(50000000/4),
    DIAG_STEPS=4)(
    input wire clk,audio_ready_async,key_active_async,
    input wire pll1_lock_async,pll2_lock_async,reset_active_async,
    output wire [5:0] led_n);
    localparam integer CW=STEP_CYCLES>1?$clog2(STEP_CYCLES):1;
    localparam integer DW=DIAG_STEPS>0?$clog2(DIAG_STEPS+1):1;
    // Configuration/GSR initializes this reference-clock-only observer.
    // No diagnostic signal feeds back into PLL, reset, keyboard or audio.
    reg [CW-1:0] count=0;
    reg [1:0] position=0;
    reg [DW-1:0] waiting_steps=0;
    (* syn_preserve=1,syn_async_reg=1 *) reg [1:0] ready_sync=0,key_sync=0;
    (* syn_preserve=1,syn_async_reg=1 *) reg [1:0] lock1_sync=0,lock2_sync=0,button_sync=0;
    wire step_tick=(count==STEP_CYCLES-1);
    wire diagnostic_active=(DIAG_STEPS>0) && !ready_sync[1] && (waiting_steps==DIAG_STEPS);
    wire [3:0] run_n=~(4'b0001<<position);
    // Logical LED0 heartbeat, LED1/2 raw lock indications, LED3 reset input.
    // A visibly steady lock LED does not exclude sub-cycle LOCK glitches.
    wire [3:0] diagnostic_n={~button_sync[1],~lock2_sync[1],~lock1_sync[1],~position[0]};
    always @(posedge clk)begin
        ready_sync<={ready_sync[0],audio_ready_async};
        key_sync<={key_sync[0],key_active_async};
        lock1_sync<={lock1_sync[0],pll1_lock_async};
        lock2_sync<={lock2_sync[0],pll2_lock_async};
        button_sync<={button_sync[0],reset_active_async};
        if(step_tick)begin count<=0;position<=position+1'b1;end
        else count<=count+1'b1;
        if(ready_sync[1])waiting_steps<=0;
        else if(step_tick && DIAG_STEPS>0 && waiting_steps<DIAG_STEPS)
            waiting_steps<=waiting_steps+1'b1;
    end
    assign led_n[3:0]=diagnostic_active?diagnostic_n:run_n;
    assign led_n[4]=~ready_sync[1];
    assign led_n[5]=~key_sync[1];
    // synthesis translate_off
    initial if(STEP_CYCLES<1 || DIAG_STEPS<0)$fatal(1,"Invalid LED interval/diagnostic delay");
    // synthesis translate_on
endmodule
`timescale 1ns/1ps






































module sine_rom #(parameter ROM_FILE="src/rom/sine4096.hex")(
    input wire clk, ce, input wire [12-1:0] addr,
    output reg signed [16-1:0] q);
    reg signed [16-1:0] mem [0:(1<<12)-1];
    initial $readmemh(ROM_FILE,mem);
    always @(posedge clk) if(ce) q<=mem[addr];
endmodule
`timescale 1ns/1ps






































module startup_envelope #(parameter integer MUTE=480, FADE=240)(
    input wire clk,rst,frame_ce,output reg pa_enable,output reg [16:0] level);
    localparam integer MW=$clog2(MUTE+1), FW=$clog2(FADE+1);
    reg [MW-1:0] mute_count;
    reg [FW-1:0] fade_count;
    wire [31:0] next_level=((fade_count+32'd1)*32'd65536)/FADE;
    always @(posedge clk or posedge rst) begin
        if(rst) begin mute_count<=0; fade_count<=0; pa_enable<=0; level<=0; end
        else if(frame_ce) begin
            if(!pa_enable) begin
                // The first boundary STARTS frame zero; MUTE complete frames
                // have elapsed only at boundary MUTE (not MUTE-1).
                if(mute_count==MUTE) pa_enable<=1;
                else mute_count<=mute_count+1'b1;
            end else if(fade_count<FADE) begin
                fade_count<=fade_count+1'b1;
                level<=next_level[16:0];
            end
        end
    end
endmodule
`timescale 1ns/1ps






































module tone_gain #(parameter integer OUTPUT_W=16)(input wire clk,rst,in_valid,
    input wire signed [15:0] in_sample, input wire [16:0] level,
    output reg out_valid, output reg signed [OUTPUT_W-1:0] out_sample);
    localparam signed [41:0] MAX_OUT=(42'sd1 << (OUTPUT_W-1))-1;
    localparam signed [41:0] MIN_OUT=-(42'sd1 << (OUTPUT_W-1));
    wire signed [23:0] voice_q23={in_sample,8'b0};
    wire signed [17:0] level_signed=$signed({1'b0,level});
    wire signed [41:0] product=voice_q23*level_signed;
    wire signed [41:0] scaled=product >>> (16+5+24-OUTPUT_W);
    always @(posedge clk or posedge rst) begin
        if(rst) begin out_valid<=0; out_sample<=0; end
        else begin
            out_valid<=in_valid;
            if(in_valid) begin
                if(scaled>MAX_OUT) out_sample<=MAX_OUT[OUTPUT_W-1:0];
                else if(scaled < MIN_OUT) out_sample<=MIN_OUT[OUTPUT_W-1:0];
                else out_sample<=scaled[OUTPUT_W-1:0];
            end
        end
    end
endmodule
