`timescale 1ns/1ps
module tb_flash_song_library;
 reg clk=0,rst=1,request=0,fail_io=0;always #10 clk=~clk;
 reg [1:0] command=0;reg [4:0] song=0,lookup=0;
 wire reqready,busy,init,done,lock,grant,we,inv,imp,sd,fr,fv,fd,bw;
 wire [7:0] error,se,fe,bi,bd,ri,rd;wire [15:0] job,sc;
 wire [1:0] js,fo;wire [31:0] entries,crc,duration,scrc;
 wire [23:0] fa;wire [8:0] fl;wire [11:0] sa;wire [63:0] sw,sr;
 wire valid,loaded;wire [4:0] loaded_id;wire [159:0] metadata;wire [15:0] count;
 reg [63:0] notes[0:2];reg [31:0] expected;integer checks=0,base_erases,base_programs;
 integer dump;reg [4095:0] outdir,filename;
 bluetooth_score_core #(.MAX_NOTES(4096),.MAX_VOICES(16)) core(
 .clk(clk),.rst(rst),.rx_valid(1'b0),.rx_data(8'd0),.rx_fault(1'b0),.tx_ready(1'b1),.event_ready(1'b1),
 .song_valid(valid),.total_notes(count),.song_duration(duration),.song_crc(crc),.local_valid(1'b0),
 .storage_lock(lock),.storage_ready(grant),.storage_write(we),.storage_invalidate(inv),.storage_address(sa),.storage_wdata(sw),.storage_rdata(sr),
 .storage_import(imp),.storage_count(sc),.storage_crc(scrc),.storage_done(sd),.storage_error(se));
 flash_song_library #(.MAX_NOTES(4096)) lib(
 .clk(clk),.rst(rst),.request_valid(request),.request_ready(reqready),.command(command),.song_index(song),.song_name(56'd0),
 .busy(busy),.initialized(init),.job_id(job),.job_state(js),.error(error),.done(done),.entries(entries),.loaded_valid(loaded),.loaded_index(loaded_id),
 .lookup_index(lookup),.lookup_data(metadata),.ram_valid(valid),.ram_count(count),.ram_duration(duration),.ram_crc(crc),
 .storage_lock(lock),.storage_ready(grant),.storage_write(we),.storage_invalidate(inv),.storage_address(sa),.storage_wdata(sw),.storage_rdata(sr),
 .storage_import(imp),.storage_count(sc),.storage_crc(scrc),.storage_done(sd),.storage_error(se),.upload_active(1'b0),
 .flash_initialized(1'b1),.flash_supported(1'b1),.flash_ready(fr),.flash_valid(fv),.flash_op(fo),.flash_address(fa),.flash_length(fl),.flash_done(fd),.flash_error(fe),
 .buffer_write(bw),.buffer_index(bi),.buffer_wdata(bd),.read_index(ri),.read_data(rd));
 buffered_nor_model memory_model(clk,rst,fv,fr,fo,fa,fl,fd,fe,fail_io,bw,bi,bd,ri,rd);
 function automatic [31:0] cb(input [31:0] c,input [7:0] b);reg [31:0] x;
 begin x=c^b;for(integer k=0;k<8;k++)x=(x>>1)^(x[0]?32'hedb88320:0);cb=x;end endfunction
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s state=%0d e=%h",why,lib.state,error);end endtask
 task reset_fpga;begin @(negedge clk);rst=1;repeat(4)@(negedge clk);rst=0;wait(init && reqready);@(negedge clk);end endtask
 // Seed a known valid RAM song, without a phone session; separate core tests
 // exercise its public import port. No forced internals used for persistence.
 task seed(input integer semitone);begin
  expected=32'hffffffff;
  for(integer i=0;i<3;i++)begin
   notes[i]={16'd5,8'd100,8'(60+semitone+i),32'd0};
   for(integer k=0;k<8;k++)expected=cb(expected,notes[i]>>(8*k));
   core.score_ram[i]=notes[i];
  end
  @(negedge clk);core.song_valid=1;core.total_notes=3;core.expected_crc=~expected;core.duration_ms=5;
 end endtask
 task start(input [1:0] c,input [4:0] id);begin
  @(negedge clk);wait(reqready);command=c;song=id;request=1;@(negedge clk);request=0;
 end endtask
 task operation(input [1:0] c,input [4:0] id,input [7:0] e);begin start(c,id);wait(done);$display("job cmd=%0d id=%0d error=%h entries=%h",c,id,error,entries);check(error==e,"asynchronous job result");@(negedge clk);end endtask
 task old_song;begin
  check(entries[0],"old directory survives interrupted transaction");operation(1,0,0);
  check(valid && core.score_ram[0][39:32]==60 && count==3,"old song payload survives reset and reload");
 end endtask
 initial begin
  if(!$value$plusargs("SIM_OUT_DIR=%s",outdir))outdir="reports/library_integration/library_transactions";
  #100 rst=0;wait(init && reqready);check(entries==0 && memory_model.erases==0,"empty boot scan is read-only");
  seed(0);operation(0,0,0);check(entries==1 && js==2,"first save is persistent only after verified directory commit");
  lookup=0;repeat(3)@(negedge clk);check(metadata[31:16]==3 && metadata[95:64]==~expected,"catalog metadata reports actual stored record count/CRC");
  reset_fpga();old_song();
  seed(2);operation(0,1,0);reset_fpga();check(entries==3,"multiple songs survive reboot");
  operation(1,1,0);check(core.score_ram[0][39:32]==62 && loaded && loaded_id==1,"independent song selection/load");
  operation(2,1,0);reset_fpga();check(entries==1,"atomic deletion survives reboot");old_song();
  // Fail before payload completion: old directory remains untouched.
  seed(4);start(0,0);wait(lib.state==15);fail_io=1;wait(done);check(error!=0,"I/O failure cannot claim persisted success");fail_io=0;reset_fpga();old_song();
  // Power cuts at data erase/program, inactive directory erase/program,
  // directory verification and each of the four marker bytes.
  for(integer cut=0;cut<10;cut++)begin
   seed(4);start(0,0);
   case(cut)
    0:wait(memory_model.active && memory_model.operation==3 && memory_model.location>=24'h010000);
    1:wait(memory_model.active && memory_model.operation==2 && memory_model.location>=24'h010000 && memory_model.index==7);
    2:wait(memory_model.active && memory_model.operation==3 && memory_model.location<24'h002000);
    3:wait(memory_model.active && memory_model.operation==2 && memory_model.location<24'h002000 && memory_model.index==20);
    4:wait(lib.state==39 && lib.verify_directory);
    9:wait(lib.state==44);
    default:begin wait(memory_model.active && memory_model.operation==2 && memory_model.location[11:0]==16);wait(memory_model.index==cut-5);end
   endcase
   reset_fpga();
   if(cut<9)old_song();
   else begin operation(1,0,0);check(core.score_ram[0][39:32]==64,"complete commit marker selects complete new song after reset");end
  end
  // Exercise every page of a production-size song, not just a short fixture.
  expected=32'hffffffff;
  for(integer i=0;i<4096;i++)begin
   core.score_ram[i]={16'd1,8'd127,8'd60,32'(i*2)};
   for(integer k=0;k<8;k++)expected=cb(expected,core.score_ram[i]>>(8*k));
  end
  @(negedge clk);core.song_valid=1;core.total_notes=4096;core.expected_crc=~expected;core.duration_ms=8191;
  operation(0,2,0);reset_fpga();operation(1,2,0);
  check(count==4096 && duration==8191 && core.score_ram[4095][31:0]==8190,"4096-note song crosses all 128 payload pages and validates after reset");
  seed(0);
  for(integer i=0;i<32;i++)if(!entries[i])operation(0,5'(i),0);
  check(entries==32'hffffffff,"all 32 logical entries can be occupied");
  operation(0,0,0);reset_fpga();check(entries==32'hffffffff,"full-library replacement has a spare physical slot and remains atomic");
  operation(1,2,0);check(count==4096,"replacing one entry preserves other full-sized songs");
  $sformat(filename,"%0s/flash_image.bin",outdir);dump=$fopen(filename,"wb");
  for(integer i=0;i<2228224;i++)$fwrite(dump,"%c",memory_model.memory[i]);$fclose(dump);
  lookup=0;repeat(3)@(negedge clk);
  memory_model.memory[24'h010000+{metadata[15:8],16'd0}]=memory_model.memory[24'h010000+{metadata[15:8],16'd0}]^8'd1;
  operation(1,0,9);check(!valid && !loaded,"corrupt payload cannot leave a valid partial RAM song");
  for(integer b=0;b<2;b++)for(integer i=0;i<4;i++)memory_model.memory[b*4096+16+i]=0;
  base_erases=memory_model.erases;reset_fpga();check(entries==0 && error==8'h24 && memory_model.erases==base_erases,"corrupt directories report error without automatic erase/format");
  $display("PASS tb_flash_song_library checks=%0d programs=%0d erases=%0d",checks,memory_model.programs,memory_model.erases);$finish;
 end
 initial begin #100000000;$fatal(1,"library timeout state=%0d offset=%0d",lib.state,lib.offset);end
endmodule
