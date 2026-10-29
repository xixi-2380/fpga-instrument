`timescale 1ns/1ps
module tb_sustain_direct;
 reg clk=0,rst=1,valid=0;always #5 clk=~clk;
 reg signed [15:0] sample=0;wire ready,ov;wire signed [15:0] out;
 integer checks=0,cycles;reg signed [15:0] expected;
 audio_effects #(.ECHO_ENABLE(0),.D0(3),.D1(4),.D2(5),.D3(6)) dut(
 .clk(clk),.rst(rst),.enable(1'b1),.mode(2'd0),.in_valid(valid),.in_sample(sample),.in_ready(ready),.out_valid(ov),.out_sample(out),
 .effect_mask(3'b001),.cfg_valid(1'b1),.cfg_echo_wet(9'd256),.cfg_room_wet(9'd0),.cfg_tremolo_depth(9'd0),.cfg_tremolo_rate_hz(5'd20),.cfg_echo_samples(15'd24000));
 initial begin
  repeat(3)@(negedge clk);rst=0;
  for(integer i=0;i<300;i++)begin
   wait(ready);@(negedge clk);sample=i[0]?-16000:16000;expected=sample;valid=1;
   @(negedge clk);valid=0;cycles=0;
   while(!ov)begin @(negedge clk);cycles++;if(cycles>24)$fatal(1,"dry onset waited for a delay tap");end
   if(out!==expected)$fatal(1,"sustain must not attenuate or delay the held dry waveform");checks++;
  end
  if(dut.phase_step!=1789570)$fatal(1,"20Hz LFO coefficient incorrect");
  $display("PASS tb_sustain_direct checks=%0d",checks);$finish;
 end
endmodule
