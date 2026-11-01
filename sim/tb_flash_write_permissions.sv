`timescale 1ns/1ps
module tb_flash_write_permissions;
 parameter integer HALF=4;
 reg clk=0,rst=1,valid=0,bw=0;always #10 clk=~clk;
 reg [1:0] op=0;reg [23:0] addr=0;reg [8:0] len=1;
 reg [7:0] bi=0,bd=8'h5a,ri=0;
 wire [7:0] rd,err,s1,s2,s3;wire ready,done,init,supported,cs,sck,mosi,miso;
 wire [23:0] jedec;integer programs,erases,checks=0,before_programs,before_erases;
 spi_nor_flash #(.HALF_CYCLES(HALF),.BOOT_CYCLES(8),.POLL_CYCLES(8),.TIMEOUT_CYCLES(5000000),.REGION_LAST(24'h001fff)) dut(
 .clk(clk),.rst(rst),.request_valid(valid),.request_ready(ready),.operation(op),.address(addr),.length(len),.writes_enabled(1'b1),
 .done(done),.error(err),.initialized(init),.supported(supported),.jedec_id(jedec),.status1(s1),.status2(s2),.status3(s3),
 .buffer_write(bw),.buffer_index(bi),.buffer_wdata(bd),.read_index(ri),.read_data(rd),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso));
 spi_nor_model #(.BYTES(8192)) chip(clk,cs,sck,mosi,miso,24'hef4018,1'b0,1'b0,programs,erases);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s error=%h SR=%h/%h/%h",why,err,s1,s2,s3);end endtask
 task request(input [1:0] o,input [7:0] expected);begin
  @(negedge clk);wait(ready);op=o;valid=1;@(negedge clk);valid=0;
  wait(done);check(err==expected,"actual program/erase result is verified without changing protection");@(negedge clk);
 end endtask
 initial begin
  #100;rst=0;wait(init && ready);
  for(integer f=0;f<8;f++)begin
   chip.sr1_flags=f<<5;chip.sr2_flags=8'h3b;chip.sr3_flags=8'h60;
   request(0,0);check(jedec==24'hef4018 && supported,"JEDEC remains identified with register locks set");
   request(3,0);
   @(negedge clk);bw=1;bd=8'ha5;@(negedge clk);bw=0;
   request(2,0);request(1,0);repeat(2)@(negedge clk);check(rd==8'ha5,"unprotected array programs and reads despite SRP/SRL/SEC/TB/QE/LB flags");
  end
  before_programs=programs;before_erases=erases;
  for(integer f=1;f<8;f++)begin chip.sr1_flags=f<<2;chip.sr2_flags=0;chip.sr3_flags=0;request(3,8'h09);end
  @(negedge clk);bw=1;bd=8'h5a;@(negedge clk);bw=0;
  chip.sr1_flags=0;chip.sr2_flags=8'h40;request(2,8'h09);
  chip.sr2_flags=8'h80;request(3,8'h09);
  chip.sr2_flags=0;chip.sr3_flags=4;request(3,8'h09);
  check(programs==before_programs && erases==before_erases,"genuine protection never permits program or erase");
  check(chip.forbidden_writes==0,"no status writes, unlock instructions or chip erase emitted");
  $display("PASS tb_flash_write_permissions checks=%0d programs=%0d erases=%0d",checks,programs,erases);$finish;
 end
 initial begin #1000000000;$fatal(1,"permission test timeout");end
endmodule
