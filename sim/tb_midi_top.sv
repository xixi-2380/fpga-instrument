`timescale 1ns/1ps
// Byte-framed phone -> actual core/services -> wire-level U7 -> reset recovery
// -> actual more-action CDC/local controller -> same player/32-voice engine.
module tb_midi_top;
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
 spi_nor_model chip(clk,cs,sck,mosi,miso,NOR_ID,1'b0,1'b0,programs,erases);
 assign rr=dut.bluetooth_on.link.core.rx_ready;
 function automatic [15:0] cb(input [15:0] c,input [7:0] b);reg [15:0] x;
 begin x=c^{b,8'b0};for(integer k=0;k<8;k++)x=(x<<1)^(x[15]?16'h1021:0);cb=x;end endfunction
 function automatic [31:0] c32(input [31:0] c,input [7:0] b);reg [31:0] x;
 begin x=c^b;for(integer k=0;k<8;k++)x=(x>>1)^(x[0]?32'hedb88320:0);c32=x;end endfunction
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s core=%0d library=%0d reply=%h",why,dut.bluetooth_on.link.core.state,dut.bluetooth_on.services.song_library.state,response[8]);end endtask
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
 initial begin
  force dut.bluetooth_on.link.core.rx_valid=rv;force dut.bluetooth_on.link.core.rx_data=rb;force dut.bluetooth_on.link.core.tx_ready=1'b1;
  force dut.ui_action_valid=ui_valid;force dut.ui_action=ui_action;
  #100 rst=0;wait(dut.input_ready&&dut.bluetooth_on.services.library_init);cycles(20);
  command(1,0,0,0);command(8'h46,pseq,0,0);pseq++;
  note_crc=32'hffffffff;
  for(integer i=0;i<16;i++)begin
   for(integer b=0;b<12;b++)record_data[i*12+b]=0;
   record_data[i*12+4]=60;record_data[i*12+5]=100;record_data[i*12+6]=100;record_data[i*12+8]=i;record_data[i*12+9]=0;
   for(integer b=0;b<12;b++)note_crc=c32(note_crc,record_data[i*12+b]);
  end
  crc32=~note_crc;payload[0]=16;payload[1]=0;for(integer b=0;b<4;b++)payload[2+b]=crc32>>(b*8);payload[6]=1;
  command(8'h14,pseq,7,0);pseq++;payload[0]=0;payload[1]=0;for(integer b=0;b<192;b++)payload[2+b]=record_data[b];
  command(8'h11,pseq,194,0);pseq++;command(8'h12,pseq,0,0);pseq++;command(8'h20,pseq,0,0);pseq++;
  wait(accepted==16);repeat(2)@(negedge dut.audio_clk);check(tones_seen[15:0]==16'hffff,"all sixteen timbres crossed reference/audio CDC");
  repeat(8)@(posedge dut.frame_ce);check($countones(dut.voice_held)==16,"sixteen independent physical identities");
  for(integer i=0;i<16;i++)check(dut.sound.voice_timbres[i*5+:5]==i,"physical context retains exact instrument");
  command(8'h21,pseq,0,0);pseq++;check(dut.voice_held==0,"pause clears physical sound");command(8'h22,pseq,0,0);pseq++;
  wait(accepted==32);command(8'h23,pseq,0,0);pseq++;check(!dut.bt_inhibit,"stop returns manual control");
  check(!dut.underrun&&!dut.bluetooth_on.link.scheduler_fault,"production scheduler and renderer keep up");
  note_crc=32'hffffffff;
  for(integer i=0;i<3;i++)begin
   for(integer b=0;b<12;b++)record_data[i*12+b]=0;
   record_data[i*12+4]=i==0?36:i==1?49:51;record_data[i*12+5]=100;
   record_data[i*12+6]=(i==0?250:i==1?1500:1000)%256;record_data[i*12+7]=(i==0?250:i==1?1500:1000)/256;
   record_data[i*12+8]=i==0?16:i==1?24:25;record_data[i*12+9]=9;
   for(integer b=0;b<12;b++)note_crc=c32(note_crc,record_data[i*12+b]);
  end
  crc32=~note_crc;payload[0]=3;payload[1]=0;for(integer b=0;b<4;b++)payload[2+b]=crc32>>(b*8);payload[6]=1;
  command(8'h14,pseq,7,0);pseq++;payload[0]=0;payload[1]=0;for(integer b=0;b<36;b++)payload[b+2]=record_data[b];
  command(8'h11,pseq,38,0);pseq++;command(8'h12,pseq,0,0);pseq++;command(8'h20,pseq,0,0);pseq++;
  wait(accepted==35);repeat(2)@(negedge dut.audio_clk);check(tones_seen[16]&&tones_seen[24]&&tones_seen[25],"drum IDs preserve fifth bit across CDC and bridge");
  repeat(4)@(posedge dut.frame_ce);check(dut.sound.voice_timbres[0+:5]==16&&dut.sound.voice_timbres[5+:5]==24&&dut.sound.voice_timbres[10+:5]==25,"drum contexts reach native envelopes");
  command(8'h23,pseq,0,0);
  $display("PASS tb_midi_top checks=%0d accepted=%0d",checks,accepted);$finish;
 end
 initial begin #100000000;$fatal(1,"midi top timeout");end
endmodule
