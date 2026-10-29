`timescale 1ns/1ps
`include "check.svh"
`include "touch_keyboard_fixture.svh"
module tb_ultrasonic_top;
 `include "../src/config/ui_layout.svh"
 reg clk=0,rst=1,echo=0,respond=1;always #10 clk=~clk;
 reg [15:0] pressed=0;reg [11:0] auxiliary=0;tri1 [2:0] scl,sda;wire [2:0] int_n;
 reg command_valid=0;reg [5:0] command=UI_NONE;
 integer checks=0,echo_width_us=725,frames=0,prior_volume=100;
 wire trig;
 keyboard_top #(.KEYPAD_BOOT_CYCLES(20),.KEYPAD_POLL_CYCLES(1600),.KEYPAD_I2C_HALF(4),.KEYPAD_TIMEOUT_CYCLES(100),.KEYPAD_RETRY_CYCLES(32),.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.LOCK_N(16),
  .MUTE(2),.FADE(2),.ATTACK(2),.DECAY(2),.SUSTAIN(32768),.RELEASE(2),
  .ULTRA_PERIOD_US(1000),.ULTRA_TIMEOUT_US(800),.ULTRA_LOST_MS(4),.ULTRA_SLEW_CYCLES(1229)) dut(
  .clk(clk),.rst(rst),.bt_rx(1'b1),.board_buttons_n(4'hf),.keypad_scl(scl),.keypad_sda(sda),.keypad_int_n(int_n),.ec11_a(3'b111),.ec11_b(3'b111),.ec11_sw_n(3'b111),
  .ultrasonic_echo(echo),.ultrasonic_trig(trig));
 touch_keyboard_fixture keyboard(rst,{20'd0,pressed},auxiliary,3'b111,scl,sda,int_n);
 always @(negedge trig)if(!rst && respond)begin
  #20000;echo=1;#(echo_width_us*1000);echo=0;
 end
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  `CHECK(!dut.underrun,"ultrasonic ownership never underruns audio")
  if(dut.frame_ce)frames=frames+1;
  if(dut.ultrasonic_enabled && !command_valid)
   `CHECK(dut.volume_percent<=prior_volume+1 && dut.volume_percent+1>=prior_volume,"auto gain changes at most one percent per tick")
  prior_volume=dut.volume_percent;
 end
 task cycles(input integer n);begin repeat(n)@(negedge dut.audio_clk);end endtask
 task act(input [6:0] action);begin
  @(negedge dut.audio_clk);command=action;command_valid=1;
  @(negedge dut.audio_clk);command_valid=0;cycles(3);
 end endtask
 task settle(input integer percent);integer deadline;begin
  deadline=frames+500;
  while(dut.volume_percent!=percent && frames<deadline)cycles(1280);
  `CHECK(dut.volume_percent==percent,"echo pin reaches expected effective volume")
  while(dut.sound.volume_control.gain!=(percent*256+50)/100 && frames<deadline)cycles(1280);
  `CHECK(dut.sound.volume_control.gain==(percent*256+50)/100,"existing PCM gain slew settles after target percent")
  cycles(100);
 end endtask
 initial begin
  force dut.ui_action_valid=command_valid;force dut.ui_action=command;
  #100;rst=0;wait(dut.input_ready && dut.keypad_online==7);cycles(100);
  `CHECK(!trig && !dut.ultrasonic_enabled && dut.volume_percent==100,"power-on manual defaults keep sensor off")
  act(UI_MODE);act(UI_ULTRA_OPEN);
  repeat(4)act(UI_MAX_DOWN);repeat(4)act(UI_MIN_UP);repeat(4)act(UI_SENS_UP);
  act(UI_ULTRA_TOGGLE);settle(50);
  `CHECK(dut.ultrasonic_result[11:0]==12'h125 && dut.ultrasonic_ui_state==2,"distance/status survive ref-to-audio atomic snapshot")
  `CHECK(dut.sound.volume_control.gain==128,"automatic 50 percent reaches existing audio multiplier")
  act(UI_MODE);pressed=1;wait(dut.gate);cycles(12800);
  `CHECK(dut.visual_notes==1 && dut.voice_held==1 && (^{dut.sound.output_sample})!==1'bx,"auto mode preserves one-key ownership")
  echo_width_us=290;settle(80);
  `CHECK(dut.sound.volume_control.gain==205 && dut.gate,"near gesture changes real master gain while note stays held")
  act(UI_VOLUME_DOWN);cycles(6000);`CHECK(dut.volume_percent==80,"manual volume ignored while sensor owns it")
  respond=0;settle(20);
  `CHECK(dut.ultrasonic_ui_state==4,"continuous missing echo reports lost and lower limit")
  act(UI_ULTRA_TOGGLE);cycles(3000);`CHECK(dut.volume_percent==20 && !trig,"disable retains volume and stops trigger")
  act(UI_VOLUME_UP);settle(25);`CHECK(dut.volume_percent==25 && dut.sound.volume_control.gain==64,"manual resumes from retained automatic value")
  pressed=0;wait(!dut.gate);cycles(1280*80);
  `CHECK(dut.voice_active==0 && dut.visual_sample==0,"release stays silent after ultrasonic-to-manual handover")
  $display("PASS tb_ultrasonic_top checks=%0d frames=%0d",checks,frames);$finish;
 end
 initial begin #50000000;$fatal(1,"ultrasonic top timeout");end
endmodule
