`timescale 1ns/1ps
module tb_pcb_config_deadline;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [159:0] control=0;integer checks=0;
 keyboard_top #(.BT_ENABLE(0),.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.LOCK_N(16),
 .MUTE(1),.FADE(1),.KEYPAD_BOOT_CYCLES(1000000),.PCB_COMMAND_TIMEOUT_CYCLES(64)) dut(
 .clk(clk),.rst(rst),.bt_rx(1'b1),.board_buttons_n(4'hf),.keypad_int_n(3'b111),
 .ec11_a(3'b111),.ec11_b(3'b111),.ec11_sw_n(3'b111),.ultrasonic_echo(1'b0),.flash_miso(1'b1));
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 initial begin
  #100 rst=0;wait(!dut.ultrasonic_ref_reset);
  force dut.pcb_ref_control=control;force dut.pcb_control_valid=1'b1;
  @(negedge clk);control[143:12]={{16{8'd4}},4'd3};control[11:4]=1;
  wait(dut.queued);wait(dut.command_timeout==63);@(negedge clk);
  force dut.touch_keyboards[0].reader.state=4'd5;#1;
  check(dut.keypad_cfg_ready[0] && !dut.keypad_cfg_valid[0],"ready on the deadline cannot admit an expired command");
  @(posedge clk);#1;
  check(dut.command_ack==1 && dut.command_result==8'h31 && !dut.inflight,"timeout acknowledgement is final and has no in-flight writer");
  check(!dut.touch_keyboards[0].reader.applying,"expired request has not changed the keyboard configuration");
  @(negedge clk);control[11:4]=2;wait(dut.inflight);#1;
  check(dut.touch_keyboards[0].reader.applying,"a fresh request is accepted before its own deadline");
  $display("PASS tb_pcb_config_deadline checks=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"configuration deadline test timeout");end
endmodule
