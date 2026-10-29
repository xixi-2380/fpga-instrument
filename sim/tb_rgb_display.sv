`timescale 1ns/1ps
`include "check.svh"
module tb_rgb_display;
 reg ref_clk=0,audio_clk=0,pll_reset=1,audio_reset=1;
 always #10 ref_clk=~ref_clk;always #8.138020833 audio_clk=~audio_clk;
 reg [31:0] active=32'h8000003f,held=32'h80000003;
 reg [6:0] ep=25,rp=70,dp=50;reg [3:0] hz=5;
 wire pc,hs,vs,de;wire [5:0] r,g,b;
 reg [1206:0] frame_status;
 reg [4:0] de_history=0;reg next_de;
 integer x_history[0:4],y_history[0:4];integer nx,ny;
 initial for(integer j=0;j<5;j++)begin x_history[j]=0;y_history[j]=0;end
 reg [19:0] latency_bcd=20'h00137;
 reg [33:0] sensor_status={1'b0,1'b1,3'd3,7'd20,7'd80,3'd2,12'h125};
 integer checks=0,visible=0,lines=0,row=0;
 rgb_display dut(.ref_clk(ref_clk),.pll_reset(pll_reset),.audio_clk(audio_clk),.audio_reset(audio_reset),
  .voice_active(active),.voice_held(held),.selected_timbre(3'd1),.visual_sample_valid(1'b0),.visual_sample(16'sd0),.visual_notes(36'h0121),.score_busy(1'b0),.audio_ready(1'b1),
  .score_error(1'b0),.underrun(1'b0),.ghost(1'b0),.lcd_clk(pc),.lcd_hs(hs),.lcd_vs(vs),.lcd_en(de),
  .lcd_r(r),.lcd_g(g),.lcd_b(b),.menu_mode(1'b1),.effects_enabled(1'b1),.effect_mode(2'd1),
  .volume_percent(7'd100),.echo_percent(ep),.room_percent(rp),.depth_percent(dp),.tremolo_rate_hz(hz),
  .touch_enabled(1'b0),.touch_ui_enabled(1'b0),.touch_ready_status(1'b0),.touch_error_status(1'b0),
  .latency_valid(1'b1),.latency_bcd(latency_bcd),.ultrasonic_status(sensor_status),.encoder_status({12'h150,5'd0}),.keypad_online(3'b101),.more_status(146'd0),.pcb_status(2592'd0));
 initial begin
  #200 pll_reset=0;wait(dut.pixel_lock);repeat(6)@(negedge dut.pixel_clk);
  `CHECK(!de && {r,g,b}==0,"audio reset blanks display despite locked pixel clock")
  audio_reset=0;wait(dut.status_valid);
  `CHECK(dut.pixel_status[11:0]=={6'd3,6'd7},"balanced popcount includes bit31")
  while(!dut.render_frame_start)@(negedge dut.pixel_clk);
  frame_status=dut.pixel_status;@(posedge dut.pixel_clk);#1;
  `CHECK(dut.renderer.state==frame_status && frame_status[1132:1112]=={1'b1,20'h00137},"frame captures original payload plus atomic latency")
  `CHECK(frame_status[1166:1133]==sensor_status,"complete ultrasonic tuple appended atomically")
  for(integer i=1;i<1192*533;i=i+1)begin
   @(posedge dut.pixel_clk);nx=dut.x;ny=dut.y;next_de=dut.de;#1;
   `CHECK(de===de_history[4],"registered coordinates, four renderer stages plus connector register keep pixel and DE aligned")
   `CHECK(hs && vs,"DE-only sync polarity preserved")
   `CHECK(dut.renderer.state==frame_status,"settings cannot tear current frame")
   `CHECK((^{r,g,b})!==1'bx,"all connector bits defined")
   if(de)begin
    visible=visible+1;row=row+1;
    if(x_history[4]==799)begin `CHECK(row==800,"800 pixels in each active row") row=0;lines=lines+1;end
    if(x_history[4]==464 && y_history[4]==124)`CHECK({r,g,b}=={6'h35,6'h2e,6'h1e},"selected ROOM border reaches RGB666 output")
   end else `CHECK({r,g,b}==0,"porches stay black")
   de_history={de_history[3:0],next_de};
   for(integer j=4;j>0;j--)begin x_history[j]=x_history[j-1];y_history[j]=y_history[j-1];end
   x_history[0]=nx;y_history[0]=ny;
   if(i==1192*200)begin active=32'hffffffff;held=0;ep=100;rp=5;latency_bcd=20'h00258;sensor_status=0;end
  end
  `CHECK(visible==800*480 && lines==480 && row==0,"one full 800x480 connector frame")
  @(posedge dut.pixel_clk);#1;
  `CHECK(dut.renderer.state[5:0]==32 && dut.renderer.state[37:31]==5 && dut.renderer.state[1131:1112]==20'h00258,"next frame atomically publishes updated controls and latency")
  `CHECK(dut.renderer.state[1166:1133]==sensor_status,"next frame updates sensor settings and distance together")
  force dut.pixel_lock=0;#1;`CHECK(!de && {r,g,b}==0,"clock loss blanks without a new pixel edge")
  repeat(6)@(negedge ref_clk);release dut.pixel_lock;wait(!dut.pixel_reset);
  #3 pll_reset=1;#1;`CHECK(!de && {r,g,b}==0,"async reset safely blanks connector")
  $display("PASS tb_rgb_display checks=%0d visible=%0d",checks,visible);$finish;
 end
 initial begin #60000000;$fatal(1,"display timeout");end
endmodule
