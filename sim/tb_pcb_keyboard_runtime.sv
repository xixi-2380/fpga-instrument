`timescale 1ns/1ps
`include "aip5916_model.svh"
module tb_pcb_keyboard_runtime;
 reg clk=0,rst=1,present=1,noisy=0,cfg_valid=0,clear=0;always #10 clk=~clk;
 reg [15:0] touch_keys=0;reg [131:0] config_data={{16{8'd4}},4'd2};
 tri1 scl,sda;wire intr;wire [15:0] keys;wire online,report,fault,ready,done,fresh;
 wire [7:0] err;wire [131:0] applied,observed;wire [639:0] diag;
 integer checks=0,writes_before;
 aip5916_model chip(rst,present,touch_keys,scl,sda,intr);
 aip5916_keyboard #(.BOOT_CYCLES(20),.POLL_CYCLES(1600),.I2C_HALF_CYCLES(4),
 .TIMEOUT_CYCLES(100),.RETRY_CYCLES(32),.STALE_CYCLES(12000)) dut(
 .clk(clk),.rst(rst),.intr_n(intr),.scl(scl),.sda(sda),.keys(keys),.online(online),.report(report),.fault(fault),
 .cfg_valid(cfg_valid),.cfg_data(config_data),.cfg_ready(ready),.cfg_done(done),.cfg_error(err),.data_valid(fresh),
 .applied_config(applied),.observed_config(observed),.diagnostic(diag),.clear_stats(clear));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task configure;begin @(negedge clk);wait(ready);cfg_valid=1;@(negedge clk);cfg_valid=0;wait(done);#1;end endtask
 always @(negedge clk)if(noisy && dut.done && dut.state==7 && dut.byte_index==2)touch_keys=~touch_keys;
 initial begin
  repeat(5)@(negedge clk);check(!diag[609],"no applied profile is claimed before a successful initialization");rst=0;wait(fresh);check(diag[609],"successful initialization confirms the applied profile");check(online && keys==0,"verified startup and two zero samples");
  touch_keys=1;@(posedge report);@(negedge clk);touch_keys=0;
  repeat(5000)begin @(negedge clk);check(keys==0,"one coherent press sample cannot generate a note");end
  touch_keys=16'h21;wait(keys==16'h21);check(fresh,"stable chord is admitted");
  writes_before=chip.writes;noisy=1;wait(!fresh);repeat(14000)@(negedge clk);
  check(online && !fault && keys==0 && chip.writes==writes_before,"data changes become stale without physical offline or reconfiguration");
  check(dut.change_count!=0 && dut.stale_count!=0 && dut.nack_count==0,"noise and transport failures have distinct counters");
  noisy=0;touch_keys=0;wait(fresh);wait(keys==0);
  config_data[3:0]=5;config_data[4+7*8+:8]=35;configure();
  check(err==0 && applied==config_data && observed==config_data && chip.registers[7]==35,"runtime sensitivity fully writes and reads back before commit");
  present=0;wait(!online);present=1;wait(fresh);
  check(applied==config_data && chip.registers[7]==35,"reconnect retains the successful runtime configuration");
  config_data[3:0]=9;config_data[4+7*8+:8]=40;
  fork
   configure();
   begin wait(dut.applying && dut.config_index==12);chip.mismatch=1;end
  join
  check(err!=0 && applied[3:0]==5 && chip.registers[6'h20]==9,"partially written failed apply cannot overwrite the successful configuration");
  chip.mismatch=0;wait(fresh);check(chip.registers[6'h20]==5,"automatic recovery restores the last successful configuration");
  check(diag[175:144]==32'h23072829,"retry success cannot replace the original failing register/expected/actual bytes");
  @(negedge clk);clear=1;@(negedge clk);clear=0;check(applied[3:0]==5 && diag[609] && diag[175:144]==0,"healthy clear resets fault history without forgetting the confirmed applied profile");
  rst=1;repeat(5)@(negedge clk);rst=0;wait(fresh);
  check(applied[3:0]==2 && applied[4+7*8+:8]==4,"system reset restores defaults without Flash persistence");
  $display("PASS tb_pcb_keyboard_runtime checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"runtime keyboard timeout");end
endmodule
