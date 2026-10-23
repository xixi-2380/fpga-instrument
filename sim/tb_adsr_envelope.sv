`timescale 1ns/1ps
`include "check.svh"
module tb_adsr_envelope;
 reg clk=0,rst=1,ce=0,on=0,off=0,restart=0;always #5 clk=~clk;
 wire [16:0] q,qzero,qfull;wire active;
 integer checks=0,start_level,expected;
 adsr_envelope #(.ATTACK(4),.DECAY(3),.SUSTAIN(32768),.RELEASE(5)) dut(clk,rst,ce,on,off,q,active,restart,1'b0,17'd0);
 adsr_envelope #(.ATTACK(0),.DECAY(0),.SUSTAIN(0),.RELEASE(0)) zero(clk,rst,ce,on,off,qzero,,restart,1'b0,17'd0);
 adsr_envelope #(.ATTACK(0),.DECAY(0),.SUSTAIN(65536),.RELEASE(0)) full(clk,rst,ce,on,off,qfull,,restart,1'b0,17'd0);
 task tick(input bit n,f);begin
  @(negedge clk);ce=1;on=n;off=f;@(posedge clk);#1;
  `CHECK(q<=65536 && qzero<=65536 && qfull<=65536,"Q1.16 bounds")
  @(negedge clk);ce=0;on=0;off=0;
 end endtask
 initial begin
  #12 rst=0;tick(1,0);`CHECK(q==0 && qzero==0 && qfull==65536,"zero-duration limits")
  for(integer i=1;i<=4;i=i+1)begin tick(0,0);`CHECK(q==i*16384,"exact Attack") end
  for(integer i=1;i<=3;i=i+1)begin tick(0,0);`CHECK(q==65536-(32768*i/3),"exact Decay remainder") end
  repeat(4)begin tick(0,0);`CHECK(q==32768,"Sustain") end
  tick(0,1);`CHECK(q==32768 && qfull==0,"Note Off starts Release")
  for(integer i=1;i<=5;i=i+1)begin tick(0,0);`CHECK(q==32768-(32768*i/5),"exact Release from current level") end
  `CHECK(q==0 && !active,"Release reaches zero")
  tick(1,0);tick(0,0);tick(0,1);tick(0,0);start_level=q;
  tick(1,0);`CHECK(q==start_level,"retrigger has no discontinuous drop")
  for(integer i=1;i<=4;i=i+1)begin
   tick(0,0);expected=start_level+((65536-start_level)*i/4);
   `CHECK(q==expected,"Attack from release level")
  end
  tick(1,1);repeat(5)tick(0,0);`CHECK(q==0,"simultaneous Off wins")
  tick(1,0);tick(0,0);tick(0,0);
  `CHECK(q>0,"voice has a level before reassignment")
  restart=1;tick(1,0);
  `CHECK(q==0 && active,"new voice ownership restarts Attack at zero")
  restart=0;tick(0,0);`CHECK(q==16384,"restarted Attack uses full zero-to-peak slope")
  restart=1;tick(0,0);restart=0;
  `CHECK(q==0 && !active,"restart without Note On clears the voice")
  #2 rst=1;#1;`CHECK(q==0 && qfull==0,"reset mutes envelope")
  $display("PASS tb_adsr_envelope checks=%0d",checks);$finish;
 end
 initial begin #100000;$fatal(1,"ADSR timeout");end
endmodule
