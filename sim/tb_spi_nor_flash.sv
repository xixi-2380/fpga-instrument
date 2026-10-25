`timescale 1ns/1ps
module tb_spi_nor_flash;
 reg clk=0,rst=1,valid=0,bw=0,enable=1,protect=0,stuck=0;
 reg [1:0] op=0;reg [23:0] addr=0,id=24'hef4018;reg [8:0] len=1;
 reg [7:0] bi=0,bd=0,ri=0;wire [7:0] rd,err;wire ready,done,init,supported,cs,sck,mosi,miso;
 wire [23:0] jedec;integer programs,erases,checks=0;
 always #10 clk=~clk;
 spi_nor_flash #(.HALF_CYCLES(4),.BOOT_CYCLES(8),.POLL_CYCLES(8),.TIMEOUT_CYCLES(50000),.REGION_LAST(24'h001fff)) dut(
 .clk(clk),.rst(rst),.request_valid(valid),.request_ready(ready),.operation(op),.address(addr),.length(len),.writes_enabled(enable),
 .done(done),.error(err),.initialized(init),.supported(supported),.jedec_id(jedec),
 .buffer_write(bw),.buffer_index(bi),.buffer_wdata(bd),.read_index(ri),.read_data(rd),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso));
 spi_nor_model #(.BYTES(8192)) chip(clk,cs,sck,mosi,miso,id,protect,stuck,programs,erases);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task request(input [1:0] o,input [23:0] a,input [8:0] n,input [7:0] e);begin
  @(negedge clk);wait(ready);op=o;addr=a;len=n;valid=1;@(negedge clk);valid=0;
  wait(done);check(err==e,"bounded flash request result");@(negedge clk);
 end endtask
 initial begin
  #1 chip.busy_cycles=2000;
  #99 rst=0;wait(init && ready);check(jedec==24'hef4018 && supported && chip.busy_cycles==0,"read-only boot waits out a pre-reset NOR operation before JEDEC");
  for(integer i=0;i<256;i++)begin @(negedge clk);bw=1;bi=i;bd=i^8'ha5;end
  @(negedge clk);bw=0;
  request(2,0,256,0);check(programs==1,"one complete page program");request(1,0,256,0);
  for(integer i=0;i<256;i++)begin ri=i;repeat(2)@(negedge clk);check(rd==8'(i^8'ha5),"wire-level readback matches buffered page");end
  request(2,255,2,8'h23);request(3,1,1,8'h23);request(3,8192,1,8'h23);
  enable=0;request(3,0,1,8'h21);enable=1;protect=1;request(3,0,1,8'h21);protect=0;
  request(3,0,1,0);request(1,0,16,0);ri=0;repeat(2)@(negedge clk);check(rd==255 && erases==1,"sector erase and readback");
  id=24'hffffff;request(0,0,1,0);check(!supported,"unknown/absent chip stays unsupported");request(2,0,1,8'h21);
  check(programs==1 && erases==1,"rejected addresses/protection/unknown ID cannot mutate NOR");
  id=24'hef4018;request(0,0,1,0);
  fork
   request(3,0,1,8'h22);
   begin wait(erases==2);stuck=1;end
  join
  check(ready && cs,"busy timeout releases command interface/CS without stopping clocks");
  $display("PASS tb_spi_nor_flash checks=%0d programs=%0d erases=%0d",checks,programs,erases);$finish;
 end
 initial begin #10000000;$fatal(1,"SPI timeout state=%0d id=%h",dut.state,jedec);end
endmodule
