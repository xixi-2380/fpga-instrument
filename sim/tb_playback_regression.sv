`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
module tb_playback_regression;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [15:0] pressed=0;tri [3:0] columns;wire [3:0] rows,selected;
 reg command_valid=0;reg [5:0] command=63;
 integer checks=0,frames=0;reg idle_check=0;
 keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),
 .LOCK_N(16),.SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2),
 .MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.SUSTAIN(32768),.RELEASE(2)) dut(
 .clk(clk),.rst(rst),.bt_rx(1'b1),.board_buttons_n(4'hf),.key_row(rows),.key_col(columns));
 for(genvar k=0;k<4;k=k+1)assign selected[k]=(columns[k]===1'b0);
 passive_matrix_model keyboard(pressed,selected,rows);
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  if(dut.frame_ce)frames=frames+1;
  `CHECK(!dut.underrun,"gain stage stays inside frame budget")
  if(idle_check && dut.visual_sample_valid)
   `CHECK(dut.visual_sample==0,"released idle produces exact digital zero")
 end
 task more(input integer n);integer target;begin target=frames+n;wait(frames>=target);#1;end endtask
 task act(input [6:0] action);begin
  @(negedge dut.audio_clk);command=action;command_valid=1;
  @(negedge dut.audio_clk);command_valid=0;
 end endtask
 initial begin
  force dut.ui_action_valid=command_valid;force dut.ui_action=command;
  #100 rst=0;wait(dut.input_ready);more(5);idle_check=1;more(100);idle_check=0;
  for(integer k=0;k<16;k=k+1)begin
   pressed=16'b1<<k;more(5);
   `CHECK(dut.keys==(16'b1<<k) && $countones(dut.voice_held)==1 && dut.visual_notes==(16'b1<<k),"each single key has exactly one matching highlighted voice")
   pressed=0;more(8);
   `CHECK(dut.voice_held==0 && dut.voice_active==0 && dut.visual_notes==0,"all voices and highlights clear after release")
  end
  for(integer c=0;c<4;c=c+1)begin
   pressed=16'h1111<<c;more(6);
   `CHECK($countones(dut.voice_held)==4 && dut.visual_notes==(16'h1111<<c),"four physical columns retain distinct matching four-note sets")
   pressed=0;more(8);
  end
  more(66);idle_check=1;more(100);idle_check=0;
  pressed=16'h0200;more(8);repeat(20)act(19);more(270);
  `CHECK(dut.volume_percent==0 && dut.gate,"volume mute leaves note ownership intact")
  idle_check=1;more(20);idle_check=0;
  repeat(20)act(20);more(270);
  `CHECK(dut.volume_percent==100 && dut.gate,"volume returns to unity without retrigger")
  pressed=0;more(76);idle_check=1;more(100);
  $display("PASS tb_playback_regression checks=%0d",checks);$finish;
 end
 initial begin #40000000;$fatal(1,"playback regression timeout");end
endmodule
