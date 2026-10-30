`timescale 1ns/1ps
// Byte-framed phone -> actual core/services -> wire-level U7 -> reset recovery
// -> actual more-action CDC/local controller -> same player/32-voice engine.
module tb_performance_top;
 parameter integer REGISTER_LOCKS=0,PITCH_BASE=60,NOR_VENDOR=0;
 localparam [23:0] NOR_ID=NOR_VENDOR?24'hc84018:24'hef4018;
 reg clk=0,rst=1,rv=0,ui_valid=0;reg [7:0] rb=0;reg [6:0] ui_action=63;
 always #10 clk=~clk;
 wire rr,cs,sck,mosi,miso;integer programs,erases;
 integer checks=0,replies=0,n=0,goal=0,pseq=1,saved_id=0,watch=0;
 reg [7:0] response[0:31],payload[0:255];reg [31:0] crc32;
 keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.LOCK_N(16),
 .MUTE(1),.FADE(1),.ATTACK(2),.DECAY(2),.RELEASE(2)) dut(
 .clk(clk),.rst(rst),.bt_rx(1'b1),.board_buttons_n(4'hf),.keypad_int_n(3'b111),.ec11_a(3'b111),.ec11_b(3'b111),.ec11_sw_n(3'b111),
 .flash_cs_n(cs),.flash_sck(sck),.flash_mosi(mosi),.flash_miso(miso));
 defparam dut.bluetooth_on.services.flash.HALF_CYCLES=4;
 defparam dut.bluetooth_on.services.flash.BOOT_CYCLES=8;
 defparam dut.bluetooth_on.services.flash.POLL_CYCLES=8;
 spi_nor_model #(.BYTES('h222000)) chip(clk,cs,sck,mosi,miso,NOR_ID,1'b0,1'b0,programs,erases);
 assign rr=dut.bluetooth_on.link.core.rx_ready;
 function automatic [15:0] cb(input [15:0] c,input [7:0] b);reg [15:0] x;
 begin x=c^{b,8'b0};for(integer k=0;k<8;k++)x=(x<<1)^(x[15]?16'h1021:0);cb=x;end endfunction
 function automatic [31:0] c32(input [31:0] c,input [7:0] b);reg [31:0] x;
 begin x=c^b;for(integer k=0;k<8;k++)x=(x>>1)^(x[0]?32'hedb88320:0);c32=x;end endfunction
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s cmd=%h seq=%0d core=%0d library=%0d reply=%h perf=%0d flags=%b map=%h",why,dut.bluetooth_on.link.core.cmd,dut.bluetooth_on.link.core.seq,dut.bluetooth_on.link.core.state,dut.bluetooth_on.services.song_library.state,response[8],dut.performance.rec_state,dut.bluetooth_on.perf_flags_audio,dut.map_status_audio);end endtask
 task cycles(input integer count);repeat(count)@(negedge clk);endtask
 task send(input [7:0] b);begin @(negedge clk);while(!rr)@(negedge clk);rv=1;rb=b;@(negedge clk);rv=0;end endtask
 task command(input [7:0] cmd,input [15:0] seq,input integer len,input [7:0] expected);
 reg [15:0] crc;reg [7:0] b;integer old,ticks;begin
  old=replies;send(8'ha5);send(8'h5a);crc=16'hffff;
  for(integer k=0;k<6+len;k++)begin
   case(k)0:b=1;1:b=cmd;2:b=seq[7:0];3:b=seq[15:8];4:b=len;5:b=0;default:b=payload[k-6];endcase
   send(b);crc=cb(crc,b);
  end
  send(crc[7:0]);send(crc[15:8]);ticks=0;
  while(replies==old && ticks<100000)begin cycles(1);ticks++;end
  check(replies==old+1 && response[8]==expected,"framed command response");cycles(2);
 end endtask
 task job_payload;begin payload[0]=saved_id;payload[1]=saved_id>>8;payload[2]=0;payload[3]=0;
  for(integer k=0;k<4;k++)payload[4+k]=crc32>>(8*k);
 end endtask
 task ui(input [6:0] action);begin
  @(negedge dut.audio_clk);ui_action=action;ui_valid=1;@(negedge dut.audio_clk);ui_valid=0;repeat(10)@(negedge dut.audio_clk);
 end endtask
 always @(posedge clk)if(!dut.bluetooth_on.source_reset && dut.bluetooth_on.link.core.tx_valid)begin
  response[n]=dut.bluetooth_on.link.core.tx_data;n++;
  if(n==8)goal=10+{response[7],response[6]};
  if(goal>0 && n==goal)begin replies++;n=0;goal=0;end
 end
 reg [7:0] record_data[0:191];reg [25:0] tones_seen=0;integer accepted=0;reg [31:0] note_crc;
 always @(posedge dut.audio_clk)if(!dut.audio_reset&&dut.bt_valid&&dut.bt_ready&&dut.bt_note_on)begin
  accepted++;check(dut.bt_timbre<=25,"complete five-bit bridge payload");tones_seen[dut.bt_timbre]<=1;
 end

 reg [35:0] physical=0;reg [575:0] wanted;reg [31:0] map_crc;integer old_accepts;reg [31:0] captured_id;
 task rpc(input [7:0] c,input integer len,input [7:0] expected);begin command(c,pseq,len,expected);pseq++;end endtask
 task wait_manual(input integer count);integer watchdog;begin watchdog=0;while(dut.performance.count<count && watchdog<10000)begin @(negedge dut.audio_clk);watchdog++;end check(dut.performance.count==count,"manual event captured");end endtask
 initial begin
  force dut.bluetooth_on.link.core.rx_valid=rv;force dut.bluetooth_on.link.core.rx_data=rb;force dut.bluetooth_on.link.core.tx_ready=1'b1;
  force dut.keys=physical;force dut.note_keys=physical;
  force dut.ui_action_valid=ui_valid;force dut.ui_action=ui_action;
  #100 rst=0;wait(dut.input_ready && dut.map_status_audio[28]);cycles(30);
  command(1,0,0,0);rpc('h50,0,0);check(response[10]==36,"feature capability CDC");
  wanted=dut.performance_map;wanted[15:0]={8'd9,8'd21};wanted[31:16]={8'd15,8'd21};wanted[575:560]={8'd31,8'd108};
  map_crc='1;for(integer j=0;j<72;j++)map_crc=c32(map_crc,wanted[j*8+:8]);map_crc=~map_crc;
  for(integer b=0;b<4;b++)begin payload[b]=32'd42>>(b*8);payload[4+b]=map_crc>>(b*8);end rpc('h52,8,0);
  for(integer j=0;j<36;j++)begin payload[0]=42;payload[1]=0;payload[2]=0;payload[3]=0;payload[4]=j;payload[5]=wanted[j*16+:8];payload[6]=wanted[j*16+8+:8];rpc('h53,7,0);end
  payload[0]=42;payload[1]=0;payload[2]=0;payload[3]=0;rpc('h54,4,0);check(dut.performance_map==wanted,"atomic map across CDC");
  for(integer b=0;b<4;b++)payload[b]=map_crc>>(b*8);rpc('h55,4,0);saved_id={response[10],response[9]};
  // Manual onset and release must remain live during the configuration erase.
  @(negedge dut.audio_clk);physical=36'h800000000;wait(dut.key_gate);repeat(4)@(posedge dut.frame_ce);
  check(dut.map_boot_ready && !dut.map_status_audio[28] && $countones(dut.voice_held)==1,"manual onset during Flash save");
  @(negedge dut.audio_clk);physical=0;wait(!dut.key_gate);check(dut.bluetooth_on.services.keymap_status[17:16]==1,"release accepted before Flash save completes");
  wait(dut.bluetooth_on.services.keymap_status[17:16]==2);cycles(30);rpc('h56,0,0);check(response[11]==2 && {response[10],response[9]}==saved_id,"SPI save job verified");
  check(programs==2 && erases==1,"only config body and commit written");
  #40 rst=1;cycles(5);rst=0;wait(dut.input_ready && dut.map_status_audio[28]);cycles(30);check(dut.performance_map==wanted,"real SPI reboot map load");check(programs==2,"boot no writes");
  command(1,0,0,0);pseq=1;rpc('h61,0,0);captured_id={response[12],response[11],response[10],response[9]};
  payload[0]=1;payload[1]=0;for(integer b=2;b<6;b++)payload[b]=0;rpc('h10,6,5);rpc('h57,0,5);
  @(negedge dut.audio_clk);physical=3;wait_manual(2);repeat(4)@(posedge dut.frame_ce);
  check($countones(dut.voice_held)==2,"same pitch physical keys independent");check(dut.visual_notes[1:0]==3,"physical key highlights");
  check(dut.key_pitch==21,"mapped pitch reaches synth");
  @(negedge dut.audio_clk);physical=2;repeat(8)@(posedge dut.frame_ce);check($countones(dut.voice_held)==1,"one physical release leaves other held");check(dut.visual_notes[1:0]==2,"physical release highlight");
  @(negedge dut.audio_clk);physical=0;repeat(4)@(posedge dut.frame_ce);rpc('h62,0,0);wait(dut.performance.rec_state==5);
  rpc('h63,0,0);check({response[15],response[14]}==2,"capture count through protocol");
  for(integer b=0;b<4;b++)payload[b]=captured_id>>(b*8);payload[4]=0;payload[5]=0;rpc('h64,6,0);check(response[24]==21 && response[26]==9 && response[27]==0,"mapped event capture payload");
  command('h64,pseq-1,6,0);check(response[26]==9,"read retransmit cached");
  payload[4]=1;rpc('h64,6,0);check(response[24]==21 && response[26]==15 && response[27]==1,"independent same pitch timbre capture");
  // Local touch commands use the unchanged MORE page control router.
  ui(7);ui(21);ui(96);ui(96);wait(dut.performance.rec_state==1);ui(97);wait(dut.performance.rec_state==5);
  check(!dut.underrun && !dut.bluetooth_on.link.scheduler_fault,"production audio budget maintained");
  $display("PASS tb_performance_top checks=%0d (framing/CDC/SPI/reset/mapping/record/UI/audio)",checks);$finish;
 end
 initial begin #150000000;$fatal(1,"performance integration timeout");end
endmodule
