`timescale 1ns/1ps
`include "check.svh"
`include "touch_keyboard_fixture.svh"
module tb_bluetooth_top;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [15:0] pressed=0;reg [11:0] auxiliary=0;tri1 [2:0] scl,sda;wire [2:0] int_n;
 reg ev=0,inh=0;reg [1:0] kind=0;reg [6:0] pitch=69,velocity=127;
 integer checks=0,frames=0,hi=0,lo=0,peak=0,value=0;
 // Explicit legacy-song fixture verifies takeover; production defaults to no autoplay.
 keyboard_top #(.KEYPAD_BOOT_CYCLES(20),.KEYPAD_POLL_CYCLES(1600),.KEYPAD_I2C_HALF(4),.KEYPAD_TIMEOUT_CYCLES(100),.KEYPAD_RETRY_CYCLES(32),.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.SCORE_ENABLE(1),
 .LOCK_N(16),.SCORE_BEAT_FRAMES(100),.BUTTON_DEBOUNCE_CYCLES(2),
 .MUTE(4),.FADE(4),.ATTACK(2),.DECAY(2),.SUSTAIN(32768),.RELEASE(2)) dut(
 .clk(clk),.rst(rst),.bt_rx(1'b1),.board_buttons_n(4'hf),.keypad_scl(scl),.keypad_sda(sda),.keypad_int_n(int_n),.ec11_a(3'b111),.ec11_b(3'b111),.ec11_sw_n(3'b111));
 touch_keyboard_fixture keyboard(rst,{20'd0,pressed},auxiliary,3'b111,scl,sda,int_n);
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  if(dut.frame_ce)frames=frames+1;
  `CHECK(!dut.underrun,"Bluetooth flush/render does not underrun")
  if(dut.visual_sample_valid)begin
   value=$signed(dut.visual_sample);if(value<0)value=-value;if(value>peak)peak=value;
  end
 end
 task more(input integer n);integer target;begin target=frames+n;wait(frames>=target);end endtask
 task event_send(input [1:0] k,input [6:0] vel);begin
  @(negedge dut.audio_clk);kind=k;velocity=vel;ev=1;
  wait(dut.bluetooth_on.ev_ready);@(posedge dut.audio_clk);#1;
  @(negedge dut.audio_clk);ev=0;
 end endtask
 initial begin
  force dut.bluetooth_on.ev_valid=ev;
  force dut.bluetooth_on.kind=kind;
  force dut.bluetooth_on.ident=7'd0;
  force dut.bluetooth_on.pitch=pitch;
  force dut.bluetooth_on.velocity=velocity;
  force dut.bt_inhibit=inh;
  #100 rst=0;wait(dut.input_ready && dut.keypad_online==7);more(4);
  `CHECK(dut.local_score_busy && !dut.ultrasonic_trig,"preloaded score and ultrasonic trigger off by default")
  pressed=16'h0200;inh=1;event_send(2,0);more(3);
  `CHECK(dut.score_cancelled && !dut.gate && dut.note_keys==0,"Bluetooth takes ownership and clears existing audio")
  event_send(1,127);more(80);peak=0;more(100);hi=peak;
  `CHECK(dut.gate && hi>0 && dut.sound.velocities[0]==256,"full velocity reaches real synth")
  event_send(1,32);more(80);peak=0;more(100);lo=peak;
  `CHECK(lo>0 && lo<hi/2 && lo>hi/8,"velocity changes actual PCM amplitude")
  event_send(0,0);more(5);
  `CHECK(!dut.gate,"Bluetooth Off reaches allocator")
  event_send(2,0);
  `CHECK(dut.voice_active==0 && dut.voice_held==0,"pause/stop flushes voices and sustain tails before acknowledgement")
  `CHECK(dut.sound.tx.latched_l==0 && dut.sound.tx.latched_r==0 && dut.MAX_DIN==0,"clear acknowledgement follows serial silence on both channels")
  more(3);
  inh=0;more(4);
  `CHECK(!dut.gate && dut.note_keys==0,"held manual key cannot resume on return")
  pressed=0;more(4);pressed=16'h0200;wait(dut.gate);more(4);
  `CHECK(dut.last_key==9 && !dut.local_score_busy,"fresh manual key resumes after release")
  `CHECK(dut.MAX_SD_MODE && dut.HP_BCK==0 && dut.PA_EN==0,"MAX clock enable and retired pads preserved")
  force dut.volume_percent=7'd0;more(270);
  inh=1;event_send(2,0);event_send(1,127);more(12);
  `CHECK(dut.sound.volume_control.gain==0 && dut.visual_sample==0,"Bluetooth clear and reattack cannot reset master mute")
  event_send(2,0);inh=0;release dut.volume_percent;
  $display("PASS tb_bluetooth_top checks=%0d high_peak=%0d low_peak=%0d",checks,hi,lo);$finish;
 end
 initial begin #20000000;$fatal(1,"Bluetooth top timeout");end
endmodule
