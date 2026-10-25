`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
module tb_ui_top;
 parameter integer LCD=0;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [3:0] buttons=15;reg [15:0] pressed=0;
 tri [3:0] columns;wire [3:0] rows,selected;
 tri scl,sda,tint,trst;wire bck,ws,din,pa;wire [4:0] leds;
 integer checks=0,events=0,frames=0,before_events;
 keyboard_top #(.LCD_ENABLE(LCD),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.SCORE_ENABLE(0),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_LONG_PRESS_CYCLES(128),
  .LOCK_N(16),.SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2),
  .MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.SUSTAIN(32768),.RELEASE(2)) dut(
  .clk(clk),.rst(rst),.board_buttons_n(buttons),.key_row(rows),.key_col(columns),
  .MAX_BCLK(bck),.MAX_LRCLK(ws),.MAX_DIN(din),.MAX_SD_MODE(),.led_n(leds),
  .touch_scl(scl),.touch_sda(sda),.touch_int(tint),.touch_rst_n(trst));
 assign pa=dut.input_ready;
 wire [63:0] displayed;
 wire display_valid;
 if(LCD)begin: observe_display
  assign displayed=dut.lcd_on.display_driver.pixel_status;
  assign display_valid=dut.lcd_on.display_driver.status_valid;
 end else begin assign displayed=0;assign display_valid=0;end
 for(genvar k=0;k<4;k=k+1)assign selected[k]=(columns[k]===1'b0);
 passive_matrix_model keyboard(pressed,selected,rows);
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  `CHECK(!dut.underrun,"menu changes never underrun audio")
  if(dut.note_valid && dut.note_ready)events=events+1;
  if(dut.frame_ce)frames=frames+1;
 end
 task cycles(input integer n);begin repeat(n)@(negedge dut.audio_clk);end endtask
 task more_frames(input integer n);integer target;begin target=frames+n;wait(frames>=target);#1;end endtask
 task menu_button;begin buttons=14;cycles(256);buttons=15;cycles(10);end endtask
 task menu_key(input integer k);begin pressed=16'b1<<k;more_frames(2);pressed=0;more_frames(2);end endtask
 initial begin
  #100 rst=0;wait(pa);more_frames(4);
  `CHECK({scl,sda,tint,trst}===4'bzzzz,"disabled touch leaves all four signals high impedance")
  buttons=13;cycles(12);buttons=15;cycles(12);
  pressed=16'h0200;wait(dut.gate);more_frames(2);
  `CHECK(dut.selected_timbre==1 && $countones(dut.voice_held)==1,"flute note before menu")
  menu_button;more_frames(4);
  `CHECK(dut.menu_mode && !dut.gate && dut.voice_active==0,"entering menu drains held note and release tail")
  `CHECK(dut.selected_timbre==1 && dut.echo_percent==25,"held entry key is not a menu action; long S0 preserves timbre")
  pressed=0;more_frames(2);before_events=events;
  menu_key(4);menu_key(9);
  `CHECK(dut.effects_enabled && dut.effect_mode==0 && dut.echo_percent==30 && dut.sound.effect.echo_target==77,"matrix action reaches runtime audio target")
  pressed=16'h0200;more_frames(4);`CHECK(dut.echo_percent==35,"one adjustment for held menu key")
  more_frames(4);`CHECK(dut.echo_percent==35,"no repeat while menu key held")
  pressed=0;more_frames(2);menu_key(6);menu_key(10);menu_key(8);
  `CHECK(dut.effect_mode==2 && dut.tremolo_rate_hz==4 && dut.depth_percent==45,"menu controls independent tremolo parameters")
  `CHECK(dut.sound.effect.phase_step==357914 && dut.sound.effect.depth_target==115,"full parameter tuple accepted by effect engine")
  `CHECK(events==before_events && !dut.gate,"menu navigation never generates note events")
  buttons=7;cycles(256);buttons=15;cycles(10);
  `CHECK(dut.effect_mode==0,"S3 cycles from current UI state")
  pressed=16'h0008;more_frames(3);
  `CHECK(!dut.menu_mode && dut.inhibit_notes && !dut.gate,"exit key cannot sound while held")
  pressed=0;more_frames(2);pressed=16'h0200;wait(dut.gate);more_frames(2);
  `CHECK(dut.sound.voice_timbres[1:0]==1,"play resumes with selected timbre after release")
  pressed=0;wait(!dut.gate);more_frames(5);
  `CHECK(dut.voice_active==0,"no stuck voice after play-menu-play transition")
  if(LCD)begin
   wait(display_valid);cycles(40);
   `CHECK(displayed[30:24]==35 && displayed[13:12]==1 && displayed[22:20]==0,
    "real top wiring transfers final parameters, timbre and mode to pixel domain")
  end
  $display("PASS tb_ui_top checks=%0d frames=%0d events=%0d",checks,frames,events);$finish;
 end
 initial begin #5000000;$fatal(1,"UI top timeout");end
endmodule
