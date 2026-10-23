`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
module tb_ui_score_handoff;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [3:0] buttons=15;reg [15:0] pressed=0;
 tri [3:0] columns;wire [3:0] rows,selected;wire pa;
 integer checks=0,score_events=0,key_events=0,frames=0;
 keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.SCORE_BEAT_FRAMES(4),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_LONG_PRESS_CYCLES(128),
  .LOCK_N(16),.SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2),
  .MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.RELEASE(2)) dut(
  .clk(clk),.rst(rst),.board_buttons_n(buttons),.key_row(rows),.key_col(columns),.MAX_SD_MODE());
 assign pa=dut.input_ready;
 for(genvar k=0;k<4;k=k+1)assign selected[k]=(columns[k]===1'b0);
 passive_matrix_model keyboard(pressed,selected,rows);
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  `CHECK(!dut.underrun,"score plus menu never underruns")
  if(dut.note_valid && dut.note_ready)begin
   if(dut.score_busy)score_events=score_events+1;else key_events=key_events+1;
  end
  if(dut.frame_ce)frames=frames+1;
 end
 task frames_more(input integer n);integer target;begin target=frames+n;wait(frames>=target);#1;end endtask
 task toggle_menu;begin buttons=14;repeat(256)@(negedge dut.audio_clk);buttons=15;repeat(12)@(negedge dut.audio_clk);end endtask
 initial begin
  #100 rst=0;wait(pa);frames_more(2);toggle_menu;
  `CHECK(dut.menu_mode && dut.score_busy,"menu available during automatic demo")
  pressed=16'h0200;frames_more(3);pressed=0;frames_more(2);
  pressed=16'h0080;frames_more(3);pressed=0;frames_more(2);
  wait(!dut.score_busy);frames_more(3);
  `CHECK(score_events==84 && key_events==0 && !dut.gate,"all score events complete while menu keys stay silent")
  `CHECK(dut.echo_percent==30 && dut.sound.effect.echo_target==77,"parameter edits during score survive handoff")
  pressed=16'h0200;frames_more(2);toggle_menu;frames_more(2);
  `CHECK(!dut.gate && dut.inhibit_notes,"held menu key stays blocked after demo and exit")
  pressed=0;frames_more(2);pressed=16'h0200;wait(dut.gate);frames_more(2);
  `CHECK(key_events>0,"manual keyboard resumes only after release and new press")
  pressed=0;wait(!dut.gate);frames_more(4);
  $display("PASS tb_ui_score_handoff checks=%0d score_events=%0d",checks,score_events);$finish;
 end
 initial begin #10000000;$fatal(1,"UI score handoff timeout");end
endmodule
