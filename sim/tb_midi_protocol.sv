`timescale 1ns/1ps
module tb_midi_protocol;
 parameter integer CLOCK_HZ=1000000,VOICES=4,MAX_NOTES=4096;
 localparam integer MS=CLOCK_HZ/1000;
 reg clk=0,rst=1,rx_valid=0,rx_fault=0,event_ready=1;
 reg [7:0] rx_data=0;wire rx_ready,tx_valid;wire [7:0] tx_data;
 reg [15:0] lfsr=16'h347a;wire tx_ready=lfsr[0]||lfsr[2];
 wire [4:0] tone;wire legacy,fmt;wire ev,song,upload,inhibit,bad_frame,fault;wire [1:0] kind,play;wire [6:0] id,pitch,velocity;wire [31:0] position;wire [7:0] error_code;wire [15:0] received,total;
 always #5 clk=~clk;
 bluetooth_score_core #(.CLOCK_HZ(CLOCK_HZ),.MAX_NOTES(MAX_NOTES),.MAX_VOICES(VOICES),.NOTE_MIN(21),.NOTE_MAX(108),.UPLOAD_TIMEOUT_MS(20),.GAP_TIMEOUT_MS(2),.FRAME_TIMEOUT_MS(10)) dut(
  .clk(clk),.rst(rst),.rx_valid(rx_valid),.rx_data(rx_data),.rx_ready(rx_ready),.rx_fault(rx_fault),
  .tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready),.event_valid(ev),.event_ready(event_ready),
  .event_timbre(tone),.event_legacy(legacy),.song_format(fmt),.event_kind(kind),.event_id(id),.event_pitch(pitch),.event_velocity(velocity),.song_valid(song),.upload_active(upload),
  .play_state(play),.position_ms(position),.manual_inhibit(inhibit),.last_error(error_code),.received_notes(received),.total_notes(total),
  .bad_frame(bad_frame),.scheduler_fault(fault),.local_valid(1'b0),.local_command(2'd0),.storage_lock(1'b0));
 integer checks=0,responses=0,reply_count=0,reply_goal=0,on_count=0,off_count=0,silences=0,faults=0;
 reg [7:0] response_bytes[0:63],response_payload[0:19];reg [7:0] response_cmd;reg [15:0] response_seq;integer response_len;
 reg [1:0] event_types[0:4095];reg [6:0] event_ids[0:4095],event_pitches[0:4095];reg [31:0] event_times[0:4095];integer event_count=0;
 integer max_wait_cycles=0;
 reg held=0;reg [28:0] held_event;
 function automatic [15:0] crc16_byte(input [15:0] c,input [7:0] b);
  reg [15:0] x;begin x=c^{b,8'b0};for(integer i=0;i<8;i++)x=(x<<1)^(x[15]?16'h1021:0);crc16_byte=x;end
 endfunction
 function automatic [31:0] crc32_byte(input [31:0] c,input [7:0] b);
  reg [31:0] x;begin x=c^{24'b0,b};for(integer i=0;i<8;i++)x=(x>>1)^(x[0]?32'hedb88320:0);crc32_byte=x;end
 endfunction
 task check(input bit ok,input string text);begin checks++;if(!ok)$fatal(1,"%s at %0t",text,$time);end endtask
 always @(posedge clk)begin
  if(rst)lfsr<=16'h347a;else lfsr<={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
  if(!rst&&fault)faults++;
  if(!rst&&held)check(ev&&{legacy,tone,kind,id,pitch,velocity}===held_event,"stalled event payload remains stable");
  held<=!rst&&ev&&!event_ready;held_event<={legacy,tone,kind,id,pitch,velocity};
  if(!rst&&ev&&event_ready)begin
   event_types[event_count]=kind;event_ids[event_count]=id;event_pitches[event_count]=pitch;event_times[event_count]=position;event_count++;
   case(kind)0:off_count++;1:begin on_count++;check(velocity>=1&&velocity<=127,"event velocity preserved");end 2,3:silences++;default:$fatal(1,"bad event kind");endcase
  end
  if(!rst&&tx_valid&&tx_ready)begin
   response_bytes[reply_count]=tx_data;reply_count++;
   if(reply_count==8)reply_goal=10+{response_bytes[7],response_bytes[6]};
   if(reply_goal>0&&reply_count==reply_goal)begin
    reg [15:0] expected_crc;
    expected_crc=16'hffff;for(integer k=2;k<reply_goal-2;k++)expected_crc=crc16_byte(expected_crc,response_bytes[k]);
    check(response_bytes[0]==8'ha5&&response_bytes[1]==8'h5a&&response_bytes[2]==1,"response header/version");
    check({response_bytes[reply_goal-1],response_bytes[reply_goal-2]}==expected_crc,"response CRC independently checked");
    response_cmd=response_bytes[3];response_seq={response_bytes[5],response_bytes[4]};response_len=reply_goal-10;
    for(integer k=0;k<response_len;k++)response_payload[k]=response_bytes[k+8];
    responses++;reply_count=0;reply_goal=0;
   end
  end
 end
 task clocks(input integer n);repeat(n)@(negedge clk);endtask
 reg [7:0] request_payload[0:255];reg [7:0] records[0:MAX_NOTES*12-1];integer record_bytes;
 function automatic [31:0] record_crc(input integer n);
  reg [31:0] c;begin c=32'hffffffff;for(integer k=0;k<n*12;k++)c=crc32_byte(c,records[k]);record_crc=c^32'hffffffff;end
 endfunction
 task record(input integer index,input [31:0] start,input [7:0] note,vel,input [15:0] duration);
  begin for(integer k=0;k<4;k++)records[index*12+k]=start>>(8*k);records[index*12+4]=note;records[index*12+5]=vel;records[index*12+6]=duration[7:0];records[index*12+7]=duration[15:8];end
 endtask
 task byte_send(input [7:0] b);
  begin while(!rx_ready)@(negedge clk);rx_data=b;rx_valid=1;@(negedge clk);rx_valid=0;end
 endtask
 task request(input [7:0] cmd,input [15:0] seq,input integer len,input bit corrupt,input [7:0] version);
  reg [7:0] b;reg [15:0] c;begin
   byte_send(8'ha5);byte_send(8'h5a);c=16'hffff;
   for(integer k=0;k<6+len;k++)begin
    case(k)0:b=version;1:b=cmd;2:b=seq[7:0];3:b=seq[15:8];4:b=len&255;5:b=len>>8;default:b=request_payload[k-6];endcase
    byte_send(b);c=crc16_byte(c,b);
   end
   byte_send(c[7:0]^(corrupt?8'h01:0));byte_send(c[15:8]);
  end
 endtask
 task exchange(input [7:0] cmd,input [15:0] seq,input integer len,input [7:0] status);
  integer old,watchdog;begin old=responses;request(cmd,seq,len,0,1);watchdog=0;
   while(responses==old&&watchdog<CLOCK_HZ/2)begin clocks(1);watchdog++;end
   if(watchdog>max_wait_cycles)max_wait_cycles=watchdog;
   check(responses==old+1,"response before 500ms budget");$display("REQ %h seq %0d len %0d expected %h actual %h",cmd,seq,len,status,response_payload[0]);check(response_cmd==(cmd|8'h80)&&response_seq==seq&&response_payload[0]==status,"response identity/status");
  end
 endtask
 task begin_upload(input integer seq,n,input [31:0] crc,input [7:0] status);
  begin request_payload[0]=n&255;request_payload[1]=n>>8;for(integer k=0;k<4;k++)request_payload[k+2]=crc>>(8*k);exchange(8'h10,seq,6,status);end
 endtask
 task data_upload(input integer seq,index,n,input [7:0] status);
  begin request_payload[0]=index&255;request_payload[1]=index>>8;for(integer k=0;k<n*12;k++)request_payload[k+2]=records[index*12+k];exchange(8'h11,seq,2+n*12,status);end
 endtask
 integer seqno=1,prior_count;reg [31:0] crc;reg [4:0] on_tones[0:127];integer tone_count=0;
 always @(posedge clk)if(!rst && ev && event_ready && kind==1)begin on_tones[tone_count]=tone;tone_count++;end
 task note12(input integer i,input integer pitch_value,duration_value,tone_value,channel_value);begin
  for(integer k=0;k<12;k++)records[i*12+k]=0;
  records[i*12+4]=pitch_value;records[i*12+5]=100;records[i*12+6]=duration_value;records[i*12+7]=duration_value>>8;records[i*12+8]=tone_value;records[i*12+9]=channel_value;
 end endtask
 task begin12(input integer n);begin crc=record_crc(n);request_payload[0]=n;request_payload[1]=n>>8;for(integer k=0;k<4;k++)request_payload[k+2]=crc>>(k*8);request_payload[6]=1;exchange(8'h14,seqno,7,0);seqno++;end endtask
 initial begin
  clocks(4);rst=0;clocks(4);exchange(1,0,0,0);exchange(8'h46,seqno,0,0);seqno++;
  check(response_len==8&&response_payload[2]==26&&response_payload[3]==21&&response_payload[4]==108,"capabilities");
  $readmemh("sim/data/midi_golden.hex",records,0,35);check(record_crc(3)==32'h716d002f,"Java MIDI conversion golden CRC");begin12(3);
  records[2*12+10]=1;data_upload(seqno,0,3,6);seqno++;check(received==0,"invalid reserved field cannot partly write");records[2*12+10]=0;
  data_upload(seqno,0,3,0);data_upload(seqno,0,3,0);seqno++;
  exchange(8'h12,seqno,0,0);seqno++;check(song&&fmt&&received==3,"extended commit and count");
  event_ready=0;prior_count=responses;request(8'h20,seqno,0,0,1);clocks(80);event_ready=1;while(responses==prior_count)clocks(1);seqno++;clocks(300);
  check(tone_count==3&&on_tones[0]==9&&on_tones[1]==8&&on_tones[2]==16&&!legacy,"atomic per-note tone at both melodic limits and drum");
  exchange(8'h21,seqno,0,0);seqno++;exchange(8'h22,seqno,0,0);seqno++;clocks(200);
  check(tone_count==6&&on_tones[3]==9&&on_tones[4]==8&&on_tones[5]==16,"resume retains all timbres");exchange(8'h23,seqno,0,0);seqno++;
  note12(0,54,80,19,9);begin12(1);data_upload(seqno,0,1,6);seqno++;check(received==0,"unsupported drum key rejected");exchange(8'h13,seqno,0,0);
  check(faults==0,"no scheduler deadline fault");$display("PASS tb_midi_protocol checks=%0d",checks);$finish;
 end
 initial begin #200000000;$fatal(1,"midi protocol timeout");end
endmodule
