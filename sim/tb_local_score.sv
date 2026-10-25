`timescale 1ns/1ps
module tb_local_score;
 reg clk=0,rst=1,lock=0,we=0,inv=0,imp=0,lv=0;
 reg [3:0] address=0;reg [63:0] wdata=0;reg [1:0] command=0;
 wire grant,sd,lr,ld,valid,upload,ev;wire [7:0] se,le;wire [1:0] play;
 wire [31:0] duration,checksum;reg [31:0] expected;
 integer checks=0,ons=0;reg [63:0] records[0:2];
 always #10 clk=~clk;
 bluetooth_score_core #(.MAX_NOTES(16),.MAX_VOICES(16)) dut(
 .clk(clk),.rst(rst),.rx_valid(1'b0),.rx_data(8'd0),.rx_fault(1'b0),.tx_ready(1'b1),
 .event_valid(ev),.event_ready(1'b1),.song_valid(valid),.upload_active(upload),.play_state(play),
 .local_valid(lv),.local_command(command),.local_ready(lr),.local_done(ld),.local_error(le),
 .storage_lock(lock),.storage_ready(grant),.storage_write(we),.storage_invalidate(inv),
 .storage_address(address),.storage_wdata(wdata),.storage_import(imp),.storage_count(16'd3),.storage_crc(expected),
 .storage_done(sd),.storage_error(se),.song_duration(duration),.song_crc(checksum));
 function automatic [31:0] cb(input [31:0] c,input [7:0] b);reg [31:0] x;
 begin x=c^b;for(integer k=0;k<8;k++)x=(x>>1)^(x[0]?32'hedb88320:0);cb=x;end endfunction
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task load(input bit corrupt);begin
  @(negedge clk);lock=1;wait(grant);inv=1;@(negedge clk);inv=0;
  for(integer k=0;k<3;k++)begin address=k;wdata=records[k]^(corrupt && k==1?64'd1:64'd0);we=1;@(negedge clk);end
  we=0;imp=1;@(negedge clk);imp=0;wait(sd);@(negedge clk);
 end endtask
 task control(input [1:0] c);begin @(negedge clk);command=c;lv=1;wait(lr);@(posedge clk);#1;@(negedge clk);lv=0;wait(ld);@(negedge clk);end endtask
 always @(posedge clk)if(!rst && ev && dut.event_kind==1)ons++;
 initial begin
  records[0]={16'd5,8'd127,8'd60,32'd0};records[1]={16'd5,8'd32,8'd60,32'd0};records[2]={16'd3,8'd90,8'd64,32'd2};
  expected=32'hffffffff;for(integer i=0;i<3;i++)for(integer k=0;k<8;k++)expected=cb(expected,records[i]>>(8*k));expected=~expected;
  #100 rst=0;load(0);check(valid && se==0 && duration==5 && checksum==expected,"Flash/RAM import uses common format/CRC/overlap validation");
  lv=1;command=0;repeat(5)@(negedge clk);check(!lr && play==0,"storage lock excludes local playback");lv=0;lock=0;
  control(0);wait(ons==2);check(play==1 && !upload,"local playback works without any HELLO or phone");
  control(1);check(play==2,"independent local pause");control(2);check(play==1,"independent local resume");
  control(3);check(play==0,"independent local stop");
  load(1);check(!valid && se==9,"bad stored payload fails CRC and cannot retain stale song validity");
  lock=0;control(0);check(le==8'h0e && play==0,"invalid imported RAM cannot play");
  $display("PASS tb_local_score checks=%0d",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"local control timeout state=%0d play=%0d valid=%0d ons=%0d lock=%0d",dut.state,play,valid,ons,lock);end
endmodule
