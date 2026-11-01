`timescale 1ns/1ps
module tb_sustain_controls;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [2:0] up=0,down=0,single=0;reg ready=1;
 wire [10:0] ms;wire [15:0] bcd;wire [16:0] samples;
 wire [4:0] rate,cfg_rate;wire valid;integer checks=0;
 timbre_control #(.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(8)) dut(
  .clk(clk),.rst(rst),.buttons_n(4'hf),.ui_action_valid(1'b0),.ui_action(6'd63),.cfg_ready(ready),
  .encoder_up(up),.encoder_down(down),.encoder_single(single),.encoder_double(3'd0),
  .echo_time_ms(ms),.echo_time_bcd(bcd),.cfg_echo_samples(samples),.tremolo_rate_hz(rate),.cfg_tremolo_rate_hz(cfg_rate),.cfg_valid(valid),
  .auto_valid(1'b0),.auto_version(8'd0),.auto_target(7'd0));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task turn(input [2:0] a,input bit reverse);begin
  @(negedge clk);up=reverse?0:a;down=reverse?a:0;@(negedge clk);up=0;down=0;repeat(5)@(negedge clk);
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;repeat(5)@(negedge clk);
  repeat(220)turn(3'b001,0);
  check(ms==2000 && bcd==16'h2000 && samples==96000,"2s control, four-digit display and17-bit sample count do not wrap");
  repeat(25)turn(3'b001,1);check(ms==1750 && bcd==16'h1750 && samples==84000,"upper-range values retain exact time andBCD");
  repeat(200)turn(3'b001,1);check(ms==20 && bcd==16'h0020 && samples==960,"sustain minimum remains20ms");
  @(negedge clk);single=4;@(negedge clk);single=0;
  repeat(30)turn(3'b100,0);check(rate==20 && cfg_rate==20,"tremolo reaches20Hz without four-bit truncation");
  repeat(30)turn(3'b100,1);check(rate==1,"tremolo lower bound remains1Hz");
  $display("PASS tb_sustain_controls checks=%0d",checks);$finish;
 end
endmodule
