`timescale 1ns/1ps
// Byte-framed phone -> actual core/services -> wire-level U7 -> reset recovery
// -> actual more-action CDC/local controller -> same player/32-voice engine.
module tb_bt_library_link;
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
 initial begin
  if(REGISTER_LOCKS)begin chip.sr1_flags=8'he0;chip.sr2_flags=8'h3b;chip.sr3_flags=8'h60;end
  force dut.bluetooth_on.link.core.rx_valid=rv;force dut.bluetooth_on.link.core.rx_data=rb;force dut.bluetooth_on.link.core.tx_ready=1'b1;
  force dut.ui_action_valid=ui_valid;force dut.ui_action=ui_action;
  #100 rst=0;wait(dut.input_ready && dut.bluetooth_on.services.library_init);cycles(20);
  check(!dut.gate && erases==0,"boot probes/scans only; no autoplay or automatic erase");
  command(1,0,0,0);check(response[15]==16 && {response[14],response[13]}==4096,"production HELLO reports16/4096");
  command(8'h40,1,0,0);check(response[10][2] && {response[17],response[16],response[15]}==NOR_ID,"fresh SPI identity enables standard NOR access");
  check(response[17]==NOR_ID[23:16],"reported manufacturer remains unmodified");
  for(integer i=0;i<3;i++)begin
   for(integer k=0;k<4;k++)payload[2+i*8+k]=0;
   payload[6+i*8]=PITCH_BASE+i*2;payload[7+i*8]=100;payload[8+i*8]=5;payload[9+i*8]=0;
  end
  crc32=32'hffffffff;for(integer i=2;i<26;i++)crc32=c32(crc32,payload[i]);crc32=~crc32;
  payload[0]=3;payload[1]=0;for(integer k=0;k<4;k++)payload[2+k]=crc32>>(8*k);
  command(8'h10,2,6,0);
  payload[0]=0;payload[1]=0;
  for(integer i=0;i<3;i++)begin
   for(integer k=0;k<4;k++)payload[2+i*8+k]=0;
   payload[6+i*8]=PITCH_BASE+i*2;payload[7+i*8]=100;payload[8+i*8]=5;payload[9+i*8]=0;
  end
  command(8'h11,3,26,0);command(8'h12,4,0,0);
  for(integer k=0;k<8;k++)payload[k]=0;
  command(8'h42,5,8,0);saved_id={response[10],response[9]};
  command(8'h42,5,8,0);check(dut.bluetooth_on.services.job_id==saved_id,"duplicate SAVE starts exactly one job");
  command(8'h23,6,0,5); // Phone cannot interrupt storage ownership.
  command(1,0,0,0);pseq=1;job_payload();
  while(watch<1000)begin
   command(8'h45,pseq,8,0);pseq++;
   if(response[11]==2)begin check(response[19]==1,"persistent success only after payload+directory verification");break;end
   check(response[11]==1 && response[19]==0,"pending task cannot claim persistence");cycles(1000);watch++;
  end
  check(watch<1000,"Flash save completes asynchronously");payload[0]=0;command(8'h41,pseq,1,0);
  check(response[10]==1 && {response[12],response[11]}==3,"catalog query reads committed directory metadata");
  @(negedge clk);rst=1;cycles(8);rst=0;wait(dut.input_ready && dut.bluetooth_on.services.library_init);cycles(100);
  check(!dut.bluetooth_on.song_valid && !dut.gate && dut.bluetooth_on.services.entries==1,"reset preserves Flash library, not RAM/autoplay");
  force dut.menu_mode=1'b1;ui(21);check(dut.more_open,"single settings more action opens page");
  ui(25);wait(dut.gate);check($countones(dut.voice_held)>0,"local more PLAY loads persistent score without HELLO/phone");
  wait($countones(dut.voice_held)==3);check(dut.bluetooth_on.services.loaded_valid,"same shared player handles all three loaded notes");
  ui(28);wait(!dut.bt_inhibit);check(!dut.gate,"local STOP clears automatic ownership");
  ui(31);check(dut.delete_confirm && dut.bluetooth_on.services.entries==1,"first DELETE only asks confirmation");
  ui(31);wait(dut.bluetooth_on.services.library_busy);wait(!dut.bluetooth_on.services.library_busy);
  check(dut.bluetooth_on.services.entries==0,"confirmed local DELETE commits directory transaction");
  ui(22);check(!dut.more_open,"BACK returns to original settings");release dut.menu_mode;
  $display("PASS tb_bt_library_link checks=%0d programs=%0d erases=%0d",checks,programs,erases);$finish;
 end
 initial begin #50000000;$fatal(1,"service chain timeout state=%0d",dut.bluetooth_on.services.song_library.state);end
endmodule
