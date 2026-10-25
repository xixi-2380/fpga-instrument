`timescale 1ns/1ps
`include "passive_matrix_model.svh"
module tb_bt_score_audio;
 reg clk=0,rst=1,rv=0;reg [7:0] rb=0;always #10 clk=~clk;
 wire rr;integer checks=0,replies=0,n=0,goal=0,ons=0,offs=0,clears=0;
 reg [7:0] response[0:31],payload[0:255];
 reg [15:0] pressed=0;tri [3:0] columns;wire [3:0] rows,selected;
 for(genvar k=0;k<4;k=k+1)assign selected[k]=(columns[k]===1'b0);
 passive_matrix_model keyboard(pressed,selected,rows);
 reg [31:0] held_position;
 // Functional acceleration only: 1 logical ms=1000 ref cycles;
 // one render voice and128-cycle I2S frame retain deadline headroom.
 keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.SCORE_ENABLE(0),
 .SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2),
 .LOCK_N(16),.MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.RELEASE(2)) dut(
 .clk(clk),.rst(rst),.bt_rx(1'b1),.board_buttons_n(4'hf),.key_row(rows),.key_col(columns));
 defparam dut.bluetooth_on.link.CLOCK_HZ=1000000;
 defparam dut.sound.VOICES=1;
 defparam dut.sound.timing.HALF_CYCLES=2;
 assign rr=dut.bluetooth_on.link.core.rx_ready;
 function automatic [15:0] crc(input [15:0] prev,input [7:0] b);
 reg [15:0] x;begin x=prev^{b,8'b0};for(integer i=0;i<8;i++)x=(x<<1)^(x[15]?16'h1021:0);crc=x;end endfunction
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task cycles(input integer k);repeat(k)@(negedge clk);endtask
 task send(input [7:0] b);begin @(negedge clk);while(!rr)@(negedge clk);rv=1;rb=b;@(negedge clk);rv=0;end endtask
 task command(input [7:0] cmd,input [15:0] seq,input integer len);
 reg [15:0] sum;reg [7:0] b;integer previous;begin
  previous=replies;send(8'ha5);send(8'h5a);sum=16'hffff;
  for(integer i=0;i<6+len;i++)begin
   case(i)0:b=1;1:b=cmd;2:b=seq[7:0];3:b=seq[15:8];4:b=len;5:b=0;default:b=payload[i-6];endcase
   send(b);sum=crc(sum,b);
  end
  send(sum[7:0]);send(sum[15:8]);wait(replies>previous);cycles(2);
  check(response[8]==0 && response[3]==(cmd|8'h80),"actual protocol command succeeds through audio acknowledgement");
 end endtask
 task note(input integer i,input [31:0] t,input [7:0] pitch,input [15:0] duration);
 begin
  for(integer j=0;j<4;j++)payload[2+8*i+j]=t>>(j*8);
  payload[6+8*i]=pitch;payload[7+8*i]=100;payload[8+8*i]=duration[7:0];payload[9+8*i]=duration[15:8];
 end endtask
 always @(posedge clk)if(!dut.bluetooth_on.source_reset && dut.bluetooth_on.link.core.tx_valid)begin
  response[n]=dut.bluetooth_on.link.core.tx_data;n++;
  if(n==8)goal=10+{response[7],response[6]};
  if(goal>0 && n==goal)begin replies++;n=0;goal=0;end
 end
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  if(dut.bt_valid && dut.bt_ready)begin
   if(dut.bt_note_on)ons++;else offs++;
  end
  if(dut.bluetooth_on.ev_valid && dut.bluetooth_on.ev_ready && dut.bluetooth_on.kind>=2)begin
   clears++;check(dut.voice_held==0 && dut.voice_active==0 && dut.sound.tx.latched_l==0 && dut.sound.tx.latched_r==0,
    "protocol silence ack waits for actual zeroed synth and I2S");
  end
  check(!dut.underrun,"no buffer underrun across command/CDC/volume");
 end
 initial begin
  force dut.bluetooth_on.link.core.rx_valid=rv;force dut.bluetooth_on.link.core.rx_data=rb;
  force dut.bluetooth_on.link.core.tx_ready=1'b1;
  #100 rst=0;wait(dut.input_ready);cycles(100);
  wait(!dut.inhibit_notes);pressed=16'h0200;wait(dut.gate);
  command(1,0,0);check(response[15]==1,"HELLO advertises actual single voice");
  payload[0]=3;payload[1]=0;payload[2]=8'h9a;payload[3]=8'hbd;payload[4]=8'h39;payload[5]=8'h75;
  command(8'h10,1,6);
  check(!dut.gate && dut.inhibit_notes,"real BEGIN clears the held manual key through source-domain ownership");
  payload[0]=0;payload[1]=0;note(0,0,60,450);note(1,500,62,450);note(2,1000,64,900);
  command(8'h11,2,26);command(8'h11,2,26);command(8'h12,3,0);
  command(8'h20,4,0);wait(ons==1);cycles(500);
  check(dut.visual_notes==16'h0001,"Bluetooth C4 highlights its MIDI pitch rather than allocator slot0");
  cycles(99500);
  command(8'h21,5,0);held_position=dut.bluetooth_on.link.core.position_ms;
  cycles(75000);check(dut.bluetooth_on.link.core.position_ms==held_position && dut.voice_active==0,"pause freezes time and silences audio");
  command(8'h22,6,0);wait(ons==2);
  wait(dut.bluetooth_on.link.core.play_state==0);
  wait(!dut.bluetooth_on.link.core.manual_inhibit && !dut.bt_inhibit);cycles(1000);
  check(dut.bluetooth_on.link.core.position_ms==1900 && ons==4 && offs==3,"golden1900ms piece plus resume delivers exactly four On/three Off");
  check(!dut.gate && dut.voice_active==0 && dut.visual_sample==0 && clears>=3,"natural completion restores digital silence");
  command(8'h23,7,0);check(dut.bluetooth_on.link.core.position_ms==0,"STOP resets protocol position");
  cycles(1000);check(!dut.gate && dut.inhibit_notes,"held key cannot retrigger after protocol STOP");
  pressed=0;wait(!dut.inhibit_notes);pressed=16'h0200;wait(dut.gate);
  check(dut.last_key==9,"manual performance resumes only after physical release and re-press");
  $display("PASS tb_bt_score_audio checks=%0d ons=%0d offs=%0d",checks,ons,offs);$finish;
 end
 initial begin #60000000;$fatal(1,"protocol/audio timeout replies=%0d ons=%0d offs=%0d keys=%h inhibit=%b gate=%b state=%0d ready=%b",replies,ons,offs,dut.keys,dut.inhibit_notes,dut.gate,dut.bluetooth_on.link.core.play_state,dut.input_ready);end
endmodule
