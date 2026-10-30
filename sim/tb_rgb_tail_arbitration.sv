`timescale 1ns/1ps
// Natural tail continues owning the synth; no custom mapping/recorder exists.
module tb_rgb_tail_arbitration;
 reg clk=0,rst=1,tail=0,manual_valid=0;always #10 clk=~clk;
 integer checks=0;
 keyboard_top #(.BT_ENABLE(0),.LCD_ENABLE(0),.TOUCH_ENABLE(0),.LOCK_N(16),.MUTE(1),.FADE(1)) dut(
 .clk(clk),.rst(rst),.bt_rx(1'b1),.ultrasonic_echo(1'b0),.board_buttons_n(4'hf),
 .keypad_int_n(3'b111),.ec11_a(3'b111),.ec11_b(3'b111),.ec11_sw_n(3'b111),.flash_miso(1'b1));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 initial begin
  force dut.bt_tail_pending=tail;force dut.key_valid=manual_valid;
  #100;rst=0;wait(dut.input_ready);repeat(10)@(negedge dut.audio_clk);
  check(!dut.take_bt,"manual source available initially");
  manual_valid=1;repeat(2)@(negedge dut.audio_clk);
  check(dut.note_valid,"manual event enters original synth path");
  tail=1;repeat(3)@(negedge dut.audio_clk);
  check(dut.take_bt && !dut.note_valid,"natural tail excludes new manual events");
  check(!dut.key_events.enabled,"keyboard onset adapter inhibited during tail");
  tail=0;manual_valid=0;repeat(3)@(negedge dut.audio_clk);
  check(!dut.take_bt && dut.key_events.enabled,"tail completion releases original manual adapter");
  $display("PASS tb_rgb_tail_arbitration checks=%0d",checks);$finish;
 end
 initial begin #5000000;$fatal(1,"tail ownership timeout");end
endmodule
