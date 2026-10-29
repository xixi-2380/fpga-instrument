`timescale 1ns/1ps
// Wire-level outcomes across manufacturers and independent address/sector locks.
module tb_flash_compatibility;
 parameter integer HALF=4;
 reg clk=0,rst=1,valid=0,bw=0,protect=0;always #10 clk=~clk;
 reg [1:0] op=0;reg [23:0] addr=0,id=24'hc84018;reg [8:0] len=256;
 reg [7:0] bi=0,bd=0,ri=0;wire [7:0] rd,err,s1,s2,s3;
 wire ready,done,init,identified,cs,sck,mosi,miso;wire [23:0] jedec;
 integer programs,erases,checks=0,before_p,before_e;
 spi_nor_flash #(.HALF_CYCLES(HALF),.BOOT_CYCLES(8),.POLL_CYCLES(8),
 .TIMEOUT_CYCLES(5000000),.REGION_LAST(24'h001fff)) dut(
 .clk(clk),.rst(rst),.request_valid(valid),.request_ready(ready),.operation(op),.address(addr),.length(len),.writes_enabled(1'b1),
 .done(done),.error(err),.initialized(init),.supported(identified),.jedec_id(jedec),.status1(s1),.status2(s2),.status3(s3),
 .buffer_write(bw),.buffer_index(bi),.buffer_wdata(bd),.read_index(ri),.read_data(rd),
 .cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso));
 spi_nor_model #(.BYTES(8192)) chip(clk,cs,sck,mosi,miso,id,protect,1'b0,programs,erases);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s error=%h",why,err);end endtask
 task request(input [1:0] operation,input [23:0] address,input [8:0] count,input [7:0] expected);
 begin
  @(negedge clk);wait(ready);op=operation;addr=address;len=count;valid=1;
  @(negedge clk);valid=0;wait(done);check(err==expected,"verified operation result");@(negedge clk);
 end endtask
 task fill(input [7:0] value);begin
  for(integer i=0;i<256;i++)begin @(negedge clk);bw=1;bi=i;bd=value^8'(i);end
  @(negedge clk);bw=0;
 end endtask
 initial begin
  #100 rst=0;wait(init&&ready);check(identified&&jedec==id,"non-Winbond NOR is identified");
  chip.range_lock_enabled=1;chip.protected_first=24'hfc0000;chip.protected_last=24'hffffff;chip.sr1_flags=4;
  chip.memory[0]=0;chip.memory[4095]=0;
  request(3,0,1,0);check(chip.memory[0]==255&&chip.memory[4095]==255,"entire target sector erased despite protection elsewhere");
  fill(8'ha5);request(2,0,256,0);request(1,0,256,0);
  for(integer i=0;i<256;i++)begin ri=i;repeat(2)@(negedge clk);check(rd==(8'ha5^8'(i)),"all bytes persist for non-whitelisted manufacturer");end
  before_p=programs;before_e=erases;
  chip.protected_first=0;chip.protected_last=4095;fill(8'h5a);
  request(2,0,256,9);request(3,0,1,9);
  check(programs==before_p&&erases==before_e&&chip.memory[0]==8'ha5,"protected target remains unchanged and never reports verified success");
  chip.sr3_flags=4;chip.sr1_flags=8'h1c;chip.sr2_flags=8'h40;chip.sector_locked=2'b10;
  request(3,0,1,0);fill(8'h3c);request(2,0,256,0);
  chip.memory[4096]=8'ha5;request(2,4096,256,9);
  check(chip.memory[4096]==8'ha5&&chip.sector_locked==2'b10,"individual locks are honored without global unlock");
  chip.sr3_flags=0;chip.sr1_flags=0;chip.sr2_flags=0;chip.range_lock_enabled=0;
  before_e=erases;
  fork
   request(3,0,1,9);
   begin wait(erases==before_e+1);chip.memory[4095]=0;end
  join
  check(chip.memory[4095]==0,"erase verification includes last byte of all sixteen pages");
  request(3,0,1,0);fill(8'h69);before_p=programs;
  fork
   request(2,0,256,9);
   begin wait(programs==before_p+1);chip.memory[3]=chip.memory[3]^1;end
  join
  for(integer m=0;m<2;m++)begin
   id=m==0?24'h204018:24'h9d6018;request(0,0,1,0);check(identified&&jedec==id,"additional standard NOR IDs need no vendor whitelist");
   request(3,0,1,0);fill(8'(m+17));request(2,0,256,0);
  end
  protect=1;request(2,0,1,8'h21);protect=0;
  id=24'hffffff;request(0,0,1,0);check(!identified,"absent ID remains distinguishable");request(2,0,1,8'h21);
  check(chip.forbidden_writes==0,"no status changes, unlocks, or chip erase");
  $display("PASS tb_flash_compatibility checks=%0d half=%0d programs=%0d erases=%0d",checks,HALF,programs,erases);$finish;
 end
 initial begin #1000000000;$fatal(1,"compatibility timeout");end
endmodule
