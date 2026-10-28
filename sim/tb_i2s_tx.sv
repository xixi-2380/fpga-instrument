`timescale 1ns/1ps
`include "check.svh"
module tb_i2s_tx;
 parameter integer HALF=20;
 reg clk=0,rst=1,valid=0;always #5 clk=~clk;
 wire bck,rise,fall,fc,ws,din,ready,underrun;wire [4:0] index;
 reg [15:0] in_l=0,in_r=0;wire [15:0] frame_l,frame_r;
 reg [15:0] pending_l=0,pending_r=0,active_l=0,active_r=0;
 reg pending=0,synced=0,previous_ws=1;
 reg [15:0] expected_l=0,expected_r=0,decoded=0;
 integer checks=0,bits=0,channel=0,words=0,zeros=0,coincident=0;
 realtime last_rise=0;
 audio_timing #(.HALF_CYCLES(HALF)) timing(clk,rst,bck,rise,fall,fc,index,);
 frame_buffer buffer(clk,rst,fc,valid,ready,in_l,in_r,frame_l,frame_r,underrun);
 i2s_tx dut(clk,rst,fall,index,frame_l,frame_r,ws,din);
 always @(posedge rst)begin
  pending_l=0;pending_r=0;active_l=0;active_r=0;pending=0;
  synced=0;previous_ws=1;expected_l=0;expected_r=0;decoded=0;
  bits=0;channel=0;last_rise=0;
 end
 // Independent source queue: a boundary consumes old data before a simultaneous
 // valid/ready fills the next pair. Expectations never inspect serializer state.
 always @(posedge clk)if(!rst)begin
  if(fc)begin active_l=pending?pending_l:0;active_r=pending?pending_r:0;pending=0;end
  if(valid && ready)begin pending_l=in_l;pending_r=in_r;pending=1;if(fc)coincident=coincident+1;end
 end
 always @(ws or din)if(!rst)begin
  #0.001;`CHECK(!bck,"I2S data and LRCLK change only while BCLK is low")
 end
 always @(posedge bck)if(!rst)begin
  if(last_rise>0)begin `CHECK($realtime-last_rise==20*HALF,"BCLK period remains exact") end
  last_rise=$realtime;
  if(!synced)begin
   if(ws!=previous_ws)begin synced=1;channel=ws;bits=0;decoded=0;end
  end else begin
   if(bits==0 && channel==0)begin expected_l=active_l;expected_r=active_r;end
   decoded={decoded[14:0],din};
   if(bits==15)begin
    `CHECK(ws!=previous_ws && ws!=channel,"LRCLK transition occurs on old channel LSB")
    `CHECK(decoded==(channel?expected_r:expected_l),"distinct left/right words preserve sign, order and all bits")
    if(decoded==0)zeros=zeros+1;
    words=words+1;bits=0;decoded=0;channel=ws;
   end else begin `CHECK(ws==previous_ws,"new MSB is one BCLK after LRCLK transition") bits=bits+1;end
  end
  previous_ws=ws;
 end
 task send(input [15:0] l,r);begin
  @(negedge clk);while(!ready)@(negedge clk);
  in_l=l;in_r=r;valid=1;@(posedge clk);#0.002;@(negedge clk);valid=0;
  // Changes while the input is not accepted must not tear the active stereo pair.
  in_l=~l;in_r=~r;
 end endtask
 initial begin
  #12 rst=0;wait(words>=4);
  send(16'h1234,16'hfedc);send(16'h8000,16'h7fff);send(16'h0001,16'h8001);
  for(integer j=0;j<16;j=j+1)send(16'h1<<j,~(16'h1<<j));
  for(integer j=0;j<40;j=j+1)send($random,$random);
  @(negedge clk);while(!fc)@(negedge clk);
  in_l=16'h5aa5;in_r=16'ha55a;valid=1;@(posedge clk);#0.002;@(negedge clk);valid=0;
  wait(words>=130);
  `CHECK(coincident>0 && zeros>6 && underrun,"simultaneous handshake and empty-frame zero insertion covered")
  // Reset interrupts a partially emitted word and drops previous queued samples.
  send(16'hffff,16'h8000);repeat(7)@(posedge bck);#3;rst=1;valid=0;
  #1;`CHECK(ws && !din && !underrun,"asynchronous reset clears serializer and pending audio")
  #11;rst=0;repeat(100)@(posedge bck);
  `CHECK(words>130 && synced,"I2S receiver re-synchronizes after mid-word reset")
  $display("PASS tb_i2s_tx checks=%0d words=%0d half=%0d",checks,words,HALF);$finish;
 end
 initial begin #3000000;$fatal(1,"I2S transmitter timeout");end
endmodule
