`timescale 1ns/1ps
`include "check.svh"
module tb_ec11_controls;
 reg clk=0,rst=1,ready=1;always #5 clk=~clk;
 reg [2:0] up=0,down=0,single_click=0,double_click=0;
 wire [2:0] mask,packet_mask;wire es,tr;wire [10:0] ms;wire [8:0] ew,rw,td;wire [16:0] samples;
 wire [6:0] ep,rp,dp;wire [4:0] hz,packet_hz;wire [15:0] bcd;wire cv;
 integer checks=0;reg [51:0] held;
 timbre_control #(.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(20)) dut(
  .clk(clk),.rst(rst),.buttons_n(4'hf),.ui_action_valid(1'b0),.ui_action(6'd63),.cfg_ready(ready),
  .encoder_up(up),.encoder_down(down),.encoder_single(single_click),.encoder_double(double_click),
  .effect_mask(mask),.cfg_effect_mask(packet_mask),.echo_edit_strength(es),.tremolo_edit_rate(tr),
  .echo_time_ms(ms),.echo_time_bcd(bcd),.cfg_echo_samples(samples),
  .echo_percent(ep),.room_percent(rp),.depth_percent(dp),.tremolo_rate_hz(hz),
  .echo_wet(ew),.room_wet(rw),.tremolo_depth(td),.cfg_tremolo_rate_hz(packet_hz),.cfg_valid(cv));
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task event_send(input integer kind,input [2:0] bits);begin
  @(negedge clk);case(kind)0:up=bits;1:down=bits;2:single_click=bits;3:double_click=bits;endcase
  @(negedge clk);up=0;down=0;single_click=0;double_click=0;cycles(4);
 end endtask
 initial begin
  #12;rst=0;cycles(5);`CHECK(mask==0 && ms==150 && bcd==12'h150 && !es && !tr,"all effects off; default edit modes")
  repeat(20)event_send(1,1);`CHECK(ms==20 && samples==960 && mask==0,"turn edits time without enabling")
  for(integer n=30;n<=2000;n=n+10)begin
   event_send(0,1);`CHECK(ms==n && bcd==((n/1000)*4096+((n/100)%10)*256+((n/10)%10)*16+n%10) && samples==n*48,"every time step/BCD/sample conversion")
  end
  event_send(0,1);`CHECK(ms==2000,"time clamps at 2000ms")
  event_send(2,1);`CHECK(es,"echo click selects intensity")
  event_send(0,1);`CHECK(ep==26 && ew==67,"one percent amount maps precisely")
  repeat(110)event_send(0,1);`CHECK(ep==100,"echo amount upper clamp")
  repeat(110)event_send(1,1);`CHECK(ep==0,"echo amount lower clamp")
  event_send(0,2);`CHECK(rp==26 && rw==67,"room rotation changes its own amount")
  event_send(0,4);`CHECK(dp==51,"tremolo default rotation is depth")
  event_send(2,4);event_send(0,4);`CHECK(tr && hz==6,"tremolo click selects rate")
  repeat(24)event_send(0,4);`CHECK(hz==20,"rate upper clamp")
  repeat(24)event_send(1,4);`CHECK(hz==1,"rate lower clamp")
  event_send(3,1);event_send(3,2);event_send(3,4);
  `CHECK(mask==7 && packet_mask==7,"all three independent effects enabled together")
  event_send(3,2);`CHECK(mask==5,"turning room off preserves echo and tremolo")
  ready=0;event_send(0,2);cycles(3);held={packet_mask,samples,ew,rw,td,packet_hz};
  event_send(0,1);event_send(3,2);event_send(0,4);
  `CHECK(cv && {packet_mask,samples,ew,rw,td,packet_hz}==held,"entire extended config packet stable under backpressure")
  ready=1;cycles(8);`CHECK(packet_mask==7 && samples==96000 && ew==3 && rw==69 && packet_hz==2,"newest complete settings coalesce after acceptance")
  $display("PASS tb_ec11_controls checks=%0d",checks);$finish;
 end
endmodule
