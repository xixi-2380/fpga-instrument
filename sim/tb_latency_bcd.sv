`timescale 1ns/1ps
module tb_latency_bcd;
 reg clk=0,rst=1,cancel=0,note=0,done=0;always #5 clk=~clk;
 reg [16:0] tag=0;wire [16:0] render_tag;wire valid;wire [19:0] bcd;
 reg [23:0] artificial_time=0;integer checks=0;
 audio_latency_meter #(.CLOCK_HZ(1000000)) dut(clk,rst,cancel,note,7'd60,1'b0,1'b0,7'd0,done,tag,render_tag,valid,bcd);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task measure(input [23:0] start_tick,end_tick,input [19:0] expected);begin
  @(negedge clk);artificial_time=start_tick;force dut.ticks=artificial_time;note=1;
  @(negedge clk);note=0;tag={1'b1,dut.epoch};artificial_time=end_tick;done=1;
  @(negedge clk);done=0;repeat(20)@(negedge clk);
  check(valid && bcd==expected,"five BCD digits, saturation and timestamp wrap");release dut.ticks;
 end endtask
 initial begin
  #12 rst=0;measure(0,1234,20'h01234);measure(0,99999,20'h99999);
  measure(0,100000,20'h99999);measure(24'hfffffe,24'h000003,20'h00005);
  @(negedge clk);note=1;@(negedge clk);note=0;tag={1'b1,dut.epoch-16'd1};done=1;
  @(negedge clk);done=0;repeat(20)@(negedge clk);check(dut.awaiting,"stale tag cannot finish newer On");
  cancel=1;@(negedge clk);cancel=0;check(!dut.awaiting,"urgent clear cancels measurement");
  $display("PASS tb_latency_bcd checks=%0d",checks);$finish;
 end
endmodule
