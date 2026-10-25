`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
// Repeated USR/download-equivalent reset without stopping the reference clock.
// Production 32-voice render and I2S cadence; shortened startup/envelope/score.
// Explicit behavioral PLL substitute in the runner, not a timing simulation.
module tb_audio_restart;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [15:0] pressed=0;reg [3:0] buttons=15;
 tri [3:0] columns;wire [3:0] selected,rows;
 integer checks=0,ons=0,offs=0,key_ons=0,key_offs=0,frames=0;
 integer old_on,old_off,old_key_on,old_key_off;
 keyboard_top #(.LCD_ENABLE(1),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),
  .SCORE_BEAT_FRAMES(4),.LOCK_N(16),.MUTE(4),.FADE(4),
  .ATTACK(2),.DECAY(2),.RELEASE(2),.BUTTON_DEBOUNCE_CYCLES(2),
  .BUTTON_LONG_PRESS_CYCLES(128),.SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2)) dut(
  .clk(clk),.rst(rst),.board_buttons_n(buttons),.key_row(rows),.key_col(columns));
 for(genvar k=0;k<4;k=k+1)assign selected[k]=(columns[k]===1'b0);
 passive_matrix_model keyboard(pressed,selected,rows);
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  `CHECK(!dut.underrun && !dut.score_error,"restarts and LCD activity cannot underrun or corrupt score")
  if(dut.frame_ce)frames=frames+1;
  if(dut.visual_sample_valid)`CHECK((^dut.visual_sample)!==1'bx,"post-effect PCM remains defined")
  if(dut.note_valid && dut.note_ready)begin
   if(dut.score_busy)begin if(dut.note_on)ons=ons+1;else offs=offs+1;end
   else begin if(dut.note_on)key_ons=key_ons+1;else key_offs=key_offs+1;end
  end
 end
 task more_frames(input integer n);integer target;begin target=frames+n;wait(frames>=target);@(negedge dut.audio_clk);end endtask
 initial begin
  for(integer run=0;run<3;run=run+1)begin
   old_on=ons;old_off=offs;old_key_on=key_ons;old_key_off=key_offs;
   rst=1;pressed=0;buttons=15;#213;
   `CHECK(dut.audio_reset && !dut.gate,"USR asserts reset and clears held ownership")
   rst=0;wait(dut.input_ready);
   // Cycle a visual theme during playback; it cannot edit the score state.
   more_frames(2);buttons=11;repeat(12)@(negedge dut.audio_clk);buttons=15;
   wait(!dut.score_busy);more_frames(6);
   `CHECK(ons-old_on==42 && offs-old_off==42,"all 42 onsets and 42 releases survive every restart")
   `CHECK(dut.voice_held==0 && dut.voice_active==0 && dut.sound.frame_l==0 && dut.sound.frame_r==0,"score drains to exactly silent stereo after each restart")
   pressed=16'h0200;wait(dut.gate);more_frames(3);pressed=0;
   wait(!dut.gate);more_frames(8);
   `CHECK(key_ons-old_key_on==1 && key_offs-old_key_off==1,"manual key has one matched release after each score")
   `CHECK(dut.voice_active==0 && dut.sound.frame_l==0 && dut.sound.frame_r==0,"manual release finishes after each repeated startup")
  end
  $display("PASS tb_audio_restart checks=%0d score_on=%0d score_off=%0d key_on=%0d key_off=%0d",checks,ons,offs,key_ons,key_offs);$finish;
 end
 initial begin #30000000;$fatal(1,"restart regression timeout");end
endmodule
