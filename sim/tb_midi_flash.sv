`timescale 1ns/1ps
module tb_midi_flash;
 reg clk=0,rst=1,request=0,fail_io=0,flash_supported=1;always #10 clk=~clk;
 reg [1:0] command=0;reg [4:0] song=0,lookup=0;
 wire reqready,busy,init,done,lock,grant,we,inv,imp,sd,fr,fv,fd,bw;
 wire [7:0] error,se,fe,bi,bd,ri,rd;wire [15:0] job,sc;
 wire [1:0] js,fo;wire [31:0] entries,crc,duration,scrc;
 wire [23:0] fa;wire [8:0] fl;wire [11:0] sa;wire [95:0] sw,sr;
 wire valid,loaded,fmt,loaded_fmt;wire [4:0] loaded_id;wire [159:0] metadata;wire [15:0] count;
 reg [63:0] notes[0:2];reg [31:0] expected;integer checks=0,base_erases,base_programs;
 integer dump;reg [4095:0] outdir,filename;
 bluetooth_score_core #(.MAX_NOTES(4096),.MAX_VOICES(16)) core(
 .clk(clk),.rst(rst),.rx_valid(1'b0),.rx_data(8'd0),.rx_fault(1'b0),.tx_ready(1'b1),.event_ready(1'b1),
 .song_format(fmt),.storage_format(loaded_fmt),.song_valid(valid),.total_notes(count),.song_duration(duration),.song_crc(crc),.local_valid(1'b0),
 .storage_lock(lock),.storage_ready(grant),.storage_write(we),.storage_invalidate(inv),.storage_address(sa),.storage_wdata(sw),.storage_rdata(sr),
 .storage_import(imp),.storage_count(sc),.storage_crc(scrc),.storage_done(sd),.storage_error(se));
 flash_song_library #(.MAX_NOTES(4096)) lib(
 .clk(clk),.rst(rst),.request_valid(request),.request_ready(reqready),.command(command),.song_index(song),.song_name(56'd0),
 .busy(busy),.initialized(init),.job_id(job),.job_state(js),.error(error),.done(done),.entries(entries),.loaded_valid(loaded),.loaded_index(loaded_id),
 .lookup_index(lookup),.lookup_data(metadata),.ram_format(fmt),.storage_format(loaded_fmt),.ram_valid(valid),.ram_count(count),.ram_duration(duration),.ram_crc(crc),
 .storage_lock(lock),.storage_ready(grant),.storage_write(we),.storage_invalidate(inv),.storage_address(sa),.storage_wdata(sw),.storage_rdata(sr),
 .storage_import(imp),.storage_count(sc),.storage_crc(scrc),.storage_done(sd),.storage_error(se),.upload_active(1'b0),
 .flash_initialized(1'b1),.flash_supported(flash_supported),.flash_ready(fr),.flash_valid(fv),.flash_op(fo),.flash_address(fa),.flash_length(fl),.flash_done(fd),.flash_error(fe),
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
  @(negedge clk);core.song_format=0;core.song_valid=1;core.total_notes=3;core.expected_crc=~expected;core.duration_ms=5;
 end endtask
 task start(input [1:0] c,input [4:0] id);begin
  @(negedge clk);wait(reqready);command=c;song=id;request=1;@(negedge clk);request=0;
 end endtask
 task operation(input [1:0] c,input [4:0] id,input [7:0] e);begin start(c,id);wait(done);$display("job cmd=%0d id=%0d error=%h entries=%h",c,id,error,entries);check(error==e,"asynchronous job result");@(negedge clk);end endtask
 task old_song;begin
  check(entries[0],"old directory survives interrupted transaction");operation(1,0,0);
  check(valid && core.score_ram[0][39:32]==60 && count==3,"old song payload survives reset and reload");
 end endtask
 task seed_new;reg [95:0] w;begin
  expected=32'hffffffff;
  for(integer i=0;i<70;i++)begin w={16'd0,8'd0,8'(i%16),16'd200,8'd100,8'd60,32'(i*500)};core.score_ram[i]=w;
   for(integer k=0;k<12;k++)expected=cb(expected,w>>(k*8));end
  @(negedge clk);core.song_format=1;core.song_valid=1;core.total_notes=70;core.expected_crc=~expected;core.duration_ms=34700;
 end endtask
 initial begin
  #100 rst=0;wait(init && reqready);check(memory_model.erases==0,"boot read only");seed(0);operation(0,0,0);
  for(integer cut=0;cut<5;cut++)begin
   seed_new();start(0,1);
   case(cut)
    0:wait(lib.state==14 && lib.record_no==21 && lib.record_byte==3);
    1:wait(lib.state==14 && lib.record_no==42 && lib.record_byte==7);
    2:wait(lib.state==28);
    3:wait(lib.state==43);
    4:wait(memory_model.active && memory_model.operation==2 && memory_model.location<8192 && memory_model.location[11:0]==16 && memory_model.index==2);
   endcase
   reset_fpga();check(entries[0]&&!entries[1],"interrupted upgrade retains legacy directory");operation(1,0,0);check(fmt==0&&core.score_ram[0][39:32]==60,"old song readable after failed upgrade");
  end
  seed_new();operation(0,1,0);reset_fpga();check(entries==3&&lib.directory_extended,"version2 mixed directory selected after reboot");operation(1,1,0);
  check(fmt==1&&count==70&&duration==34700,"new record format and duration restored");
  for(integer i=0;i<70;i++)check(core.score_ram[i]=={16'd0,8'd0,8'(i%16),16'd200,8'd100,8'd60,32'(i*500)},"12-byte record survives page split");
  operation(1,0,0);check(fmt==0&&count==3,"mixed library old song remains old format");
  lookup=1;repeat(4)@(negedge clk);memory_model.memory[24'h010000+{metadata[15:8],16'd0}]^=1;
  operation(1,1,9);check(!valid&&!loaded,"bad new-format CRC invalidates RAM");
  $display("PASS tb_midi_flash checks=%0d",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"midi flash timeout state=%0d",lib.state);end
endmodule
