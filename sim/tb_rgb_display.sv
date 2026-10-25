`timescale 1ns/1ps
`include "check.svh"
module tb_rgb_display;
 reg ref_clk=0,audio_clk=0,pll_reset=1,audio_reset=1;
 always #10 ref_clk=~ref_clk;always #8.138020833 audio_clk=~audio_clk;
 reg [31:0] active=32'h8000003f,held=32'h80000003;
 reg [6:0] ep=25,rp=70,dp=50;reg [3:0] hz=5;
 wire pc,hs,vs,de;wire [5:0] r,g,b;
 reg [1132:0] frame_status;reg [19:0] latency_bcd=20'h00137;
 reg expected_de=0,older_de=0,next_de;integer px=0,py=0,older_x=0,older_y=0,nx,ny;
 integer checks=0,visible=0,lines=0,row=0;
 rgb_display dut(.ref_clk(ref_clk),.pll_reset(pll_reset),.audio_clk(audio_clk),.audio_reset(audio_reset),
  .voice_active(active),.voice_held(held),.selected_timbre(3'd1),.visual_sample_valid(1'b0),.visual_sample(16'sd0),.visual_notes(16'h0121),.score_busy(1'b0),.audio_ready(1'b1),
  .score_error(1'b0),.underrun(1'b0),.ghost(1'b0),.lcd_clk(pc),.lcd_hs(hs),.lcd_vs(vs),.lcd_en(de),
  .lcd_r(r),.lcd_g(g),.lcd_b(b),.menu_mode(1'b1),.effects_enabled(1'b1),.effect_mode(2'd1),
  .volume_percent(7'd100),.echo_percent(ep),.room_percent(rp),.depth_percent(dp),.tremolo_rate_hz(hz),
  .touch_enabled(1'b0),.touch_ui_enabled(1'b0),.touch_ready_status(1'b0),.touch_error_status(1'b0),
  .latency_valid(1'b1),.latency_bcd(latency_bcd));
 initial begin
  #200 pll_reset=0;wait(dut.pixel_lock);repeat(6)@(negedge dut.pixel_clk);
  `CHECK(!de && {r,g,b}==0,"audio reset blanks display despite locked pixel clock")
  audio_reset=0;wait(dut.status_valid);
  `CHECK(dut.pixel_status[11:0]=={6'd3,6'd7},"balanced popcount includes bit31")
  while(!dut.frame_start)@(negedge dut.pixel_clk);
  frame_status=dut.pixel_status;@(posedge dut.pixel_clk);#1;
  `CHECK(dut.renderer.state==frame_status && frame_status[1132:1112]=={1'b1,20'h00137},"frame captures original payload plus atomic latency")
  for(integer i=1;i<1192*533;i=i+1)begin
   @(posedge dut.pixel_clk);nx=dut.x;ny=dut.y;next_de=dut.de;#1;
   `CHECK(de===older_de,"three-stage pixel and DE stay aligned")
   `CHECK(hs && vs,"DE-only sync polarity preserved")
   `CHECK(dut.renderer.state==frame_status,"settings cannot tear current frame")
   `CHECK((^{r,g,b})!==1'bx,"all connector bits defined")
   if(de)begin
    visible=visible+1;row=row+1;
    if(older_x==799)begin `CHECK(row==800,"800 pixels in each active row") row=0;lines=lines+1;end
    if(older_x==464 && older_y==124)`CHECK({r,g,b}=={6'h35,6'h2e,6'h1e},"selected ROOM border reaches RGB666 output")
   end else `CHECK({r,g,b}==0,"porches stay black")
   older_de=expected_de;expected_de=next_de;older_x=px;older_y=py;px=nx;py=ny;
   if(i==1192*200)begin active=32'hffffffff;held=0;ep=100;rp=5;latency_bcd=20'h00258;end
  end
  `CHECK(visible==800*480 && lines==480 && row==0,"one full 800x480 connector frame")
  @(posedge dut.pixel_clk);#1;
  `CHECK(dut.renderer.state[5:0]==32 && dut.renderer.state[37:31]==5 && dut.renderer.state[1131:1112]==20'h00258,"next frame atomically publishes updated controls and latency")
  force dut.pixel_lock=0;#1;`CHECK(!de && {r,g,b}==0,"clock loss blanks without a new pixel edge")
  repeat(6)@(negedge ref_clk);release dut.pixel_lock;wait(!dut.pixel_reset);
  #3 pll_reset=1;#1;`CHECK(!de && {r,g,b}==0,"async reset safely blanks connector")
  $display("PASS tb_rgb_display checks=%0d visible=%0d",checks,visible);$finish;
 end
 initial begin #60000000;$fatal(1,"display timeout");end
endmodule
