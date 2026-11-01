`timescale 1ns/1ps
// Long device BUSY times against a scaled per-operation deadline. These are
// timer-boundary tests; production 1MHz is verified by tb_flash_production.
module tb_flash_busy_budget;
 reg clk=0,rst=1,valid=0,bw=0,stuck=0;always #10 clk=~clk;
 reg [1:0] op=0;reg [8:0] length=1;reg [7:0] index=0,value=0;
 wire ready,done,init,cs,sck,mosi,miso;wire [7:0] error;integer programs,erases,checks=0;
 spi_nor_flash #(.HALF_CYCLES(4),.BOOT_CYCLES(8),.POLL_CYCLES(100),.TIMEOUT_CYCLES(1000000),.REGION_LAST(4095)) dut(
 .clk(clk),.rst(rst),.request_valid(valid),.request_ready(ready),.operation(op),.address(24'd0),.length(length),.writes_enabled(1'b1),
 .done(done),.error(error),.initialized(init),.buffer_write(bw),.buffer_index(index),.buffer_wdata(value),.read_index(8'd0),
 .cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso));
 spi_nor_model #(.BYTES(4096),.PROGRAM_BUSY_CYCLES(500000),.ERASE_BUSY_CYCLES(500000)) chip(clk,cs,sck,mosi,miso,24'h204018,1'b0,stuck,programs,erases);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task request(input [1:0] operation,input [8:0] size,input [7:0] expected);begin
  @(negedge clk);wait(ready);op=operation;length=size;valid=1;@(negedge clk);valid=0;
  wait(done);check(error==expected,"long BUSY / timeout result");@(negedge clk);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;wait(init && ready);
  for(integer i=0;i<256;i++)begin @(negedge clk);bw=1;index=i;value=i^8'h6a;end
  @(negedge clk);bw=0;request(2,256,0);check(programs==1,"slow page program completes and reads back before deadline");
  request(3,1,0);check(erases==1 && chip.memory[0]==255 && chip.memory[4095]==255,"slow erase still checks the whole sector");
  stuck=1;request(0,1,8'h22);stuck=0;request(0,1,0);
  check(ready && cs && chip.forbidden_writes==0,"busy timeout recovery needs no unlock, reset or chip erase");
  $display("PASS tb_flash_busy_budget checks=%0d",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"slow busy timeout");end
endmodule
