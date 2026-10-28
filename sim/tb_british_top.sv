`timescale 1ns/1ps
`include "check.svh"
`include "touch_keyboard_fixture.svh"
module tb_british_top;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [3:0] buttons=15;reg [15:0] pressed=0;reg [11:0] auxiliary=0;
 tri1 [2:0] scl,sda;wire [2:0] int_n;wire pa,bck,lrclk,din;
 integer checks=0,frames=0,events=0,tap_count=0,windows=0;reg [6:0] seen=0;
 wire [1206:0] displayed;
 keyboard_top #(.KEYPAD_BOOT_CYCLES(20),.KEYPAD_POLL_CYCLES(1600),.KEYPAD_I2C_HALF(4),.KEYPAD_TIMEOUT_CYCLES(100),.KEYPAD_RETRY_CYCLES(32),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.SCORE_ENABLE(0),.BUTTON_DEBOUNCE_CYCLES(2),.BUTTON_LONG_PRESS_CYCLES(128),
  .LOCK_N(16),
  .MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.RELEASE(2)) dut(
  .clk(clk),.rst(rst),.board_buttons_n(buttons),.keypad_scl(scl),.keypad_sda(sda),.keypad_int_n(int_n),.ec11_a(3'b111),.ec11_b(3'b111),.ec11_sw_n(3'b111),
  .MAX_BCLK(bck),.MAX_LRCLK(lrclk),.MAX_DIN(din),.MAX_SD_MODE());
 assign pa=dut.input_ready;
 assign displayed=dut.lcd_on.display_driver.pixel_status;
 touch_keyboard_fixture keyboard(rst,{20'd0,pressed},auxiliary,3'b111,scl,sda,int_n);
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  `CHECK(!dut.underrun,"all seven presets and large display CDC cannot underrun")
  if(dut.frame_ce)frames=frames+1;
  if(dut.note_valid && dut.note_ready && dut.note_on)begin seen[dut.event_timbre]=1;events=events+1;end
  if(dut.visual_sample_valid)begin
   `CHECK(dut.visual_sample===$signed(dut.sound.visual_sum>>>1),"display observes the average of actual post-volume left/right samples")
   tap_count=tap_count+1;
  end
  if(dut.lcd_on.display_driver.monitor.window_valid)windows=windows+1;
 end
 task more_frames(input integer n);integer target;begin target=frames+n;wait(frames>=target);#1;end endtask
 task toggle;begin buttons=14;repeat(256)@(negedge dut.audio_clk);buttons=15;repeat(10)@(negedge dut.audio_clk);end endtask
 task key(input integer n);begin auxiliary=12'b1<<n;more_frames(4);auxiliary=0;more_frames(4);end endtask
 initial begin
  #100 rst=0;wait(pa && dut.keypad_online==7);more_frames(4);
  for(integer t=0;t<7;t=t+1)begin
   toggle;more_frames(2);
   `CHECK(dut.menu_mode,"S0 enters parameter page")
   if(t!=0)key(1);
   `CHECK(dut.selected_timbre==t,"AUX next reaches all seven identities")
   key(9);`CHECK(dut.menu_mode && dut.ultrasonic_page,"AUX10 enters preserved ultrasonic page")
   key(11);`CHECK(dut.menu_mode && !dut.ultrasonic_page,"ultrasonic BACK returns to main settings")
   if(t==0)begin
    key(10);`CHECK(dut.more_open,"main AUX11 retains the library entry")
    key(11);`CHECK(!dut.more_open && dut.menu_mode,"library BACK returns to settings")
   end
   toggle;more_frames(2);`CHECK(!dut.menu_mode,"long S0 returns from settings to play mode")
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
  `CHECK(displayed[1132],"stereo output latency measurement reaches the extended UI snapshot")
  $display("PASS tb_british_top checks=%0d notes=%0d windows=%0d",checks,events,windows);$finish;
 end
 initial begin #30000000;$fatal(1,"British top timeout");end
endmodule
