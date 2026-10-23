`timescale 1ns/1ps
`include "check.svh"
module tb_instrument_envelopes;
 reg clk=0,rst=1,ce=1,on=0,off=0,restart=0;reg [2:0] timbre=3;
 wire [16:0] level;wire active;
 integer checks=0,attack_frames,initial_level,prior,max_release;
 always #5 clk=~clk;
 instrument_envelope #(.ATTACK(4),.DECAY(4),.SUSTAIN(40000),.RELEASE(8)) dut(clk,rst,ce,on,off,restart,timbre,level,active);
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 initial begin
  #12 rst=0;
  for(integer t=3;t<7;t=t+1)begin
   timbre=t;on=1;restart=1;tick;on=0;restart=0;
   `CHECK(active && level==0,"new ownership starts at zero")
   attack_frames=t==3 ? 2048 : t==4 ? 64 : t==5 ? 32 : 128;
   prior=0;
   for(integer n=0;n<attack_frames;n=n+1)begin tick;`CHECK(level>=prior && level<=65536,"bounded monotonic profile attack") prior=level;end
   `CHECK(level==65536,"instrument-specific attack reaches exact full scale")
   for(integer n=0;n<4096;n=n+1)tick;
   if(t==3)`CHECK(level>=49152 && active,"cello bow sustains")
   else `CHECK(level<65536 && active,"struck and plucked notes decay while held")
   initial_level=level;timbre=0;repeat(20)tick;
   `CHECK(dut.profile==t && active,"changing selection alone cannot rewrite held voice profile")
   off=1;tick;off=0;prior=level;max_release= t==5 ? 512 : t==4 ? 1024 : 2048;
   for(integer n=0;n<=max_release;n=n+1)begin tick;`CHECK(level<=prior,"release monotonic without click-producing level jumps") prior=level;end
   `CHECK(!active && level==0,"bounded release finishes before score handoff tail")
  end
  timbre=4;on=1;restart=1;tick;on=0;restart=0;repeat(30)tick;
  initial_level=level;on=1;tick;on=0;
  `CHECK(level==initial_level,"same-ID retrigger preserves present level")
  // Same note can adopt a new preset without discarding its current level.
  initial_level=level;timbre=1;on=1;tick;on=0;
  `CHECK(level==initial_level && active,"new-to-legacy retrigger seeds the old envelope continuously")
  repeat(2)tick;initial_level=level;timbre=3;on=1;tick;on=0;
  `CHECK(level==initial_level && active,"legacy-to-new retrigger preserves envelope level")
  rst=1;#1;`CHECK(level==0 && !active,"reset clears all envelope paths")
  $display("PASS tb_instrument_envelopes checks=%0d",checks);$finish;
 end
endmodule
