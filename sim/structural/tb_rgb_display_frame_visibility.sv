`timescale 1ns/1ps
`include "check.svh"
module tb_rgb_display_frame_visibility;
 parameter integer FRAME_LOCKED=0;
 reg [2591:0] pcb_source=0;
 reg ref_clk=0,audio_clk=0,pll_reset=1,audio_reset=1;
 always #10 ref_clk=~ref_clk;always #8.138020833 audio_clk=~audio_clk;
 reg [31:0] active=32'h8000003f,held=32'h80000003;
 reg [6:0] ep=25,rp=70,dp=50;reg [4:0] hz=20;
 wire pc,hs,vs,de;wire [5:0] r,g,b;
 reg [1206:0] frame_status;
 reg [4:0] de_history=0;reg next_de;
 integer x_history[0:4],y_history[0:4];integer nx,ny;
 initial for(integer j=0;j<5;j++)begin x_history[j]=0;y_history[j]=0;end
 reg [19:0] latency_bcd=20'h00137;
 reg [33:0] sensor_status={1'b0,1'b1,3'd3,7'd20,7'd80,3'd2,12'h125};
 integer checks=0,visible=0,lines=0,row=0;
 rgb_display #(.FRAME_LOCKED_SNAPSHOTS(FRAME_LOCKED)) dut(.ref_clk(ref_clk),.pll_reset(pll_reset),.audio_clk(audio_clk),.audio_reset(audio_reset),
  .voice_active(active),.voice_held(held),.selected_timbre(3'd1),.visual_sample_valid(1'b0),.visual_sample(16'sd0),.visual_notes(36'h0121),.score_busy(1'b0),.audio_ready(1'b1),
  .score_error(1'b0),.underrun(1'b0),.ghost(1'b0),.lcd_clk(pc),.lcd_hs(hs),.lcd_vs(vs),.lcd_en(de),
  .lcd_r(r),.lcd_g(g),.lcd_b(b),.menu_mode(1'b1),.effects_enabled(1'b1),.effect_mode(2'd1),
  .volume_percent(7'd100),.echo_percent(ep),.room_percent(rp),.depth_percent(dp),.tremolo_rate_hz(hz),
  .touch_enabled(1'b0),.touch_ui_enabled(1'b0),.touch_ready_status(1'b0),.touch_error_status(1'b0),
  .latency_valid(1'b1),.latency_bcd(latency_bcd),.ultrasonic_status(sensor_status),.sustain_time_thousands(4'd2),.encoder_status({12'h000,5'd0}),.keypad_online(3'b101),.more_status(146'd0),.pcb_status(pcb_source));

 reg injected_frame=0;
 task frame;
  begin
   @(negedge dut.pixel_clk);injected_frame=1;
   @(negedge dut.pixel_clk);injected_frame=0;
   repeat(3)@(negedge dut.pixel_clk);
  end
 endtask
 task settle;
  begin repeat(80)@(negedge dut.pixel_clk);end
 endtask
 initial begin
  #200 pll_reset=0;wait(dut.pixel_lock);audio_reset=0;
  wait(!dut.pixel_reset);repeat(3)@(negedge dut.pixel_clk);
  force dut.render_frame_start=injected_frame;
  // Independent status bridge readiness must not expose an unknown PCB payload.
  force dut.status_valid=1'b1;force dut.pcb_valid=1'b0;force dut.pixel_pcb={2592{1'bx}};
  frame();
  `CHECK(dut.renderer.pcb_visible===1'b0,"PCB invalid masks unknown resetless payload even if main bridge is valid")
  force dut.pixel_pcb={2592{1'b1}};frame();
  `CHECK(dut.renderer.pcb_visible===1'b0,"PCB invalid masks stale all-one resetless payload")
  release dut.pixel_pcb;release dut.pcb_valid;release dut.status_valid;
  // Restart real handshakes, then use actual source capture through the CDC.
  @(negedge audio_clk);audio_reset=1;pcb_source=0;
  repeat(5)@(negedge audio_clk);audio_reset=0;wait(!dut.pixel_reset);settle();
  frame();settle();frame();settle();
  `CHECK(dut.renderer.pcb_visible===1'b0 && dut.pcb_visible===1'b0,"initial closed snapshot is not visible")
  pcb_source[2560]=1;settle();frame();settle();frame();settle();
  `CHECK(dut.renderer.pcb_visible===1'b1 && dut.pcb_visible===1'b1,"opened snapshot reaches renderer and acknowledgement")
  pcb_source[2560]=0;settle();
  if(FRAME_LOCKED!=0)begin
   // Retire the already captured open snapshot; the next pending one is closed.
   frame();settle();
  end
  `CHECK(dut.renderer.pcb_visible===1'b1 && dut.pcb_visible===1'b1,"close source data does not acknowledge before actual frame commit")
  if(FRAME_LOCKED!=0)begin
   `CHECK(dut.pcb_bridge.ack_sync[1]===1'b1,"closed snapshot is held ready before the commit boundary")
  end else begin
   `CHECK(dut.pixel_pcb[2560]===1'b0,"legacy bridge has already received close while renderer still holds old frame")
  end
  frame();settle();
  `CHECK(dut.renderer.pcb_visible===1'b0 && dut.pcb_visible===1'b0,"closed snapshot acknowledgement follows actual renderer visibility")
  @(negedge audio_clk);audio_reset=1;#2;
  `CHECK(dut.renderer.pcb_visible===1'b0,"reset closes visible PCB state")
  $display("PASS tb_rgb_display_frame_visibility checks=%0d frame_locked=%0d",checks,FRAME_LOCKED);$finish;
 end
 initial begin #200000;$fatal(1,"frame visibility timeout");end
endmodule
