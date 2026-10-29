`timescale 1ns/1ps
module tb_flash_recovery;
 reg clk=0,rst=1,ev=0,er=0,stuck=0;always #10 clk=~clk;
 reg [7:0] cmd=0;reg [8:0] len=0;reg [63:0] data=0;
 wire ready,rv,cs,sck,mosi,miso;wire [4:0] rlen;wire [159:0] response;
 integer programs,erases,checks=0;reg [159:0] last;
 score_services dut(.clk(clk),.rst(rst),.action_valid(1'b0),.action(4'd0),
 .song_valid(1'b1),.upload_active(1'b0),.play_state(2'd0),.total_notes(16'd1),.song_duration(32'd100),.song_crc(32'h81e319be),
 .local_ready(1'b1),.local_done(1'b0),.local_error(8'd0),.storage_ready(1'b1),.storage_rdata(64'h00647f3c00000000),
 .storage_done(1'b0),.storage_error(8'd0),.extension_valid(ev),.extension_ready(ready),.extension_command(cmd),.extension_length(len),.extension_payload(data),
 .extension_response_valid(rv),.extension_response_ready(er),.extension_response_length(rlen),.extension_response(response),
 .flash_cs_n(cs),.flash_sck(sck),.flash_mosi(mosi),.flash_miso(miso));
 defparam dut.flash.HALF_CYCLES=4;defparam dut.flash.BOOT_CYCLES=8;defparam dut.flash.POLL_CYCLES=8;defparam dut.flash.TIMEOUT_CYCLES=500000;
 spi_nor_model chip(clk,cs,sck,mosi,miso,24'hef4018,1'b0,stuck,programs,erases);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task request(input [7:0] code,input [8:0] n,input [7:0] expected);begin
  @(negedge clk);wait(ready);cmd=code;len=n;ev=1;@(negedge clk);ev=0;
  wait(rv);last=response;check(response[7:0]==expected,"protocol status");
  @(negedge clk);er=1;@(negedge clk);er=0;
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;wait(dut.library_init && dut.library_ready);
  request(8'h40,0,0);check(last[18],"initial writable");
  stuck=1;request(8'h40,0,0);check(last[127:120]==8'h22,"diagnostic carries the actual probe timeout");
  request(8'h42,8,8'h22);check(dut.job_id==0,"probe failure starts no erase job");
  stuck=0;request(8'h40,0,0);check(last[127:120]==0,"successful fresh probe clears only the diagnostic result");
  fork
   request(8'h42,8,0);
   begin wait(erases==1);stuck=1;end
  join
  wait(dut.library_done);check(dut.library_error==8'h22 && dut.s1[0],"busy timeout leaves cached WIP");
  @(negedge clk);stuck=0;repeat(1000)@(negedge clk);
  check(chip.busy_cycles==0 && !stuck,"actual NOR is idle again");
  for(integer i=0;i<3;i++)begin
   request(8'h40,0,0);check(!last[80] && last[18],"idle diagnostics refresh physical BUSY without reset");
  end
  fork
   request(8'h42,8,0);
   begin wait(erases==2);stuck=1;end
  join
  wait(dut.library_done);check(dut.library_error==8'h22,"second transient busy timeout");
  @(negedge clk);stuck=0;repeat(1000)@(negedge clk);
  // No diagnostic request between clearing busy and retrying SAVE.
  request(8'h42,8,0);wait(dut.library_done);
  check(dut.library_error==0 && dut.job_state==2 && dut.entries==1,"SAVE directly refreshes stale status and commits without reset");
  request(8'h40,0,0);check(last[18] && !last[80],"success leaves coherent fresh diagnostics");
  check(chip.forbidden_writes==0,"recovery emits no unlock or status writes");
  $display("PASS tb_flash_recovery checks=%0d diagnostic_refresh=1 direct_save_retry=1 no_reset=1",checks);$finish;
 end
 initial begin #200000000;$fatal(1,"timeout");end
endmodule
