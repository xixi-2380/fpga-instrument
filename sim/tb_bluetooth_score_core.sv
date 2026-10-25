`timescale 1ns/1ps
module tb_bluetooth_score_core;
 parameter integer CLOCK_HZ=1000000,VOICES=4,MAX_NOTES=1024;
 localparam integer MS=CLOCK_HZ/1000;
 reg clk=0,rst=1,rx_valid=0,rx_fault=0,event_ready=1;
 reg [7:0] rx_data=0;wire rx_ready,tx_valid;wire [7:0] tx_data;
 reg [15:0] lfsr=16'h347a;wire tx_ready=lfsr[0]||lfsr[2];
 wire ev,song,upload,inhibit,bad_frame,fault;wire [1:0] kind,play;wire [6:0] id,pitch,velocity;wire [31:0] position;wire [7:0] error_code;wire [15:0] received,total;
 always #5 clk=~clk;
 bluetooth_score_core #(.CLOCK_HZ(CLOCK_HZ),.MAX_NOTES(MAX_NOTES),.MAX_VOICES(VOICES),.UPLOAD_TIMEOUT_MS(20),.GAP_TIMEOUT_MS(2),.FRAME_TIMEOUT_MS(10)) dut(
  .clk(clk),.rst(rst),.rx_valid(rx_valid),.rx_data(rx_data),.rx_ready(rx_ready),.rx_fault(rx_fault),
  .tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready),.event_valid(ev),.event_ready(event_ready),
  .event_kind(kind),.event_id(id),.event_pitch(pitch),.event_velocity(velocity),.song_valid(song),.upload_active(upload),
  .play_state(play),.position_ms(position),.manual_inhibit(inhibit),.last_error(error_code),.received_notes(received),.total_notes(total),
  .bad_frame(bad_frame),.scheduler_fault(fault),.local_valid(1'b0),.local_command(2'd0),.storage_lock(1'b0));
 integer checks=0,responses=0,reply_count=0,reply_goal=0,on_count=0,off_count=0,silences=0,faults=0;
 reg [7:0] response_bytes[0:63],response_payload[0:19];reg [7:0] response_cmd;reg [15:0] response_seq;integer response_len;
 reg [1:0] event_types[0:4095];reg [6:0] event_ids[0:4095],event_pitches[0:4095];reg [31:0] event_times[0:4095];integer event_count=0;
 integer max_wait_cycles=0;
 reg held=0;reg [22:0] held_event;
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
  if(!rst&&held)check(ev&&{kind,id,pitch,velocity}===held_event,"stalled event payload remains stable");
  held<=!rst&&ev&&!event_ready;held_event<={kind,id,pitch,velocity};
  if(!rst&&ev&&event_ready)begin
   event_types[event_count]=kind;event_ids[event_count]=id;event_pitches[event_count]=pitch;event_times[event_count]=position;event_count++;
   case(kind)0:off_count++;1:begin on_count++;check(velocity>=1&&velocity<=127,"event velocity preserved");end 2:silences++;default:$fatal(1,"bad event kind");endcase
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
 reg [7:0] request_payload[0:255];reg [7:0] records[0:MAX_NOTES*8-1];integer record_bytes;
 function automatic [31:0] record_crc(input integer n);
  reg [31:0] c;begin c=32'hffffffff;for(integer k=0;k<n*8;k++)c=crc32_byte(c,records[k]);record_crc=c^32'hffffffff;end
 endfunction
 task record(input integer index,input [31:0] start,input [7:0] note,vel,input [15:0] duration);
  begin for(integer k=0;k<4;k++)records[index*8+k]=start>>(8*k);records[index*8+4]=note;records[index*8+5]=vel;records[index*8+6]=duration[7:0];records[index*8+7]=duration[15:8];end
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
   check(responses==old+1,"response before 500ms budget");check(response_cmd==(cmd|8'h80)&&response_seq==seq&&response_payload[0]==status,"response identity/status");
  end
 endtask
 task begin_upload(input integer seq,n,input [31:0] crc,input [7:0] status);
  begin request_payload[0]=n&255;request_payload[1]=n>>8;for(integer k=0;k<4;k++)request_payload[k+2]=crc>>(8*k);exchange(8'h10,seq,6,status);end
 endtask
 task data_upload(input integer seq,index,n,input [7:0] status);
  begin request_payload[0]=index&255;request_payload[1]=index>>8;for(integer k=0;k<n*8;k++)request_payload[k+2]=records[index*8+k];exchange(8'h11,seq,2+n*8,status);end
 endtask
 integer old,old_on,saved_events;reg [31:0] frozen;reg [31:0] golden_crc;
 initial begin
  clocks(4);rst=0;clocks(4);
  exchange(1,0,0,0);check(response_len==20&&response_payload[7]==VOICES&&{response_payload[6],response_payload[5]}==MAX_NOTES,"HELLO actual parameter capability");
  exchange(8'h20,1,0,8'h0e);
  old=responses;request(8'h23,2,0,1,1);clocks(100);check(responses==old,"bad CRC is silent");exchange(8'h23,2,0,0);
  record(0,0,60,100,450);record(1,500,62,100,450);record(2,1000,64,100,900);golden_crc=record_crc(3);check(golden_crc==32'h7539bd9a,"three-note CRC golden");
  begin_upload(3,3,golden_crc,0);check(upload&&!song&&received==0&&inhibit,"BEGIN atomic invalidation and manual inhibit");
  records[5]=0;data_upload(4,0,3,6);check(received==0,"bad DATA no partial count");records[5]=100;
  data_upload(5,0,3,0);check(received==3,"DATA accepted");data_upload(5,0,3,0);check(received==3,"duplicate DATA not double written");
  request_payload[2]^=1;exchange(8'h11,5,26,8'h0b);exchange(8'h12,6,0,0);check(song&&!upload&&response_len==5&&{response_payload[4],response_payload[3],response_payload[2],response_payload[1]}==1900,"COMMIT time/CRC and state");
  exchange(8'h12,6,0,0);exchange(8'h30,99,0,8'h0b);
  old_on=on_count;exchange(8'h20,7,0,0);clocks(50);check(on_count==old_on+1&&play==1,"PLAY first note");exchange(8'h20,7,0,0);check(on_count==old_on+1,"duplicate PLAY not retriggered");
  clocks(100*MS);exchange(8'h21,8,0,0);frozen=position;old_on=on_count;clocks(75*MS);check(play==2&&position==frozen&&on_count==old_on,"PAUSE freezes and suppresses events");
  exchange(8'h30,9,0,0);check(response_payload[3]==2,"status PAUSE");exchange(8'h22,10,0,0);check(on_count==old_on+1,"RESUME retriggers retained active record");
  clocks(420*MS);check(on_count>=old_on+2,"second note follows resumed musical time");exchange(8'h23,11,0,0);check(play==0&&position==0&&!inhibit,"STOP returns manual with zero position");
  begin_upload(12,3,golden_crc,0);clocks(22*MS);check(!upload&&!song&&received==0&&error_code==8'h0c,"upload timeout invalidates partial song");
  exchange(1,0,0,0);check(error_code==0,"HELLO clears last_error");
  begin_upload(1,1,0,0);data_upload(2,0,1,0);exchange(8'h12,3,0,9);check(!song&&!upload&&total==0,"bad score CRC invalidates upload");
  // Five simultaneous records exceed four voices (or VOICES+1 for boundary run).
  for(integer k=0;k<VOICES+1;k++)record(k,0,60+k,100,10);
  begin_upload(4,VOICES+1,record_crc(VOICES+1),0);data_upload(5,0,VOICES+1,0);exchange(8'h12,6,0,8'h0a);check(!song&&!upload,"COMMIT overlap rejected");
  // Same pitch overlap has independent IDs. At t=10 Off precedes new On.
  record(0,0,60,80,10);record(1,5,60,90,10);record(2,10,64,100,5);
  begin_upload(7,3,record_crc(3),0);data_upload(8,0,3,0);exchange(8'h12,9,0,0);
  begin_upload(10,MAX_NOTES+1,0,8);check(song,"rejected BEGIN preserves old valid song");
  saved_events=event_count;exchange(8'h20,11,0,0);clocks(18*MS);check(play==0&&position==15&&!inhibit,"natural end retains duration and returns manual");
  begin
   integer first_id,second_id,off_at10,on_at10;first_id=-1;second_id=-1;off_at10=-1;on_at10=-1;
   for(integer k=saved_events;k<event_count;k++)begin
    if(event_types[k]==1&&event_times[k]==0)first_id=event_ids[k];
    if(event_types[k]==1&&event_times[k]==5)second_id=event_ids[k];
    if(event_types[k]==0&&event_times[k]==10)off_at10=k;
    if(event_types[k]==1&&event_times[k]==10)on_at10=k;
   end
   check(first_id>=0&&second_id>=0&&first_id!=second_id,"overlapping same pitch identity separate");check(off_at10>=0&&on_at10>off_at10,"same ms releases before starts");
  end
  // Reset/HELLO preserves committed song but cancels incomplete upload.
  exchange(1,0,0,0);check(song,"HELLO keeps valid score");begin_upload(1,1,0,0);exchange(1,0,0,0);check(!upload&&!song,"HELLO aborts unfinished upload");
  // Whole-packet atomicity: second record invalid must not write first.
  record(0,0,60,100,5);record(1,5,61,0,5);begin_upload(1,2,0,0);data_upload(2,0,2,6);check(received==0&&dut.score_crc==32'hffffffff,"atomic packet validation and CRC");exchange(8'h13,3,0,0);
  // Exhaustive RAM address boundary and 64 packets.
  for(integer k=0;k<MAX_NOTES;k++)record(k,k*2,60,100,1);
  begin_upload(4,MAX_NOTES,record_crc(MAX_NOTES),0);
  for(integer k=0;k<MAX_NOTES;k+=16)data_upload(5+k/16,k,(MAX_NOTES-k<16)?MAX_NOTES-k:16,0);
  exchange(8'h12,5+(MAX_NOTES+15)/16,0,0);check(song&&received==MAX_NOTES&&duration_value()==MAX_NOTES*2-1,"full RAM capacity and COMMIT");
  // Correctly framed unsupported version must not mutate sequence/error state.
  exchange(1,0,0,0);old=responses;request(8'h23,1,0,0,2);while(responses==old)clocks(1);check(response_payload[0]==2&&error_code==0&&dut.expected_seq==1,"BAD_VERSION has no side effects");
  // Parser recovers after interrupted frame, FIFO fault and embedded SOF bytes.
  byte_send(8'ha5);byte_send(8'h5a);byte_send(1);clocks(4*MS);exchange(8'h30,1,0,0);
  byte_send(8'ha5);byte_send(8'h5a);rx_fault=1;clocks(1);rx_fault=0;exchange(8'h30,2,0,0);
  // Full 256-byte payload, embedded A5/5A and repeated SOF prefix must stay framed.
  for(integer k=0;k<256;k++)request_payload[k]=(k%2)?8'h5a:8'ha5;
  byte_send(8'ha5);exchange(8'h7f,3,256,1);check(dut.expected_seq==4,"max payload consumed once with embedded SOF");
  exchange(8'h7f,3,256,1);check(dut.expected_seq==4,"max payload exact duplicate cached");
  // Oversized declared length is discarded without consuming request sequence.
  old=responses;byte_send(8'ha5);byte_send(8'h5a);byte_send(1);byte_send(8'h30);byte_send(4);byte_send(0);byte_send(1);byte_send(1);
  clocks(10);check(responses==old&&dut.expected_seq==4,"oversize is silent and atomic");exchange(8'h30,4,0,0);
  dut.expected_seq=17'd65535;exchange(8'h30,16'hffff,0,0);exchange(8'h30,16'hffff,0,0);exchange(8'h30,0,0,8'h0b);check(dut.expected_seq==17'd65536,"sequence exhaustion does not wrap");exchange(1,0,0,0);
  check(faults==0,"no scheduler deadline errors with ready consumer");
  // Hold an ON event: payload cannot move, and missed scheduling is flagged.
  record(0,0,60,100,10);begin_upload(1,1,record_crc(1),0);data_upload(2,0,1,0);exchange(8'h12,3,0,0);
  exchange(8'h20,4,0,0);clocks(30); // Start event may already have passed; stall the due Off.
  event_ready=0;clocks(13*MS);event_ready=1;clocks(2*MS);check(faults>0&&play==0&&error_code==8'h0d,"backpressure deadline fault flushes and stops");
  rst=1;clocks(3);rst=0;clocks(10);check(!song&&!upload&&play==0&&error_code==0,"reset invalidates RAM metadata");
  exchange(1,0,0,0);exchange(8'h40,1,0,1);exchange(8'h30,2,0,0);
  check(dut.expected_seq==3,"bare v1 core rejects absent extension and keeps session usable");
  $display("PASS tb_bluetooth_score_core checks=%0d responses=%0d events=%0d max_wait_cycles=%0d",checks,responses,event_count,max_wait_cycles);$finish;
 end
 function automatic [31:0] duration_value;duration_value={response_payload[4],response_payload[3],response_payload[2],response_payload[1]};endfunction
 initial begin #100000000000;$fatal(1,"watchdog");end
endmodule
