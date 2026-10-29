`timescale 1ns/1ps
`include "touch_keyboard_fixture.svh"
module tb_pcb_top;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [3:0] buttons=15;reg [2:0] a=7,b=7,sw=7;reg [35:0] pressed=0;reg [11:0] auxiliary=0;
 tri1 [2:0] scl,sda;wire [2:0] intr;reg av=0;reg [5:0] action=63;
 integer checks=0,frames=0,old_volume,old_echo,serial_checks=0;
 keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.TOUCH_UI_ENABLE(0),.LOCK_N(16),
 .MUTE(2),.FADE(2),.ATTACK(2),.DECAY(2),.RELEASE(1200),.SUSTAIN(32768),
 .BUTTON_DEBOUNCE_CYCLES(4),.BUTTON_LONG_PRESS_CYCLES(32),
 .KEYPAD_BOOT_CYCLES(20),.KEYPAD_POLL_CYCLES(1600),.KEYPAD_I2C_HALF(4),.KEYPAD_TIMEOUT_CYCLES(100),.KEYPAD_RETRY_CYCLES(32),
 .EC11_MS_CYCLES(8),.EC11_FILTER_CYCLES(2),.EC11_DEBOUNCE_MS(2),.EC11_DOUBLE_MS(12),.EC11_LONG_MS(30)) dut(
 .clk(clk),.rst(rst),.bt_rx(1'b1),.ultrasonic_echo(1'b0),.board_buttons_n(buttons),
 .keypad_scl(scl),.keypad_sda(sda),.keypad_int_n(intr),.ec11_a(a),.ec11_b(b),.ec11_sw_n(sw),.flash_miso(1'b1));
 touch_keyboard_fixture keyboard(rst,pressed,auxiliary,3'b111,scl,sda,intr);
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task cycles(input integer n);repeat(n)@(negedge dut.audio_clk);endtask
 task act(input [5:0] code);begin @(negedge dut.audio_clk);action=code;av=1;cycles(1);av=0;cycles(30);end endtask
 task short_button(input integer which);begin buttons[which]=0;cycles(16);buttons[which]=1;cycles(16);end endtask
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  if(dut.frame_ce)frames++;
  if(dut.pcb_page)begin
   check(dut.pcb_muted && dut.sound.frame_l==0 && dut.sound.frame_r==0,"debug opens only after both final audio frames are zero");
   check(!dut.underrun,"debug cannot underrun the audio engine");
   if(dut.sound.fall_ce)begin #1;check(!dut.MAX_DIN,"actual I2S data remains zero in the silent page");serial_checks++;end
  end
 end
 initial begin
  force dut.touch_action_valid=av;force dut.touch_action=action;
  #100 rst=0;wait(dut.input_ready && dut.keypad_data_valid==7);cycles(100);
  pressed=1;wait(dut.gate);wait(dut.visual_sample!=0);
  buttons[0]=0;cycles(70);buttons[0]=1;cycles(20);check(dut.menu_mode,"original S0 hold opens settings");
  act(42);check(dut.pcb_mute && !dut.pcb_page,"entry starts the original gradual volume ramp");
  wait(dut.pcb_page);check(dut.voice_active!=0,"mute is tested with a real nonzero release tail still running");
  old_volume=dut.volume_percent;short_button(1);check(dut.volume_percent==old_volume-5,"S1 keeps volume decrement while debug is open");
  short_button(2);check(dut.volume_percent==old_volume,"S2 keeps volume increment while debug is open");
  short_button(3);check(dut.effect_mask==1,"S3 keeps current effect toggle while debug is open");
  old_echo=dut.echo_time_ms;a[0]=0;cycles(12);b[0]=0;cycles(12);a[0]=1;cycles(12);b[0]=1;cycles(30);
  check(dut.echo_time_ms==old_echo+10 && dut.keypad_online==7,"encoder detent changes echo without changing any PCB online bit");
  act(45);act(54);act(57);wait(!dut.pcb_controls.pending);cycles(50);
  check(dut.keypad_applied[3:0]==3 && dut.keypad_applied[135:132]==2,"real command CDC applies only the selected board");
  check(dut.keypad_observed[3:0]==3,"actual I2C readback crosses back to UI");
  act(43);check(!dut.pcb_page && !dut.pcb_mute && dut.menu_mode,"touch return restores settings and user volume");
  buttons[0]=0;cycles(70);buttons[0]=1;cycles(20);check(!dut.menu_mode,"S0 retains its original menu exit");
  check(serial_checks>0,"complete serial output was observed during mute");
  $display("PASS tb_pcb_top checks=%0d frames=%0d serial_checks=%0d",checks,frames,serial_checks);$finish;
 end
 initial begin #40000000;$fatal(1,"PCB top timeout page=%b pending=%b",dut.pcb_page,dut.pcb_controls.pending);end
endmodule
