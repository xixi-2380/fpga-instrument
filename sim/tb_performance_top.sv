`timescale 1ns/1ps
module tb_performance_top;
 reg clk=0,rst=1;always #10 clk=~clk;
 reg [72:0] touch=0;reg upd=0;reg [53:0] keyboard={3'b111,3'b111,48'd0};
 reg takeover=0,clear=0;integer checks=0,ons=0,offs=0,manuals=0;
 wire frame;wire [31:0] held;
 keyboard_top #(.BT_ENABLE(0),.LCD_ENABLE(0),.TOUCH_ENABLE(1),.LOCK_N(16),.MUTE(1),.FADE(1),.ATTACK(2),.DECAY(2),.RELEASE(4)) dut(
 .clk(clk),.rst(rst),.board_buttons_n(4'hf),.keypad_int_n(3'b111),.ec11_a(3'b111),.ec11_b(3'b111),.ec11_sw_n(3'b111),.bt_rx(1'b1));
 // Only the touch gate is shortened in this integration fixture. All audio
 // clocks,32voice rendering,limiter and I2S retain production parameters.
 defparam dut.performance.GATE_FRAMES=16;
 assign frame=dut.frame_ce;assign held=dut.voice_held;
 task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"%s",why);end endtask
 task frames(input integer k);repeat(k)begin @(posedge dut.audio_clk);while(!frame)@(posedge dut.audio_clk);@(negedge dut.audio_clk);end endtask
 task touch_report(input bit down,input integer x,y);begin
  @(negedge dut.audio_clk);touch={~touch[72],~touch[71],16'd800,16'd480,1'b1,1'b0,down,down?4'd1:4'd0,16'(x),16'(y)};upd=1;
  @(negedge dut.audio_clk);upd=0;repeat(4)@(negedge dut.audio_clk);
 end endtask
 task tap(input integer x,y);begin touch_report(0,0,0);touch_report(1,x,y);touch_report(0,0,0);end endtask
 always @(posedge dut.audio_clk)if(!dut.audio_reset&&dut.note_valid&&dut.note_ready)begin
  check(!dut.take_bt,"no manual event during takeover");
  if(dut.note_id>=96)begin if(dut.note_on)ons++;else offs++;check(dut.manual_pitch>=60&&dut.manual_pitch<=86,"complete arbiter pitch payload");end
  else if(dut.note_on)manuals++;
 end
 initial begin
  force dut.touch_audio=touch;force dut.touch_audio_valid=1'b1;force dut.touch_update=upd;
  force dut.keypad_snapshot=keyboard;force dut.keypad_snapshot_valid=1'b1;
  force dut.bt_inhibit=takeover;force dut.bt_flush=clear;
  #100 rst=0;wait(dut.input_ready);frames(2);touch_report(0,0,0);touch_report(0,0,0);
  tap(500,40);check(dut.performance_active,"actual top touch opens page");
  keyboard[0]=1;frames(4);check(manuals==1,"physical key still playable on harp page");
  touch_report(1,112,260);touch_report(1,640,260);frames(8);check(ons==12&&$countones(held)==13,"twelve strings plus physical key");
  touch_report(0,0,0);frames(20);check($countones(held)==1&&offs==12,"all plucks off; physical key held independently");
  touch_report(1,656,390);frames(260);check(dut.manual_pitch_ratio==73562,"top live bend");
  touch_report(0,0,0);frames(260);check(dut.manual_pitch_ratio==65536,"top release recentres");
  keyboard[0]=0;frames(10);check(held==0,"physical release under touch UI");
  tap(740,128);check(dut.chorus_enabled,"top chorus toggled");tap(710,40);check(!dut.performance_active&&dut.chorus_enabled,"effect survives page exit");
  tap(500,40);tap(740,128);check(!dut.chorus_enabled,"top effect disabled");tap(710,40);tap(500,40);check(!dut.chorus_enabled,"effect does not re-enable on navigation");
  tap(112,260);frames(2);takeover=1;clear=1;frames(4);check(held==0&&!dut.harp_valid,"BT flush cancels every touch note");
  takeover=0;clear=0;touch_report(0,0,0);frames(4);check(!dut.underrun,"production top no underrun");
  $display("PASS tb_performance_top checks=%0d plucks=%0d releases=%0d physical=%0d",checks,ons,offs,manuals);$finish;
 end
 initial begin #100000000;$fatal(1,"performance top timeout");end
endmodule
