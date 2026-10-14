`timescale 1ns/1ps
`include "synth_config.svh"
`include "check.svh"

// Independent rising-edge PT8211 receiver and mathematical DDS reference.
// Uses no internal phase/ROM/serializer state to derive the expected code.
module tone_play_probe #(
 parameter integer MODE=0,MUTE=`MUTE_FRAMES,FADE=`FADE_FRAMES,TARGET=850)(
 input wire clk,rst,output reg done=0,output integer checks=0);
 // Testbench-only clock shutdown after isolated-channel checks finish.
 // Hold that model in reset while stopped; external reset re-arms it.
 // The production stereo instance runs continuously through both epochs.
 wire probe_clk=(MODE!=0 && done)?1'b0:clk;
 wire probe_rst=rst || (MODE!=0 && done);
 wire bck,ws,din,pa,db,dw,dd,dp,underrun;
 generate
  if(MODE==0)begin: stereo
   tone_play_stereo #(.LOCK_N(32),.MUTE(MUTE),.FADE(FADE)) dut(probe_clk,probe_rst,bck,ws,din,pa,db,dw,dd,dp);
   assign underrun=dut.board.engine.underrun;
  end else if(MODE==1)begin: left_only
   tone_play_left #(.LOCK_N(32),.MUTE(MUTE),.FADE(FADE)) dut(probe_clk,probe_rst,bck,ws,din,pa,db,dw,dd,dp);
   assign underrun=dut.board.engine.underrun;
  end else begin: right_only
   tone_play_right #(.LOCK_N(32),.MUTE(MUTE),.FADE(FADE)) dut(probe_clk,probe_rst,bck,ws,din,pa,db,dw,dd,dp);
   assign underrun=dut.board.engine.underrun;
  end
 endgenerate
 integer frames=0,bitn=0,ch=0,word=0,addr,romcode,step,coef,expected;
 integer positive=0,negative=0,epoch=-1,f=0;
 reg [31:0] phase;
 reg signed [63:0] product;
 realtime last_rise=0,period;
 real x;
 initial if(MODE==0)begin
  f=$fopen("reports/sim/D1_decoded.csv","w");
  $fdisplay(f,"epoch,frame,channel,sample");
 end
 always @(posedge rst)begin
  frames=0;bitn=0;ch=0;word=0;done=0;
  positive=0;negative=0;last_rise=0;epoch=epoch+1;
 end
 always @(bck or ws or din or pa)begin
  #0.001;
  `CHECK({db,dw,dd,dp}==={bck,ws,din,pa},"header mirrors DAC and amplifier signals")
 end
 always @(ws or din)if(!rst && !done && last_rise>0)begin
  #0.001;
  `CHECK(bck===0,"WS/DIN change with BCK low")
 end
 always @(posedge bck)if(!rst && !done)begin
  #0.001;
  `CHECK(ws==(ch==1),"PT8211 right-low left-high; no I2S bit delay")
  `CHECK(!underrun,"no missing audio frame")
  if(last_rise>0)begin
   period=$realtime-last_rise;
   `CHECK(period>651.02 && period<651.07,"continuous 1.536 MHz BCK")
  end
  last_rise=$realtime;
  word=((word<<1)|din)&65535;
  if(bitn==15)begin
   phase=(frames-1)*`TONE_FCW;addr=phase[31:20];
   x=$sin(6.283185307179586*addr/4096.0)*32767.0;
   romcode=x>=0?$rtoi(x+0.5):$rtoi(x-0.5);
   step=frames-(MUTE+1);if(step<0)step=0;if(step>FADE)step=FADE;
   coef=step*65536/FADE;product=romcode;product=product*coef;
   expected=product >>> (16+`GAIN_SHIFT);
   if(frames==0 || (MODE==1 && ch==0) || (MODE==2 && ch==1))expected=0;
   `CHECK(word==(expected&65535),"independent DDS/fade/channel pin decoder")
   `CHECK($signed(word[15:0])>=-1024 && $signed(word[15:0])<=1023,"safe 1/32 amplitude")
   `CHECK(pa==(frames>=MUTE),"480 FULL silent frames before amplifier enable")
   if((MODE==0 || (MODE==1 && ch==1) || (MODE==2 && ch==0)) && frames>MUTE+FADE+1)begin
    if($signed(word[15:0])>0)positive=positive+1;
    if($signed(word[15:0])<0)negative=negative+1;
   end
   if(MODE==0 && frames<TARGET)$fdisplay(f,"%0d,%0d,%0d,%0d",epoch,frames,ch,$signed(word[15:0]));
   word=0;bitn=0;
   if(ch==1)begin
    frames=frames+1;
    if(frames==TARGET)begin
     `CHECK(positive>20 && negative>20,"selected channel produces positive and negative sine")
     done=1;
    end
   end
   ch=1-ch;
  end else bitn=bitn+1;
 end
endmodule

module tb_tone_play;
 reg clk=0,rst=0;always #10 clk=~clk;
 wire d0,d1,d2;wire [31:0] c0,c1,c2;
 integer checks=0,local_checks=0;
 tone_play_probe stereo(clk,rst,d0,c0);
 // Production channel entry points, accelerated startup for isolation tests.
 tone_play_probe #(.MODE(1),.MUTE(4),.FADE(4),.TARGET(120)) left_only(clk,rst,d1,c1);
 tone_play_probe #(.MODE(2),.MUTE(4),.FADE(4),.TARGET(120)) right_only(clk,rst,d2,c2);
 initial begin
  $dumpfile("reports/sim/D1_boundaries.vcd");$dumpvars(1,stereo);
  #0.001;$dumpoff;
  wait(stereo.frames==478);$dumpon;
  wait(stereo.frames==484);$dumpoff;
 end
 initial begin
  #1 rst=1;#100 rst=0;
  wait(d0 && d1 && d2);
  #3 rst=1;#1;
  `CHECK(stereo.pa==0 && stereo.dp==0 && stereo.din==0 && stereo.dd==0,"mid-play reset mutes DAC and amplifier")
  `CHECK(left_only.pa==0 && right_only.pa==0,"reset mutes isolated profiles")
  #100 rst=0;
  wait(d0 && d1 && d2);
  checks=checks+c0+c1+c2;
  $display("PASS tb_tone_play checks=%0d stereo_frames_per_epoch=850 epochs=2 channel_profiles=3",checks);
  $finish;
 end
 initial begin #50000000;$fatal(1,"board tone timeout");end
endmodule
