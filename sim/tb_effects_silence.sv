`timescale 1ns/1ps
module tb_effects_silence;
 reg clk=0,rst=1,valid=0;always #5 clk=~clk;
 reg signed [15:0] sample=0;wire ready,pv;wire signed [15:0] pcm;
 integer checks=0,nonzero=0,late=0;
 audio_effects #(.ECHO_ENABLE(0)) dut(.clk(clk),.rst(rst),.in_valid(valid),.in_sample(sample),
 .in_ready(ready),.out_valid(pv),.out_sample(pcm),.enable(1'b1),.mode(2'd1),.effect_mask(3'b110),
 .cfg_valid(1'b1),.cfg_echo_wet(9'd0),.cfg_room_wet(9'd256),.cfg_tremolo_depth(9'd256),.cfg_tremolo_rate_hz(5'd20),.cfg_echo_samples(15'd7200));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task tick(input signed [15:0] value);begin
  @(negedge clk);wait(ready);sample=value;valid=1;@(negedge clk);valid=0;
  wait(pv);@(negedge clk);
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(integer pass=0;pass<2;pass++)begin
   repeat(300)tick(0);tick(pass==0?32767:-32768);
   nonzero=0;late=0;
   for(integer n=0;n<40000;n++)begin tick(0);if(pcm!=0)begin nonzero++;if(n>=36000)late++;end end
   check(nonzero>0,"production-length combs produce a real reverb tail");
   check(late==0 && pcm==0,"positive/negative impulse residue decays to exact zero without a timeout mute");
  end
  $display("PASS tb_effects_silence checks=%0d",checks);$finish;
 end
 initial begin #20000000;$fatal(1,"effect silence timeout");end
endmodule
