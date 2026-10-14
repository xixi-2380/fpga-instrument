`timescale 1ns/1ps
`include "passive_matrix_model.svh"
module tb_keyboard_netlist;
 reg clk=0,aclk=0,rst=1;
 always #10 clk=~clk;
 always #8.138020833 aclk=~aclk;
 reg [15:0] pressed=0;
 tri [3:0] cols;
 wire [3:0] selected,rows;
 wire bck,ws,din,pa,db,dw,dd,dp;
 integer bits=0,ch=0,word=0,frames=0,nonzero=0,checks=0;
 for(genvar k=0;k<4;k=k+1)assign selected[k]=(cols[k]===1'b0);
 passive_matrix_model switches(pressed,selected,rows);
 keyboard_top dut(.clk(clk),.rst(rst),.key_row(rows),.key_col(cols),
  .HP_BCK(bck),.HP_WS(ws),.HP_DIN(din),.PA_EN(pa),
  .DBG_BCK(db),.DBG_WS(dw),.DBG_DIN(dd),.DBG_PA_EN(dp));
 // Isolate existing synthesized digital logic from PLL simulation cost.
 // This test does not validate PLL lock or analog electrical behavior.
 initial begin
  force dut.audio_clk=aclk;
  force dut.audio_reset=rst;
  force dut.pll1_reset=1'b1;
  force dut.pll2_reset=1'b1;
 end
 always @(posedge bck)if(!rst)begin
  if(ws!==(ch==1))$fatal(1,"Netlist framing failure");
  checks=checks+1;word=((word<<1)|din)&65535;
  if(bits==15)begin
   if(word!=0)nonzero=nonzero+1;
   if(ch==1)frames=frames+1;
   ch=1-ch;word=0;bits=0;
  end else bits=bits+1;
 end
 initial begin
  #100 rst=0;
  wait(frames==20);pressed=16'h0200;
  #4000000;
  $display("NETLIST matrix keys=%h cols=%b rows=%b",dut.core.keys,cols,rows);
  if(dut.core.keys!==16'h0200)$fatal(1,"Synthesized scanner did not recognize A4");
  wait(pa===1'b1);wait(nonzero>=32);
  $display("NETLIST audio frames=%0d nonzero_words=%0d",frames,nonzero);
  pressed=0;#4000000;
  if(dut.core.keys!==16'h0000)$fatal(1,"Synthesized scanner did not release A4");
  $display("PASS tb_keyboard_netlist checks=%0d",checks);$finish;
 end
 initial begin #20000000;$fatal(1,"Netlist audio timeout");end
endmodule
