`timescale 1ns/1ps
`include "synth_config.svh"
`include "check.svh"
module tb_tone_core;
 reg clk=0,rst=1;always #8.138020833 clk=~clk;
 reg [1:0] mode=0;wire bck,ws,din,pa,u;
 integer checks=0,frame=0,bitn=0,ch=0,decoded=0,expected,a,step,coef,romcode;
 integer f,epoch=0;reg [31:0] phase;reg signed [63:0] p;real x;
 tone_core dut(clk,rst,`TONE_FCW,mode,bck,ws,din,pa,u);
 always @(posedge clk) if(!rst) begin
  `CHECK(!dut.gain_valid || dut.ready,"fixed pipeline meets deadline")
  `CHECK(!u,"no underrun")
 end
 always @(posedge bck) if(!rst) begin
  `CHECK(ws==(ch==1),"pin decoder channel")
  decoded=((decoded<<1)|din)&65535;
  if(bitn==15) begin
   phase=(frame-1)*`TONE_FCW;a=phase[31:20];
   x=$sin(6.283185307179586*a/4096.0)*32767.0;
   romcode=x>=0?$rtoi(x+0.5):$rtoi(x-0.5);
   step=frame-481;if(step<0)step=0;if(step>240)step=240;
   coef=step*65536/240;p=romcode;p=p*coef;expected=p>>>21;
   if(frame==0 || (mode==1 && ch==0) || (mode==2 && ch==1))expected=0;
   `CHECK(decoded==(expected&65535),"end-to-end DDS/envelope/serial reference")
   if(ch==1 && epoch==0)$fdisplay(f,"%0d,%0d",frame,$signed(decoded[15:0]));
   bitn=0;decoded=0;
   if(ch==1)begin
    frame=frame+1;
    if(frame%12000==0)$display("PROGRESS frames=%0d",frame);
   end
   ch=1-ch;
  end else bitn=bitn+1;
 end
 task restart(input [1:0] m);begin
  #3 rst=1;#1;`CHECK(!pa && !u && din==0,"mid-play reset mute")
  frame=0;bitn=0;ch=0;decoded=0;mode=m;#31 rst=0;
 end endtask
 initial begin
  f=$fopen("reports/sim/tone_samples.csv","w");$fdisplay(f,"frame,sample");
  $dumpfile("reports/sim/tone_boundaries.vcd");$dumpvars(1,dut);
  #23 rst=0;wait(frame==3);$dumpoff;
  wait(frame==48000);epoch=1;$fclose(f);
  restart(1);wait(frame==1000);
  $dumpon;restart(2);wait(frame==3);$dumpoff;wait(frame==1000);
  $display("PASS tb_tone_core checks=%0d continuous_frames=48000 reset_modes=2",checks);$finish;
 end
 initial begin #1100000000;$fatal(1,"timeout");end
endmodule
