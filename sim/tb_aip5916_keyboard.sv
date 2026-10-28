`timescale 1ns/1ps
`include "check.svh"
`include "aip5916_model.svh"
module tb_aip5916_keyboard;
 parameter integer HALF=4;
 reg clk=0,rst=1,present=1;always #10 clk=~clk;
 reg [15:0] touch_keys=0;
 tri1 scl,sda;wire int_n;wire [15:0] keys;wire online,report,fault;
 integer checks=0,reports=0;reg hold_scl=0;
 assign scl=hold_scl?1'b0:1'bz;
 aip5916_model chip(rst,present,touch_keys,scl,sda,int_n);
 aip5916_keyboard #(.BOOT_CYCLES(20),.POLL_CYCLES(HALF*400),.I2C_HALF_CYCLES(HALF),
  .TIMEOUT_CYCLES(HALF*24),.RETRY_CYCLES(32)) dut(clk,rst,int_n,scl,sda,keys,online,report,fault);
 always @(posedge clk)begin #1;if(report)reports++;
  if(!rst)begin
   `CHECK(!dut.bus.scl_low || scl===0,"master SCL is open drain")
   `CHECK(!dut.bus.sda_low || sda===0,"master SDA is open drain")
  end
 end
 task settle(input [15:0] value);integer count;begin
  count=0;while((keys!==value || !online) && count<HALF*20000)begin @(negedge clk);count++;end
  `CHECK(keys===value && online,"coherent touch snapshot eventually commits")
 end endtask
 initial begin
  #100;rst=0;settle(0);
  `CHECK(chip.writes==25 && chip.registers[6'h3a]==0,"all 25 init writes read back before normal mode")
  `CHECK(chip.registers[6'h21]==4 && chip.registers[6'h20]==2 && chip.registers[6'h22]==8'h20 && chip.registers[6'h2a]==8'h10,"documented config values")
  for(integer n=0;n<16;n++)`CHECK(chip.registers[n]==4,"all thresholds written separately")
  touch_keys=16'h0001;settle(1);touch_keys=16'h8805;settle(16'h8805);
  touch_keys=16'h8804;settle(16'h8804);touch_keys=0;settle(0);
  // Change between the two verification pairs. No torn state may be published.
  touch_keys=16'h00ff;wait(dut.state==7 && dut.byte_index==2);touch_keys=16'h0f00;
  settle(16'h0f00);`CHECK(dut.failures==0,"incoherent scan retries without false release")
  touch_keys=16'h0801;settle(16'h0801);
  present=0;wait(!online);`CHECK(fault && keys==0,"three failures release held notes and mark this board offline")
  present=1;settle(16'h0801);`CHECK(!fault && chip.writes>=50,"plugging board back reinitializes and verifies")
  hold_scl=1;wait(!online);`CHECK(keys==0 && !dut.bus.sda_low,"stuck clock times out without stuck notes")
  hold_scl=0;settle(16'h0801);
  chip.mismatch=1;present=0;wait(!online);present=1;
  repeat(HALF*3000)@(negedge clk);
  `CHECK(!online && keys==0,"readback mismatch prevents exposing keys")
  chip.mismatch=0;touch_keys=0;settle(0);
  `CHECK(chip.starts>chip.reads && chip.stops>25,"writes and repeated starts observed on wires")
  $display("PASS tb_aip5916_keyboard checks=%0d reports=%0d half=%0d",checks,reports,HALF);$finish;
 end
 initial begin #(HALF*1000000);$fatal(1,"AiP keyboard timeout");end
endmodule
