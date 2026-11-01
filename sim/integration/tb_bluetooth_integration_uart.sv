`timescale 1ns/1ps
`include "touch_keyboard_fixture.svh"
// Real 8N1 pins -> production top/link/CDC/bridge/synth, plus wire NOR.
// UART uses the supported 115200 baud; reference/audio clocks stay real.
// Only the decoded touch snapshot is supplied by the test. No BT event, source
// ownership, player, allocator, library or Flash internals are forced.
module tb_bluetooth_integration_uart;
 localparam integer BAUD=115200,DIV=(50000000+BAUD/2)/BAUD;
 reg clk=0,rst=1,rx=1;always #10 clk=~clk;
 wire tx,cs,sck,mosi,miso;integer programs,erases;
 reg [35:0] pressed=0;tri1 [2:0] scl,sda;wire [2:0] intr;
 reg [72:0] touch=0;reg upd=0;
 integer checks=0,replies=0,n=0,goal=0,seqno=0,watch=0,saved_id=0;
 integer auto_ons=0,auto_offs=0,manual_ons=0,manual_offs=0,flushes=0;
 reg flush_d=0;reg [7:0] response[0:127],payload[0:255];reg [31:0] crc32;
 keyboard_top #(.BT_ENABLE(1),.LCD_ENABLE(0),.TOUCH_ENABLE(1),.LOCK_N(16),.MUTE(1),.FADE(1),
  .ATTACK(2),.DECAY(2),.RELEASE(4),.KEYPAD_BOOT_CYCLES(20),.KEYPAD_POLL_CYCLES(1600),
  .KEYPAD_I2C_HALF(4),.KEYPAD_TIMEOUT_CYCLES(100),.KEYPAD_RETRY_CYCLES(32),.KEYPAD_STALE_CYCLES(80000)) dut(
  .clk(clk),.rst(rst),.bt_rx(rx),.bt_tx(tx),.ultrasonic_echo(1'b0),
  .keypad_scl(scl),.keypad_sda(sda),.keypad_int_n(intr),.ec11_a(3'b111),.ec11_b(3'b111),.ec11_sw_n(3'b111),
  .flash_cs_n(cs),.flash_sck(sck),.flash_mosi(mosi),.flash_miso(miso));
 defparam dut.bluetooth_on.link.BAUD=BAUD;
 defparam dut.bluetooth_on.services.flash.HALF_CYCLES=4;
 defparam dut.bluetooth_on.services.flash.BOOT_CYCLES=8;
 defparam dut.bluetooth_on.services.flash.POLL_CYCLES=8;
 touch_keyboard_fixture keyboard(rst,pressed,12'd0,3'b111,scl,sda,intr);
 spi_nor_model chip(clk,cs,sck,mosi,miso,24'hc84018,1'b0,1'b0,programs,erases);
 function automatic [15:0] cb(input [15:0] c,input [7:0] b);reg [15:0] x;
 begin x=c^{b,8'b0};for(integer k=0;k<8;k++)x=(x<<1)^(x[15]?16'h1021:0);cb=x;end endfunction
 function automatic [31:0] c32(input [31:0] c,input [7:0] b);reg [31:0] x;
 begin x=c^b;for(integer k=0;k<8;k++)x=(x>>1)^(x[0]?32'hedb88320:0);c32=x;end endfunction
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s play=%0d core=%0d bridge=%0d held=%h response=%h",why,dut.bluetooth_on.play_state,dut.bluetooth_on.link.core.state,dut.bluetooth_on.bridge.state,dut.voice_held,response[8]);end endtask
 task cycles(input integer count);repeat(count)@(negedge clk);endtask
 task frames(input integer count);repeat(count)begin @(posedge dut.audio_clk);while(!dut.frame_ce)@(posedge dut.audio_clk);@(negedge dut.audio_clk);end endtask
 task held_count(input integer count);integer j;begin
  j=0;while($countones(dut.voice_held)!=count && j<120)begin frames(1);j++;end
  check($countones(dut.voice_held)==count,$sformatf("expected %0d held voices",count));
 end endtask
 task released_owner;integer j;begin
  j=0;while(dut.take_bt && j<500)begin frames(1);j++;end
  check(!dut.take_bt && dut.voice_held==0,"automatic source releases ownership and all held notes");
 end endtask
 task send(input [7:0] b);begin
  @(negedge clk);rx=0;cycles(DIV);
  for(integer k=0;k<8;k++)begin rx=b[k];cycles(DIV);end
  rx=1;cycles(DIV);
 end endtask
 task command(input [7:0] cmd,input [15:0] seq,input integer len,input [7:0] expected);
 reg [15:0] crc;reg [7:0] b;integer old,ticks;begin
  old=replies;send(8'ha5);send(8'h5a);crc=16'hffff;
  for(integer k=0;k<6+len;k++)begin
   case(k)0:b=1;1:b=cmd;2:b=seq[7:0];3:b=seq[15:8];4:b=len;5:b=len>>8;default:b=payload[k-6];endcase
   send(b);crc=cb(crc,b);
  end
  send(crc[7:0]);send(crc[15:8]);ticks=0;
  while(replies==old && ticks<300000)begin cycles(1);ticks++;end
  check(replies==old+1,"8N1 request produces one framed reply");
  check(response[3]==(cmd|8'h80) && {response[5],response[4]}==seq && response[8]==expected,"UART response command/sequence/status");
  $display("UART cmd=%h seq=%0d status=%h time=%0t",cmd,seq,response[8],$time);cycles(DIV);
 end endtask
 // Independent UART decoder: checks every start/stop bit and response CRC.
 initial forever begin
  reg [7:0] value;reg [15:0] crc;
  @(negedge tx);cycles(DIV/2);check(tx===0,"TX start bit");
  for(integer k=0;k<8;k++)begin cycles(DIV);value[k]=tx;end
  cycles(DIV);check(tx===1,"TX stop bit");response[n]=value;n++;
  if(n==8)goal=10+{response[7],response[6]};
  if(goal>0 && n==goal)begin
   crc=16'hffff;for(integer k=2;k<goal-2;k++)crc=cb(crc,response[k]);
   check(response[0]==8'ha5 && response[1]==8'h5a && response[2]==1,"wire reply prefix and version");
   check({response[goal-1],response[goal-2]}==crc,"wire reply CRC independent calculation");
   replies++;n=0;goal=0;
  end
 end
 task report(input bit down,input integer x,y);begin
  @(negedge dut.audio_clk);touch={~touch[72],~touch[71],16'd800,16'd480,1'b1,1'b0,down,down?4'd1:4'd0,16'(x),16'(y)};upd=1;
  @(negedge dut.audio_clk);upd=0;repeat(5)@(negedge dut.audio_clk);
 end endtask
 task tap(input integer x,y);begin report(0,0,0);report(1,x,y);report(0,0,0);end endtask
 task fresh_manual;integer prior;begin
  prior=manual_ons;pressed=0;frames(6);pressed[0]=1;held_count(1);
  check(manual_ons==prior+1,"fresh physical press resumes manual source exactly once");
  check(!dut.take_bt && dut.key_events.reported_keys[0],"manual adapter bookkeeping agrees with engine after BT");
  pressed=0;held_count(0);frames(8);check(dut.voice_active==0,"fresh manual release terminates voices");
 end endtask
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  flush_d<=dut.bt_flush;if(dut.bt_flush && !flush_d)flushes++;
  if(dut.note_valid && dut.note_ready)begin
   if(dut.note_id<16)begin
    check(dut.take_bt,"automatic event owns the production mux");
    check(dut.bt_pitch==60 || dut.bt_pitch==62 || dut.bt_pitch==64,"automatic pitch survives UART/event CDC/bridge");
    if(dut.note_on)begin auto_ons++;check(dut.bt_velocity==100,"automatic velocity survives to synth");end else auto_offs++;
   end else begin
    if(dut.note_on)manual_ons++;else manual_offs++;
    check(dut.note_id==60,"physical key0 keeps manual ID60");
   end
  end
  if(dut.frame_ce)check(!dut.underrun,"integrated filtered stereo never underruns");
 end
 initial begin
  force dut.touch_audio=touch;force dut.touch_audio_valid=1'b1;force dut.touch_update=upd;
  #100 rst=0;wait(dut.input_ready && dut.keypad_online==7 && dut.keypad_data_valid==7 && dut.bluetooth_on.services.library_init);frames(4);
  check(dut.voice_held==0 && !dut.score_busy && erases==0,"real BT/Flash top boots silent without automatic erase/play");
  command(1,0,0,0);check(response[15]==16 && {response[14],response[13]}==4096,"top HELLO advertises16 automatic voices and4096 notes");
  command(8'h40,1,0,0);check(response[10][2] && {response[17],response[16],response[15]}==24'hc84018,"phone Flash probe uses actual wire-level JEDEC response");
  pressed[0]=1;held_count(1);check(manual_ons==1,"manual physical key plays before phone upload");
  crc32=32'hffffffff;
  for(integer i=0;i<3;i++)begin
   for(integer k=0;k<4;k++)crc32=c32(crc32,0);
   crc32=c32(crc32,8'(60+i*2));crc32=c32(crc32,100);crc32=c32(crc32,5);crc32=c32(crc32,0);
  end
  crc32=~crc32;payload[0]=3;payload[1]=0;for(integer k=0;k<4;k++)payload[2+k]=crc32>>(8*k);
  command(8'h10,2,6,0);held_count(0);check(dut.bt_inhibit && !dut.key_events.reported_keys[0],"UART upload takes ownership and flushes admitted manual key");
  payload[0]=0;payload[1]=0;
  for(integer i=0;i<3;i++)begin
   for(integer k=0;k<4;k++)payload[2+i*8+k]=0;
   payload[6+i*8]=60+i*2;payload[7+i*8]=100;payload[8+i*8]=5;payload[9+i*8]=0;
  end
  command(8'h11,3,26,0);command(8'h12,4,0,0);released_owner();frames(4);
  check(dut.bluetooth_on.song_valid && dut.voice_held==0 && manual_ons==1,"validated upload does not autoplay or resurrect held physical key");
  command(8'h20,5,0,0);held_count(3);
  check(auto_ons==3 && dut.bt_audio_ids==16'h0007,"three phone notes reach distinct production identities");
  command(8'h21,6,0,0);held_count(0);check(dut.bt_inhibit && dut.bluetooth_on.play_state==2,"PAUSE clears notes but retains automatic ownership");
  command(8'h22,7,0,0);held_count(3);check(auto_ons==6,"RESUME restores all chord notes");
  command(8'h23,8,0,0);released_owner();frames(8);
  check(dut.voice_active==0 && dut.bt_audio_ids==0 && manual_ons==1,"STOP all-notes-off drains automatic engine and held physical key stays suppressed");
  fresh_manual();
  // Natural completion also traverses DRAIN/CLEAR and releases the mux.
  command(8'h20,9,0,0);held_count(3);released_owner();frames(8);
  check(auto_ons==9 && auto_offs>=3 && dut.voice_active==0,"natural song completion delivers Offs and silence without STOP");fresh_manual();
  for(integer k=0;k<8;k++)payload[k]=0;
  command(8'h42,10,8,0);saved_id={response[10],response[9]};
  command(8'h42,10,8,0);check(dut.bluetooth_on.services.job_id==saved_id,"duplicate UART SAVE is idempotent");
  command(8'h23,11,0,5); // Storage owns score RAM while the save is active.
  watch=0;while(dut.bluetooth_on.services.library_busy && watch<1000000)begin cycles(1);watch++;end
  check(watch<1000000 && dut.bluetooth_on.services.job_state==2,"asynchronous wire NOR save verifies before success");
  payload[0]=saved_id;payload[1]=saved_id>>8;payload[2]=0;payload[3]=0;
  for(integer k=0;k<4;k++)payload[4+k]=crc32>>(8*k);
  command(8'h45,12,8,0);check(response[11]==2 && response[19]==1,"phone job query reports persistence only after verified Flash commit");
  payload[0]=0;command(8'h41,13,1,0);check(response[10]==1 && {response[12],response[11]}==3,"phone catalog retains uploaded song count");
  @(negedge clk);rst=1;cycles(8);rst=0;
  wait(dut.input_ready && dut.keypad_online==7 && dut.keypad_data_valid==7 && dut.bluetooth_on.services.library_init);frames(4);
  check(!dut.bluetooth_on.song_valid && !dut.gate && dut.bluetooth_on.services.entries==1,"FPGA reset preserves Flash song but clears volatile RAM and never autoplays");
  tap(710,40);tap(350,402);check(dut.menu_mode && dut.more_open,"current touch settings exposes retained song library page");
  tap(650,220);held_count(3);check(dut.bluetooth_on.services.loaded_valid,"touch PLAY loads Flash through local action CDC and the shared player");
  tap(450,270);released_owner();frames(8);check(dut.voice_active==0,"touch STOP clears loaded Flash notes");
  tap(270,320);check(dut.delete_confirm && dut.bluetooth_on.services.entries==1,"first touch DELETE requests confirmation without deleting");
  tap(270,320);wait(dut.bluetooth_on.services.library_busy);wait(!dut.bluetooth_on.services.library_busy);
  check(dut.bluetooth_on.services.entries==0 && chip.forbidden_writes==0,"second touch DELETE atomically removes directory entry without unsafe NOR writes");
  tap(710,40);tap(710,40);check(!dut.menu_mode && !dut.more_open,"song settings return to the manual screen");fresh_manual();
  check(!dut.bluetooth_on.link.overflow && !dut.bluetooth_on.link.framing_fault && !dut.bluetooth_on.link.bad_frame && !dut.bluetooth_on.link.scheduler_fault,"actual integrated UART/player reports no overflow/framing/deadline error");
  check(flushes>=8 && auto_ons==12,"phone/local transitions exercised repeated real engine flushes");
  $display("PASS tb_bluetooth_integration_uart checks=%0d auto_on=%0d auto_off=%0d manual_on=%0d manual_off=%0d flushes=%0d programs=%0d erases=%0d",checks,auto_ons,auto_offs,manual_ons,manual_offs,flushes,programs,erases);$finish;
 end
 initial begin #200000000;$fatal(1,"integrated UART/Flash timeout library=%0d",dut.bluetooth_on.services.song_library.state);end
endmodule
