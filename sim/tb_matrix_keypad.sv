`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
module tb_matrix_keypad;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [15:0] pressed=0;
 wire [3:0] rows,columns;
 wire [15:0] keys;wire valid,ghost;
 integer checks=0,scans=0;
 matrix_keypad #(.SLOT_CYCLES(8),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(3))
  dut(clk,rst,rows,columns,keys,valid,ghost);
 passive_matrix_model model(pressed,columns,rows);
 always @(negedge clk)if(!rst)begin
  `CHECK(columns!=0 && (columns&(columns-1))==0,"one active column")
  if(valid)scans=scans+1;
 end
 task await_scans(input integer count);integer target;begin
  target=scans+count;wait(scans>=target);@(negedge clk);#1;
 end endtask
 task set_keys(input [15:0] mask);begin
  @(negedge clk);pressed=mask;await_scans(5);
  `CHECK(keys==mask && !ghost,"stable matrix state and orientation")
 end endtask
 initial begin
  #12 rst=0;await_scans(4);`CHECK(keys==0,"idle")
  for(integer k=0;k<16;k=k+1)begin set_keys(16'h1<<k);set_keys(0);end
  // A bounce shorter than the qualification interval must not make a note.
  @(negedge clk);pressed=1;await_scans(1);pressed=0;await_scans(5);
  `CHECK(keys==0,"short bounce suppressed")
  set_keys(16'h000f);set_keys(0); // four keys in one row are unambiguous
  set_keys(16'h8421);set_keys(0); // separate rows and columns
  set_keys(16'h0021); // opposite corners of a 2x2, safe
  @(negedge clk);pressed=16'h0013;await_scans(4); // three corners, fourth ghosts
  `CHECK(ghost && keys==0,"three-corner ghost cannot create notes")
  @(negedge clk);pressed=16'hffff;await_scans(4);
  `CHECK(ghost && keys==0,"full occupied ambiguous matrix")
  set_keys(16'h0003);set_keys(0);
  pressed=16'h8000;await_scans(5);#2 rst=1;#1;
  `CHECK(keys==0 && columns==0,"reset releases columns and clears held keys")
  #20 rst=0;await_scans(5);
  `CHECK(keys==16'h8000,"held key recognized after reset")
  $display("PASS tb_matrix_keypad checks=%0d",checks);$finish;
 end
 initial begin #100000;$fatal(1,"matrix timeout");end
endmodule
