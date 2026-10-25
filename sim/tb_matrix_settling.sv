`timescale 1ns/1ps
`include "check.svh"
module tb_matrix_settling;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [15:0] pressed=0;wire [3:0] columns;reg [3:0] ideal;
 wire [3:0] rows;wire [15:0] keys;wire scan,ghost;integer checks=0;
 // Fast falling contact,slow pull-up release: seven clocks of row history.
 for(genvar r=0;r<4;r=r+1)begin
  always @*ideal[r]=!((pressed[r*4+:4]&columns)!=0);
  assign #(70,0) rows[r]=ideal[r];
 end
 matrix_keypad #(.SLOT_CYCLES(24),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2)) dut(clk,rst,rows,columns,keys,scan,ghost);
 task settle;begin repeat(600)@(negedge clk);end endtask
 initial begin #100 rst=0;settle;
  for(integer k=0;k<16;k=k+1)begin
   pressed=16'b1<<k;settle;
   `CHECK(keys==(16'b1<<k) && !ghost,"slow pull-up cannot duplicate a physical single key")
   pressed=0;settle;`CHECK(keys==0,"release clears all keys")
  end
  for(integer c=0;c<4;c=c+1)begin
   pressed=16'h1111<<c;settle;
   `CHECK(keys==(16'h1111<<c) && !ghost,"each column preserves its own four identities")
   pressed=0;settle;
  end
  $display("PASS tb_matrix_settling checks=%0d",checks);$finish;
 end
endmodule
