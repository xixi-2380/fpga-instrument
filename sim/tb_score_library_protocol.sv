`timescale 1ns/1ps
module tb_score_library_protocol;
 reg clk=0,rst=1,valid=0,rr=0,initialized=1,supported=1,writable=1,busy=0,local_busy=0;
 always #5 clk=~clk;
 reg [7:0] command=0;reg [8:0] len=0;reg [63:0] data=0;
 wire ready,response_valid,job_valid;wire [4:0] response_len,index,lookup;
 wire [159:0] response;reg [159:0] metadata=0;wire [1:0] operation;wire [55:0] name;
 reg [15:0] job=41;reg [1:0] state=2;integer checks=0,starts=0,probes=0;
 wire probe_valid;reg probe_done=0;reg [7:0] probe_error=0;
 score_library_protocol dut(.clk(clk),.rst(rst),.request_valid(valid),.request_ready(ready),.command(command),.length(len),.payload(data),
 .response_valid(response_valid),.response_ready(rr),.response_length(response_len),.response(response),.initialized(initialized),.supported(supported),.writable(writable),
 .library_busy(busy),.local_busy(local_busy),.storage_ready(1'b1),.jedec_id(24'hef4018),.status1(8'd0),.status2(8'd0),.status3(8'd0),.library_error(8'd0),
 .job_id(job),.job_state(state),.ram_crc(32'h12345678),.library_valid(job_valid),.library_ready(1'b1),.library_command(operation),.library_index(index),.library_name(name),
 .lookup_index(lookup),.lookup_data(metadata),.probe_valid(probe_valid),.probe_ready(1'b1),.probe_done(probe_done),.probe_error(probe_error));
 always @(posedge clk)begin
  metadata<={8'd0,56'h31303053,32'h87654321,32'd500,16'(lookup+10),8'd2,8'd1};
  probe_done<=probe_valid;if(probe_valid)probes++;
  if(!rst && job_valid)begin job<=job+1'b1;state<=1;starts++;end
 end
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task request(input [7:0] cmd,input [8:0] n,input [63:0] payload,input [7:0] error);begin
  @(negedge clk);wait(ready);command=cmd;len=n;data=payload;valid=1;@(negedge clk);valid=0;
  wait(response_valid);check(response[7:0]==error,"extension result status");
 end endtask
 task consume;begin @(negedge clk);rr=1;@(negedge clk);rr=0;end endtask
 initial begin
  #12 rst=0;request(8'h40,0,0,0);check(response_len==20 && response[23:16]==31 && response[79:56]==24'hef4018 && response[159:128]==32'h12345678,"capability wire offsets");consume();
  request(8'h41,1,7,0);check(response_len==20 && response[15:8]==7 && response[39:24]==17 && response[103:72]==32'h87654321,"synchronous catalog lookup wire offsets");consume();
  request(8'h42,8,64'hff00,6);consume();request(8'h42,7,0,3);consume();request(8'h42,8,32,6);consume();
  busy=1;request(8'h42,8,0,5);consume();busy=0;supported=0;request(8'h42,8,0,8'h21);consume();supported=1;
  writable=0;request(8'h44,1,0,8'h21);consume();writable=1;
  request(8'h42,8,2,0);check(response_len==3 && response[23:8]==42 && starts==1 && operation==0 && index==2,"one asynchronous SAVE startup");consume();
  request(8'h45,8,{32'h12345678,8'd2,8'd0,16'd42},0);check(response[31:24]==1 && response[95:88]==0,"busy task never claims persistent success");consume();
  state=2;request(8'h45,8,{32'h12345678,8'd2,8'd0,16'd42},0);check(response[31:24]==2 && response[95:88]==1,"only completed SAVE claims persistence");consume();
  request(8'h45,8,{32'h12345679,8'd2,8'd0,16'd42},8'h28);consume();
  job=43;request(8'h45,8,{32'h12345678,8'd2,8'd0,16'd42},8'h28);consume();
  check(starts==1,"invalid requests and polling cannot create additional erase jobs");
  check(probes==4,"idle diagnostics and each valid write refresh physical status");
  supported=0;writable=0;request(8'h43,1,2,0);
  check(starts==2 && operation==1,"LOAD does not require write-capable identity");consume();
  probe_error=8'h22;request(8'h40,0,0,0);
  check(response[127:120]==8'h22,"idle diagnosis reports the new physical probe failure");consume();
  request(8'h42,8,0,8'h22);consume();
  check(starts==2,"failed probe never starts a write or replaces a tracked job");
  $display("PASS tb_score_library_protocol checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"extension timeout");end
endmodule
