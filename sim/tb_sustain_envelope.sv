`timescale 1ns/1ps
module tb_sustain_envelope;
 reg clk=0,rst=1,ce=1,on=0,off=0,enable=1,base_active=1;
 reg [16:0] base_level=0,duration=96000,q=174,rem=73216;
 reg [8:0] strength=256;wire [16:0] level;wire active;
 integer checks=0;
 always #5 clk=~clk;
 sustain_envelope dut(clk,rst,ce,on,off,enable,base_level,base_active,duration,q,rem,strength,level,active);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task release_note(input [16:0] n,input [16:0] seed);begin
  @(negedge clk);on=1;@(negedge clk);on=0;base_level=seed;
  duration=n;q=16777216/n;rem=16777216%n;off=1;
  @(negedge clk);off=0;base_level=0;base_active=0;
 end endtask
 initial begin
  repeat(2)@(negedge clk);rst=0;
  release_note(96000,0);
  repeat(64)@(negedge clk);
  check(active && level>8000,"release during Attack still produces a smoothly rising audible tail");
  repeat(47936)@(negedge clk);
  check(active && level>=8100 && level<=8400,"two-second release is approximately half amplitude at one second");
  repeat(47999)@(negedge clk);
  check(active,"release remains owned until its final sample");
  @(negedge clk);check(!active && level==0,"release completes at exactly96000 samples without inherited native tail");
  release_note(960,65536);repeat(959)@(negedge clk);check(active,"20ms lower range retains its last sample");
  @(negedge clk);check(!active && level==0,"20ms release ends at exact duration");
  release_note(24000,65536);repeat(20)@(negedge clk);enable=0;
  repeat(260)@(negedge clk);check(!active && level==0,"disabling sustain fades the outstanding tail smoothly");
  enable=0;base_active=1;base_level=1234;@(negedge clk);on=1;@(negedge clk);on=0;
  check(level==1234 && active,"disabled effect retains the instrument envelope");
  repeat(600)@(negedge clk);base_level=0;base_active=0;enable=1;off=1;
  @(negedge clk);off=0;repeat(8)@(negedge clk);
  check(!active && level==0,"releasing a long-held naturally silent note must not resurrect it");
  $display("PASS tb_sustain_envelope checks=%0d",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"sustain envelope timeout");end
endmodule
