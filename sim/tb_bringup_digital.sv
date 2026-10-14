`timescale 1ns/1ps
`include "check.svh"
module tb_bringup_digital;
 reg clk=0,rst=1;always #10 clk=~clk;
 wire bck,ws,din,pa,dbg_bck,dbg_ws,dbg_din,dbg_pa;
 integer checks=0,edges=0,bits=0,ch=0,mirror_checks=0;
 realtime last_rise=0,period;
 bringup_digital #(.LOCK_N(32)) dut(
  .clk(clk),.rst(rst),.HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),
  .DBG_BCK(dbg_bck),.DBG_WS(dbg_ws),.DBG_DIN(dbg_din),.DBG_PA_EN(dbg_pa));
 always @(posedge clk)begin `CHECK(din===0 && pa===0,"diagnostic hard mute") end
 // Wait one precision step for continuous assignments to settle. Check
 // all source transitions, including reset assertions, at 1 ps resolution.
 always @(bck or ws or din or pa)begin
  #0.001;
  `CHECK({dbg_bck,dbg_ws,dbg_din,dbg_pa}==={bck,ws,din,pa},"GPIO mirrors all DAC signals")
  mirror_checks=mirror_checks+1;
 end
 always @(posedge bck)if(!dut.engine.audio_reset)begin
  `CHECK(ws==(ch==1),"diagnostic word framing")
  `CHECK(dbg_ws==(ch==1),"GPIO word framing")
  if(last_rise>0)begin
   period=$realtime-last_rise;
   `CHECK(period>651.02 && period<651.07,"1.536 MHz BCK")
  end
  last_rise=$realtime;edges=edges+1;
  if(bits==15)begin bits=0;ch=1-ch;end else bits=bits+1;
 end
 initial begin
  #100 rst=0;wait(edges==640);#3 rst=1;#1;
  `CHECK(din==0 && pa==0 && dbg_din==0 && dbg_pa==0,"reset hard mute on both sets")
  `CHECK(bck==1 && dbg_bck==1 && ws==0 && dbg_ws==0,"reset mirror levels")
  bits=0;ch=0;last_rise=0;#100 rst=0;wait(edges==704);
  `CHECK(mirror_checks>1400,"both BCK edges and WS/reset mirrored")
  $display("PASS tb_bringup_digital checks=%0d mirror_checks=%0d",checks,mirror_checks);$finish;
 end
 initial begin #10000000;$fatal(1,"diagnostic timeout");end
endmodule
