`timescale 1ns/1ps
`include "check.svh"
`include "passive_matrix_model.svh"
module tb_british_top;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [3:0] buttons=15;reg [15:0] pressed=0;
 tri [3:0] columns;wire [3:0] rows,selected;wire pa,bck,lrclk,din;
 integer checks=0,frames=0,events=0,tap_count=0,windows=0;reg [6:0] seen=0;
 wire [1111:0] displayed;
 keyboard_top #(.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.SCORE_ENABLE(0),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_LONG_PRESS_CYCLES(128),
  .LOCK_N(16),.SLOT_CYCLES(32),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(2),
  .MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.RELEASE(2)) dut(
  .clk(clk),.rst(rst),.board_buttons_n(buttons),.key_row(rows),.key_col(columns),
  .MAX_BCLK(bck),.MAX_LRCLK(lrclk),.MAX_DIN(din),.MAX_SD_MODE());
 assign pa=dut.input_ready;
 assign displayed=dut.lcd_on.display_driver.pixel_status;
 for(genvar k=0;k<4;k=k+1)assign selected[k]=(columns[k]===1'b0);
 passive_matrix_model keyboard(pressed,selected,rows);
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  `CHECK(!dut.underrun,"all seven presets and large display CDC cannot underrun")
  if(dut.frame_ce)frames=frames+1;
  if(dut.note_valid && dut.note_ready && dut.note_on)begin seen[dut.event_timbre]=1;events=events+1;end
  if(dut.visual_sample_valid)begin
   `CHECK(dut.visual_sample===dut.sound.effect_sample,"display observes post-effect samples")
   tap_count=tap_count+1;
  end
  if(dut.lcd_on.display_driver.monitor.window_valid)windows=windows+1;
 end
 task more_frames(input integer n);integer target;begin target=frames+n;wait(frames>=target);#1;end endtask
 task toggle;begin
 @(negedge dut.audio_clk);force dut.touch_action_valid=1;force dut.touch_action=6'd7;
 @(negedge dut.audio_clk);release dut.touch_action_valid;release dut.touch_action;repeat(10)@(negedge dut.audio_clk);
 end endtask
 task key(input integer n);begin pressed=16'b1<<n;more_frames(2);pressed=0;more_frames(2);end endtask
 initial begin
  #100 rst=0;wait(pa);more_frames(4);
  for(integer t=0;t<7;t=t+1)begin
   toggle;more_frames(2);
   `CHECK(dut.menu_mode,"screen command enters parameter page")
   if(t!=0)key(14);
   `CHECK(dut.selected_timbre==t,"matrix next reaches all seven identities")
   key(15);`CHECK(!dut.menu_mode,"return restores play mode")
   pressed=16'h0001;wait(dut.gate);more_frames(8);
   for(integer v=0;v<32;v=v+1)if(dut.voice_held[v])begin
    `CHECK(dut.sound.voice_timbres[v*3+:3]==t,"new timbre crosses note/allocator interfaces")
   end
   `CHECK(dut.visual_notes[0],"actual held C4 is highlighted")
   pressed=0;wait(!dut.gate);more_frames(3);
   `CHECK(dut.visual_notes==0,"note display clears while release tails may continue")
  end
  `CHECK(seen==127 && events==7,"all seven presets accepted without truncation or menu notes")
  pressed=16'h0011;wait($countones(dut.voice_held)==2);more_frames(600);
  wait(dut.lcd_on.display_driver.status_valid);more_frames(4);
  `CHECK(windows>0 && tap_count>512,"visual windows acquired from real engine output")
  `CHECK(displayed[53] && displayed[13:12]==2 && displayed[79:64]==16'h0011,"atomic pixel snapshot contains new ID6 and real chord")
  `CHECK(displayed[1111:88]!=0 && displayed[87:80]>0,"real post-effect waveform and peak reach pixel domain")
  $display("PASS tb_british_top checks=%0d notes=%0d windows=%0d",checks,events,windows);$finish;
 end
 initial begin #30000000;$fatal(1,"British top timeout");end
endmodule
