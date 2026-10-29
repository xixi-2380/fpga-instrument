`timescale 1ns/1ps
module tb_effect_cfg_replay;
 reg clk=0,rst=1;always #10 clk=~clk;
 integer checks=0;reg [73:0] before_cfg;reg [50:0] before_curve;
 keyboard_top #(.BT_ENABLE(0),.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.LOCK_N(16),.MUTE(1),.FADE(1)) dut(
 .clk(clk),.rst(rst),.bt_rx(1'b1),.board_buttons_n(4'hf),.keypad_int_n(3'b111),
 .ec11_a(3'b111),.ec11_b(3'b111),.ec11_sw_n(3'b111),.ultrasonic_echo(1'b0),.flash_miso(1'b1));
 task cycles(input integer n);repeat(n)@(negedge dut.audio_clk);endtask
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 wire [73:0] left_cfg={dut.sound.effect.echo_samples,dut.sound.effect.echo_target,dut.sound.effect.room_target,dut.sound.effect.depth_target,dut.sound.effect.phase_step};
 wire [73:0] right_cfg={dut.sound.stereo_on.right_effect.echo_samples,dut.sound.stereo_on.right_effect.echo_target,dut.sound.stereo_on.right_effect.room_target,dut.sound.stereo_on.right_effect.depth_target,dut.sound.stereo_on.right_effect.phase_step};
 initial begin
  #100 rst=0;wait(dut.input_ready);cycles(20);
  force dut.encoder_up=3'b111;cycles(1);release dut.encoder_up;cycles(20);
  check(dut.echo_time_ms==160 && dut.room_percent==26 && dut.depth_percent==51,"all three encoders supply nondefault parameters");
  check(dut.sound.effect.echo_samples==7680 && left_cfg==right_cfg,"both effect banks accept the selected values");
  force dut.timbre_buttons.echo_time_ms=11'd2000;force dut.timbre_buttons.tremolo_rate_hz=5'd20;cycles(30);
  check(dut.sound.release_curve[50:34]==96000 && dut.sound.effect.phase_step==1789570,"maximum sustain and20Hz parameters reach the real top");
  before_curve=dut.sound.release_curve;before_cfg=left_cfg;force dut.bt_flush=1'b1;cycles(6);
  check(dut.sound.engine_reset,"the real synthesis soft reset was exercised");
  release dut.bt_flush;cycles(24);
  $display("REPLAY before=%h after_left=%h after_right=%h",before_cfg,left_cfg,right_cfg);
  check(left_cfg==before_cfg && right_cfg==before_cfg,"nondefault left/right effect parameters survive a Bluetooth source flush");
  check(dut.sound.release_curve==before_curve,"the full17-bit2s release curve is restored after a real Bluetooth flush");
  $display("PASS tb_effect_cfg_replay checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"effect configuration replay timeout");end
endmodule
