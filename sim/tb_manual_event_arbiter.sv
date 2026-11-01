`timescale 1ns/1ps
module tb_manual_event_arbiter;
 reg clk=0,rst=1,av=0,bv=0,ready=0;wire ar,br,valid,on,expr;
 wire [6:0] id,pitch,vel;wire [31:0] fcw;wire [4:0] tone;
 integer checks=0;
 always #5 clk=~clk;
 manual_event_arbiter dut(clk,rst,av,1'b1,bv,1'b0,7'd60,7'd96,32'd123,32'd456,5'd3,5'd5,7'd60,7'd100,ready,
 ar,br,valid,on,id,pitch,vel,fcw,tone,expr);
 task check(input bit ok);begin checks++;if(!ok)$fatal(1,"arbiter lock/fairness");end endtask
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 initial begin
  cycles(3);rst=0;av=1;cycles(2);check(id==60&&on&&!expr);bv=1;cycles(10);check(id==60&&!br);
  ready=1;cycles(1);ready=0;cycles(1);check(id==96&&!on&&expr&&vel==100&&pitch==60&&fcw==456);
  cycles(10);check(id==96);ready=1;cycles(1);ready=0;cycles(1);check(id==60);
  ready=1;cycles(1);av=0;cycles(1);check(br&&id==96);bv=0;cycles(1);check(!valid);
  $display("PASS tb_manual_event_arbiter checks=%0d",checks);$finish;
 end
endmodule
