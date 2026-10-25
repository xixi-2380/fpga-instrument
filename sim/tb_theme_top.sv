`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
// Two real audio engines receive identical notes. Theme operations are applied
// to just one engine; every serialized bit and PCM sample must remain equal.
module tb_theme_top;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [3:0] buttons=15;reg [15:0] pressed=0;
 tri [3:0] col_a,col_b;wire [3:0] row_a,row_b,sel_a,sel_b;
 wire bck_a,ws_a,din_a,bck_b,ws_b,din_b;
 integer checks=0,frames=0,samples=0,events=0;
 keyboard_top #(.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.SCORE_BEAT_FRAMES(4),
  .BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_LONG_PRESS_CYCLES(128),.LOCK_N(16),
  .SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2),
  .MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.RELEASE(2)) dut(
  .clk(clk),.rst(rst),.board_buttons_n(buttons),.key_row(row_a),.key_col(col_a),
  .MAX_BCLK(bck_a),.MAX_LRCLK(ws_a),.MAX_DIN(din_a));
 keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.SCORE_BEAT_FRAMES(4),
  .BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_LONG_PRESS_CYCLES(128),.LOCK_N(16),
  .SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2),
  .MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.RELEASE(2)) reference_audio(
  .clk(clk),.rst(rst),.board_buttons_n(4'hf),.key_row(row_b),.key_col(col_b),
  .MAX_BCLK(bck_b),.MAX_LRCLK(ws_b),.MAX_DIN(din_b));
 for(genvar k=0;k<4;k=k+1)begin
  assign sel_a[k]=col_a[k]===1'b0;assign sel_b[k]=col_b[k]===1'b0;
 end
 passive_matrix_model matrix_a(pressed,sel_a,row_a),matrix_b(pressed,sel_b,row_b);
 always @(posedge dut.audio_clk)begin #1;
  if(!dut.audio_reset)begin
   `CHECK(!dut.underrun && !reference_audio.underrun,"themes cannot underrun either audio engine")
   `CHECK({bck_a,ws_a,din_a}==={bck_b,ws_b,din_b},"all standard I2S output bits identical despite theme changes")
   `CHECK({dut.effects_enabled,dut.effect_mode,dut.selected_timbre,dut.menu_mode,dut.voice_held}===
    {reference_audio.effects_enabled,reference_audio.effect_mode,reference_audio.selected_timbre,reference_audio.menu_mode,reference_audio.voice_held},"theme operations preserve held voices and all audio control state")
   if(dut.frame_ce)frames=frames+1;
   if(dut.visual_sample_valid)begin
    `CHECK(reference_audio.visual_sample_valid && dut.visual_sample===reference_audio.visual_sample,"post-effect PCM samples remain bit exact")
    samples=samples+1;
   end
   if(dut.note_valid && dut.note_ready)events=events+1;
  end
 end
 task cycles(input integer n);begin repeat(n)@(negedge dut.audio_clk);end endtask
 task frames_more(input integer n);integer target;begin target=frames+n;wait(frames>=target);#2;end endtask
 task short_key(input integer k);begin buttons=15^(1<<k);cycles(12);buttons=15;cycles(12);end endtask
 task long3;begin buttons=7;cycles(260);buttons=15;cycles(12);end endtask
 initial begin
  #100 rst=0;wait(dut.input_ready);frames_more(4);
  `CHECK(dut.score_busy,"theme test begins during automatic score")
  short_key(2);`CHECK(dut.theme_id==1,"cat selectable during auto score")
  long3;`CHECK(dut.theme_id==3 && dut.score_busy,"hidden theme does not interrupt automatic playback")
  long3;`CHECK(dut.theme_id==1,"hidden exit restores preceding cat")
  wait(dut.score_done);frames_more(4);
  `CHECK(events==84,"all automatic score events survive visual controls")
  pressed=16'h0011;wait($countones(dut.voice_held)==2);frames_more(4);
  repeat(4)begin short_key(2);short_key(1);long3;long3;end
  `CHECK(dut.theme_id==1 && $countones(dut.voice_held)==2,"normal and hidden cycles preserve real held chord")
  wait(dut.lcd_on.display_driver.status_valid);cycles(40);
  `CHECK(dut.lcd_on.display_driver.pixel_status[55:54]==1,"theme bits cross existing atomic display bridge")
  frames_more(1800);
  `CHECK(dut.lcd_on.display_driver.renderer.state[55:54]==1,"LCD frame captures selected theme")
  `CHECK(dut.lcd_on.display_driver.renderer.animation_phase!=0,"actual LCD frame cadence advances visual animation clocks")
  pressed=0;wait(!dut.gate);frames_more(8);
  `CHECK(dut.voice_active==0 && samples>1900,"no stuck notes after theme animation and release")
  $display("PASS tb_theme_top checks=%0d samples=%0d events=%0d",checks,samples,events);$finish;
 end
 initial begin #60000000;$fatal(1,"theme top timeout");end
endmodule
