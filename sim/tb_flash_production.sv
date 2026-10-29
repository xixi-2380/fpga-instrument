`timescale 1ns/1ps
module tb_flash_production;
 reg clk=0,rst=1,ev=0,er=0;always #10 clk=~clk;
 reg [7:0] cmd=0;reg [8:0] len=0;reg [63:0] data=0;
 wire ready,rv,cs,sck,mosi,miso,lock,grant,we,inv,imp,sd;
 wire [4:0] rlen;wire [159:0] response;wire [7:0] se;wire [11:0] sa;wire [63:0] sw,sr;
 wire [15:0] count,sc;wire [31:0] crc,duration,scrc;wire valid;
 integer programs,erases,checks=0,progress_fd;reg [4095:0] outdir,progress_name;reg [31:0] expected;reg [63:0] expected_word;
 bluetooth_score_core #(.MAX_NOTES(4096),.MAX_VOICES(16)) core(
 .clk(clk),.rst(rst),.rx_valid(1'b0),.rx_data(8'd0),.rx_fault(1'b0),.tx_ready(1'b1),.event_ready(1'b1),
 .song_valid(valid),.total_notes(count),.song_duration(duration),.song_crc(crc),.local_valid(1'b0),
 .storage_lock(lock),.storage_ready(grant),.storage_write(we),.storage_invalidate(inv),.storage_address(sa),.storage_wdata(sw),.storage_rdata(sr),
 .storage_import(imp),.storage_count(sc),.storage_crc(scrc),.storage_done(sd),.storage_error(se));
 score_services dut(.clk(clk),.rst(rst),.action_valid(1'b0),.action(4'd0),
 .song_valid(valid),.upload_active(1'b0),.play_state(2'd0),.total_notes(count),.song_duration(duration),.song_crc(crc),
 .local_ready(1'b1),.local_done(1'b0),.local_error(8'd0),
 .storage_lock(lock),.storage_ready(grant),.storage_write(we),.storage_invalidate(inv),.storage_address(sa),.storage_wdata(sw),.storage_rdata(sr),
 .storage_import(imp),.storage_count(sc),.storage_crc(scrc),.storage_done(sd),.storage_error(se),
 .extension_valid(ev),.extension_ready(ready),.extension_command(cmd),.extension_length(len),.extension_payload(data),
 .extension_response_valid(rv),.extension_response_ready(er),.extension_response_length(rlen),.extension_response(response),
 .flash_cs_n(cs),.flash_sck(sck),.flash_mosi(mosi),.flash_miso(miso));
 // All driver timing parameters remain production defaults (50MHz / HALF=25).
 spi_nor_model #(.PROGRAM_BUSY_CYCLES(50000),.ERASE_BUSY_CYCLES(100000)) chip(
 clk,cs,sck,mosi,miso,24'hc84018,1'b0,1'b0,programs,erases);
 function automatic [31:0] cb(input [31:0] c,input [7:0] b);reg [31:0] x;
 begin x=c^b;for(integer k=0;k<8;k++)x=(x>>1)^(x[0]?32'hedb88320:0);cb=x;end endfunction
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s error=%h",why,dut.library_error);end endtask
 task request(input [7:0] code,input [8:0] n);begin
  @(negedge clk);wait(ready);cmd=code;len=n;ev=1;@(negedge clk);ev=0;
  wait(rv);check(response[7:0]==0,"protocol response");@(negedge clk);er=1;@(negedge clk);er=0;
 end endtask
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir=".";
  $sformat(progress_name,"%0s/progress.log",outdir);progress_fd=$fopen(progress_name,"w");
  $fwrite(progress_fd,"START production half=25 count=4096\n");$fflush(progress_fd);
  repeat(5)@(negedge clk);rst=0;wait(dut.library_init && dut.library_ready);
  check(erases==0,"initial directory scan never formats storage");$fwrite(progress_fd,"BOOT_SCAN_DONE %0t\n",$time);$fflush(progress_fd);
  expected=32'hffffffff;
  for(integer i=0;i<4096;i++)begin
   expected_word={16'd1,8'd100,8'(60+i%12),32'(i*2)};core.score_ram[i]=expected_word;
   for(integer k=0;k<8;k++)expected=cb(expected,expected_word>>(8*k));
  end
  @(negedge clk);core.song_valid=1;core.total_notes=4096;core.expected_crc=~expected;core.duration_ms=8191;
  request(8'h42,8);wait(dut.library_done);check(dut.library_error==0 && dut.job_state==2,"4096-note 1MHz SAVE commits after readback");
  check(programs==134 && erases==9,"full payload uses 128 payload pages and bounded directory operations");
  $fwrite(progress_fd,"FULL_SAVE_DONE %0t programs=%0d erases=%0d\n",$time,programs,erases);$fflush(progress_fd);
  $display("FULL_SAVE programs=%0d erases=%0d sim_clock=%0t",programs,erases,$time);
  @(negedge clk);rst=1;repeat(5)@(negedge clk);rst=0;wait(dut.library_init && dut.library_ready);
  check(dut.entries[0] && !valid,"directory survives FPGA reset while RAM is invalid");request(8'h43,1);wait(dut.library_done);
  check(dut.library_error==0 && valid && count==4096 && duration==8191 && crc==~expected,"1MHz LOAD validates the full saved song in the real core");
  for(integer i=0;i<4096;i++)check(core.score_ram[i]=={16'd1,8'd100,8'(60+i%12),32'(i*2)},"each restored record matches");
  check(chip.forbidden_writes==0,"no unlock/status writes or chip erase");
  $fwrite(progress_fd,"LOAD_VERIFIED %0t\n",$time);$fclose(progress_fd);
  $display("PASS tb_flash_production checks=%0d half=25 count=4096 programs=%0d erases=%0d",checks,programs,erases);$finish;
 end
 initial begin #10000000000;$fatal(1,"production Flash timeout");end
endmodule
