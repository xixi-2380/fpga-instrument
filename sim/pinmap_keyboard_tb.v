`timescale 1ns/1ps
module tb_keyboard_pinmap;
 reg clk=0,aclk=0,rst=1;
 always #10 clk=~clk;
 always #8.138020833 aclk=~aclk;
 reg [15:0] pressed=0;
 // pads[0..3]: physical horizontal rows, top to bottom.
 // pads[4..7]: physical vertical columns, left to right.
 tri [7:0] pads;
 tri [3:0] port_rows,port_cols;
 wire bck,ws,din,pa,db,dw,dd,dp;
 integer checks=0,bits=0,word=0,nonzero=0,expected;
 `include "keypad_pad_wiring.svh"
 for(genvar r=0;r<4;r=r+1)begin: rows
  for(genvar c=0;c<4;c=c+1)begin: cols
   tranif1 contact(pads[r],pads[4+c],pressed[r*4+c]);
  end
 end
 keyboard_top #(.LCD_ENABLE(0),.BUTTON_DEBOUNCE_CYCLES(4),.SCORE_ENABLE(0),.LOCK_N(32),.SLOT_CYCLES(8),.SETTLE_CYCLES(4),.DEBOUNCE_SCANS(3),
  .MUTE(4),.FADE(4),.ATTACK(8),.DECAY(8),.SUSTAIN(32768),.RELEASE(16))
  dut(.clk(clk),.rst(rst),.board_buttons_n(4'hf),.key_row(port_rows),.key_col(port_cols),
      .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),.DBG_BCK(db),.DBG_WS(dw),.DBG_DIN(dd),.DBG_PA_EN(dp));
 // This is a physical-pin mapping test. Clock/reset behavior has its own TB.
 initial begin
  force dut.audio_clk=aclk;force dut.audio_reset=rst;
  force dut.pll1_reset=1'b1;force dut.pll2_reset=1'b1;
 end
 always @(posedge bck)if(!rst)begin
  word=((word<<1)|din)&65535;
  if(bits==15)begin if(word!=0)nonzero=nonzero+1;bits=0;word=0;end
  else bits=bits+1;
 end
 task settle;begin repeat(2560)@(posedge aclk);#1;end endtask
 initial begin
  #100 rst=0;wait(pa);settle;
  for(integer k=0;k<16;k=k+1)begin
   pressed=16'h1<<k;settle;
   expected=`PINMAP_TRANSPOSED ? ((k%4)*4+k/4) : k;
   if(!dut.gate || dut.last_key!=expected)$fatal(1,"physical key %0d selected %0d gate=%b",k,dut.last_key,dut.gate);
   checks=checks+1;
   pressed=0;settle;
   if(dut.gate)$fatal(1,"physical release %0d not recognized",k);
   checks=checks+1;
  end
  if(nonzero<10)$fatal(1,"no audio from physical pin model");
  checks=checks+1;
  pressed=16'h0013;settle;
  if(!dut.ghost || dut.gate)$fatal(1,"physical three-corner ghost not suppressed");
  checks=checks+1;
  $display("PASS tb_keyboard_pinmap checks=%0d transposed=%0d nonzero_words=%0d",checks,`PINMAP_TRANSPOSED,nonzero);
  $finish;
 end
 initial begin #5000000;$fatal(1,"physical keypad mapping timeout");end
endmodule
