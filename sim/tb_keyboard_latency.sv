`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
module tb_keyboard_latency;
 reg clk=0,rst=1;always #8.138020833 clk=~clk;
 reg [15:0] pressed=0;
 wire [3:0] rows,columns,key;wire [15:0] keys;
 wire bck,ws,din,pa,u,ghost,gate;wire [16:0] level;
 integer checks=0,edges=0,bits=0,word=0;
 real press_ns=0,first_code_ns=0,off_ns=0,note_on_ns=0;
 keyboard_core #(.MUTE(4),.FADE(4))
  dut(clk,rst,rows,columns,bck,ws,din,pa,u,keys,ghost,gate,key,level);
 passive_matrix_model model(pressed,columns,rows);
 always @(posedge gate)if(!rst && press_ns>0)note_on_ns=$realtime;
 always @(posedge bck)if(!rst)begin
  edges=edges+1;word=((word<<1)|din)&65535;
  if(bits==15)begin
   if(press_ns>0 && first_code_ns==0 && word!=0)first_code_ns=$realtime;
   word=0;bits=0;
  end else bits=bits+1;
 end
 initial begin
  #23 rst=0;wait(pa);wait(edges>=800);#103;
  press_ns=$realtime;pressed=16'h0200; // A4
  wait(first_code_ns>0);
  `CHECK(gate && key==9,"production scanner chooses pressed A4")
  `CHECK(note_on_ns-press_ns<5000000.0,"production Note On latency below 5ms in simulation")
  `CHECK(first_code_ns-press_ns<5000000.0,"first nonzero DAC code below 5ms in simulation")
  #71;off_ns=$realtime;pressed=0;wait(!gate);
  `CHECK($realtime-off_ns<5000000.0,"production Note Off latency below 5ms in simulation")
  `CHECK(!u,"no audio underrun at production scan timings")
  $display("LATENCY_US note_on=%0.3f first_code=%0.3f note_off=%0.3f",
   (note_on_ns-press_ns)/1000.0,(first_code_ns-press_ns)/1000.0,($realtime-off_ns)/1000.0);
  $display("PASS tb_keyboard_latency checks=%0d",checks);$finish;
 end
 initial begin #12000000;$fatal(1,"production scan latency timeout");end
endmodule
