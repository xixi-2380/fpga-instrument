`timescale 1ns/1ps
module tb_ultrasonic_cm_ui;
 reg clk=0,rst=1,fs=0;always #1 clk=~clk;
 reg[1279:0]data=0;reg[10:0]x=0,y=0;wire[23:0]rgb;wire od,oh,ov;
 rgb_ui_renderer dut(clk,rst,fs,1'b1,data,x,y,1'b1,1'b1,1'b1,rgb,od,oh,ov,513'd0,1'b0,146'd0,64'd0);
 `include "config/ui_language.svh"
 integer checks=0;
 task tick;begin @(negedge clk);end endtask
 task commit;begin fs=1;tick();fs=0;repeat(15)tick();end endtask
 task probe(input integer xx,yy,input integer count,input[319:0]want);begin
  x=xx;y=yy;repeat(15)tick();
  if(dut.text!==want || dut.len!==count)$fatal(1,"Unit/word label differs at%0d,%0d text=%h len=%0d expected=%h len=%0d",xx,yy,dut.text,dut.len,want,count);
  if(od && (^rgb===1'bx))$fatal(1,"Visible cm UI has unknown RGB");checks++;
 end endtask
 reg[325:0]word_value;
 initial begin
  repeat(3)tick();rst=0;data[20]=1;data[1166]=1;data[1165]=1;
  data[1161:1155]=5;data[1154:1148]=40;data[1147:1145]=2;data[1144:1133]=12'h010;commit();
  probe(100,196,8,"DEADBAND");
  for(integer n=1;n<=5;n++)begin
   data[1164:1162]=n;commit();probe(616,196,4,{8'(48+n)," CM"});
  end
  probe(616,268,6,"005 CM");probe(616,340,6,"040 CM");probe(600,380,6,"010 CM");
  data[1144:1133]=12'h400;commit();probe(600,380,6,"400 CM");
  data[1210]=1;commit();word_value=ui_word(TXT_DEADBAND,1'b1);
  if(word_value[325:320]!==4)$fatal(1,"Chinese neutral-band label must contain four glyphs");
  probe(100,196,4,word_value[319:0]);
  probe(616,196,4,"5 CM");probe(600,380,6,"400 CM");
  $display("PASS tb_ultrasonic_cm_ui checks=%0d label_en=DEADBAND label_zh_glyphs=4 distance_unit=CM",checks);$finish;
 end
 initial begin #100000;$fatal(1,"cm UI timeout");end
endmodule
