`timescale 1ns/1ps
`include "check.svh"
module tb_max98357_startup;
 reg clk=0,rst=1;always #10 clk=~clk;
 wire bck,lrclk,din,sd;wire [7:0] old_audio;tri [3:0] columns;
 integer checks=0,frames=0;realtime enabled_at=0,ready_at=0;
 keyboard_top #(.LCD_ENABLE(0),.TOUCH_ENABLE(0),.SCORE_ENABLE(0),.LOCK_N(32)) dut(
  .clk(clk),.rst(rst),.key_row(4'hf),.key_col(columns),
  .MAX_BCLK(bck),.MAX_LRCLK(lrclk),.MAX_DIN(din),.MAX_SD_MODE(sd),
  .HP_BCK(old_audio[0]),.HP_WS(old_audio[1]),.HP_DIN(old_audio[2]),.PA_EN(old_audio[3]),
  .DBG_BCK(old_audio[4]),.DBG_WS(old_audio[5]),.DBG_DIN(old_audio[6]),.DBG_PA_EN(old_audio[7]));
 always @(posedge dut.audio_clk)if(!dut.audio_reset)begin
  `CHECK(old_audio==0,"board DAC, PA and old debug pads are disabled")
  `CHECK(dut.touch_scl===1'bz && dut.touch_sda===1'bz && dut.touch_int===1'bz && dut.touch_rst_n===1'bz,
    "touch-disabled default remains high impedance")
  if(dut.frame_ce)frames=frames+1;
  if(!dut.input_ready)begin `CHECK(din==0,"device turn-on occurs during production digital silence") end
 end
 always @(posedge sd)if(!rst)begin
  enabled_at=$realtime;
  `CHECK(frames==2 && !dut.input_ready,"SD_MODE enables only after two valid clock frame boundaries")
 end
 initial begin
  #100 rst=0;wait(sd);wait(dut.input_ready);ready_at=$realtime;
  `CHECK($realtime-enabled_at>7500000,"production mute leaves over 7.5ms for MAX98357A turn-on")
  repeat(100)@(posedge bck);
  `CHECK(sd && !din && old_audio==0,"idle maintains valid I2S clock and zero audio")
  #3;rst=1;#1;
  `CHECK(!sd && !din && old_audio==0,"reset immediately shuts down external amplifier")
  $display("MAX_STARTUP_METRICS enable_to_audio_ready_us=%0.3f",(ready_at-enabled_at)/1000.0);
  $display("PASS tb_max98357_startup checks=%0d",checks);$finish;
 end
 initial begin #20000000;$fatal(1,"MAX98357 startup timeout");end
endmodule
