`timescale 1ns/1ps
`include "check.svh"
module tb_rgb_display;
 parameter integer THEME=0;
 reg ref_clk=0,audio_clk=0,pll_reset=1,audio_reset=1;
 always #10 ref_clk=~ref_clk;always #8.138020833 audio_clk=~audio_clk;
 reg [31:0] active=32'h8000003f,held=32'h80000003;
 reg [6:0] ep=25,rp=70,dp=50;reg [3:0] hz=5;
 wire pc,hs,vs,de;wire [5:0] r,g,b;
 reg [1111:0] frame_status;
 reg expected_de=0,next_de;integer px=0,py=0,nx,ny;
 reg [7:0] de_history=0;integer x_history[0:7],y_history[0:7];
 integer checks=0,visible=0,lines=0,row=0;
 rgb_display dut(.ref_clk(ref_clk),.pll_reset(pll_reset),.audio_clk(audio_clk),.audio_reset(audio_reset),
  .voice_active(active),.voice_held(held),.selected_timbre(3'd1),.visual_sample_valid(1'b0),.visual_sample(16'sd0),.visual_notes(16'h0121),.score_busy(1'b0),.audio_ready(1'b1),
  .score_error(1'b0),.underrun(1'b0),.ghost(1'b0),.lcd_clk(pc),.lcd_hs(hs),.lcd_vs(vs),.lcd_en(de),
  .lcd_r(r),.lcd_g(g),.lcd_b(b),.menu_mode(1'b1),.effects_enabled(1'b1),.effect_mode(2'd1),
  .echo_percent(ep),.room_percent(rp),.depth_percent(dp),.tremolo_rate_hz(hz),
  .theme_id(THEME[1:0]),.touch_enabled(1'b0),.touch_ui_enabled(1'b0),.touch_ready_status(1'b0),.touch_error_status(1'b0));
 initial begin
  #200 pll_reset=0;wait(dut.pixel_lock);repeat(6)@(negedge dut.pixel_clk);
  `CHECK(!de && {r,g,b}==0,"audio reset blanks display despite locked pixel clock")
  audio_reset=0;wait(dut.status_valid);
  `CHECK(dut.pixel_status[11:0]=={6'd3,6'd7},"balanced popcount includes bit31")
  while(!dut.frame_start)@(negedge dut.pixel_clk);
  frame_status=dut.pixel_status;@(posedge dut.pixel_clk);#1;
  `CHECK(dut.renderer.state==frame_status,"frame boundary captures full1112-bit atomic snapshot")
  for(integer i=1;i<1192*533;i=i+1)begin
   @(posedge dut.pixel_clk);nx=dut.x;ny=dut.y;next_de=dut.de;#1;
   `CHECK(de===expected_de,"ten-stage connector pixel and DE stay aligned")
   `CHECK(hs && vs,"DE-only sync polarity preserved")
   `CHECK(dut.renderer.state==frame_status,"settings cannot tear current frame")
   `CHECK((^{r,g,b})!==1'bx,"all connector bits defined")
   if(de)begin
    visible=visible+1;row=row+1;
    if(px==799)begin `CHECK(row==800,"800 pixels in each active row") row=0;lines=lines+1;end
    if(px==464 && py==124)`CHECK({r,g,b}==(THEME==3 ? {6'h22,6'h11,6'h14} : {6'h35,6'h2e,6'h1e}),"selected ROOM border reaches RGB666 output")
    if(THEME==3)begin
     if(px==516 && py==240)`CHECK(r>integer'(g)+2 && g>integer'(b)+2,"woman's face skin reaches actual RGB666 pins")
     if(px==510 && py==285)`CHECK(r>integer'(g)+4 && b>integer'(g)+2 && r>integer'(b)+2,"woman's pink shirt is present separately from the foot on RGB pins")
     if(px==680 && py==230)`CHECK(r>integer'(g)+2 && g>integer'(b)+2,"foreground foot reaches actual RGB666 pins")
    end
   end else `CHECK({r,g,b}==0,"porches stay black")
   expected_de=de_history[7];px=x_history[7];py=y_history[7];
   for(integer q=7;q>0;q=q-1)begin de_history[q]=de_history[q-1];x_history[q]=x_history[q-1];y_history[q]=y_history[q-1];end
   de_history[0]=next_de;x_history[0]=nx;y_history[0]=ny;
   if(i==1192*200)begin active=32'hffffffff;held=0;ep=100;rp=5;end
  end
  `CHECK(visible==800*480 && lines==480 && row==0,"one full 800x480 connector frame")
  @(posedge dut.pixel_clk);#1;
  `CHECK(dut.renderer.state[5:0]==32 && dut.renderer.state[37:31]==5,"next frame publishes updated voice count and settings")
  force dut.pixel_lock=0;#1;`CHECK(!de && {r,g,b}==0,"clock loss blanks without a new pixel edge")
  repeat(6)@(negedge ref_clk);release dut.pixel_lock;wait(!dut.pixel_reset);
  #3 pll_reset=1;#1;`CHECK(!de && {r,g,b}==0,"async reset safely blanks connector")
  $display("PASS tb_rgb_display checks=%0d visible=%0d",checks,visible);$finish;
 end
 initial begin #60000000;$fatal(1,"display timeout");end
endmodule
