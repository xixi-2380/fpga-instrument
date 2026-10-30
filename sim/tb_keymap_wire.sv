`timescale 1ns/1ps
module tb_keymap_wire;
 parameter integer HALF=25,VENDOR=0;
 reg clk=0;always #10 clk=~clk;reg rst=1,save=0;wire ready,lv;wire [575:0] map;reg [591:0] data=0;wire [31:0] status;
 wire busy,fv,fr,fd,bw,fi,fs;wire [1:0] op;wire [23:0] addr,jedec;wire [8:0] len;wire [7:0] error,bi,bd,ri,rd,s1,s2,s3;
 wire cs,sck,mosi,miso,wp,hold_n;integer programs,erases,checks=0;
 flash_keymap d(clk,rst,fi,fs,1'b1,jedec,save,ready,data,lv,1'b1,map,status,busy,fv,fr,op,addr,len,fd,error,bw,bi,bd,ri,rd);
 spi_nor_flash #(.HALF_CYCLES(HALF),.REGION_LAST('h221fff),.BOOT_CYCLES(8),.POLL_CYCLES(8)) driver(
  clk,rst,fv,fr,op,addr,len,1'b1,fd,error,fi,fs,jedec,s1,s2,s3,bw,bi,bd,ri,rd,cs,sck,mosi,miso,wp,hold_n);
 spi_nor_model #(.BYTES('h222000)) chip(clk,cs,sck,mosi,miso,VENDOR?24'hc84018:24'hef4018,1'b0,1'b0,programs,erases);
 task check(input bit b,input [255:0] why);begin checks++;if(!b)$fatal(1,"%0s state=%d error=%h",why,d.state,status);end endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;wait(ready);check(programs==0 && erases==0,"boot read only");
  data={16'd1,map};data[15:0]={8'd15,8'd21};data[575:560]={8'd31,8'd108};
  @(negedge clk);save=1;@(negedge clk);save=0;wait(!busy);check(status[17:16]==2,"verified body/commit");check(programs==2 && erases==1,"bounded writes");
  @(negedge clk);rst=1;repeat(5)@(negedge clk);rst=0;wait(ready);check(map==data[575:0],"wire reset load");check(programs==2 && erases==1,"reset read only");check(chip.forbidden_writes==0,"no status or chip erase");
  $display("PASS tb_keymap_wire checks=%0d SPI HALF=%0d vendor=%0d",checks,HALF,VENDOR);$finish;
 end
 initial begin #200000000;$fatal(1,"wire timeout");end
endmodule
