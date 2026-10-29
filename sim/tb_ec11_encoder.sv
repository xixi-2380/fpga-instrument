`timescale 1ns/1ps
`include "check.svh"
module tb_ec11_encoder;
 reg clk=0,rst=1,a=1,b=1,sw=1;always #5 clk=~clk;
 wire up,down,single_click,double_click;integer checks=0,ups=0,downs=0,singles=0,doubles=0,old;
 ec11_encoder #(.FILTER_CYCLES(2),.DEBOUNCE_MS(2),.DOUBLE_MS(40),.LONG_MS(80)) dut(
  clk,rst,1'b1,a,b,sw,up,down,single_click,double_click,1'b0,);
 always @(posedge clk)if(!rst)begin
  if(up)ups=ups+1;if(down)downs=downs+1;
  if(single_click)singles=singles+1;if(double_click)doubles=doubles+1;
  `CHECK(!(up && down) && !(single_click && double_click),"events are exclusive")
 end
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task ab(input [1:0] value);begin {a,b}=value;cycles(12);end endtask
 task forward;begin ab(1);ab(0);ab(2);ab(3);end endtask
 task backward;begin ab(2);ab(0);ab(1);ab(3);end endtask
 task click;begin sw=0;cycles(12);sw=1;cycles(12);end endtask
 initial begin
  #12;rst=0;cycles(10);forward();`CHECK(ups==1 && downs==0,"one clockwise event per full detent")
  backward();`CHECK(ups==1 && downs==1,"counterclockwise detent")
  ab(1);ab(3);ab(1);ab(0);ab(2);ab(3);
  `CHECK(ups==2 && downs==1,"quadrature bounce reversals cancel")
  old=ups+downs;ab(0);ab(3);`CHECK(ups+downs==old,"two-bit invalid jumps discard partial detent")
  ab(1);ab(0);ab(1);ab(3);`CHECK(ups+downs==old,"partial direction reversal has no phantom step")
  {a,b}=1;cycles(1);{a,b}=3;cycles(8);`CHECK(ups+downs==old,"sub-filter glitch is ignored")
  click();cycles(45);`CHECK(singles==1 && doubles==0,"single click waits through double-click window")
  click();click();cycles(45);`CHECK(singles==1 && doubles==1,"double click never also emits a single")
  sw=0;cycles(12);forward();sw=1;cycles(60);
  `CHECK(singles==1 && doubles==1 && ups==3,"turn while pressed still turns but suppresses click")
  sw=0;cycles(100);sw=1;cycles(60);`CHECK(singles==1 && doubles==1,"long hold has no click action")
  click();sw=0;cycles(12);backward();sw=1;cycles(60);
  `CHECK(singles==1 && doubles==1,"held rotation cancels a pending double gesture")
  click();sw=0;wait(dut.press);@(negedge clk);dut.click_ms=39;
  cycles(12);sw=1;cycles(60);
  `CHECK(singles==1 && doubles==2,"second press at timeout boundary cannot emit both single and double")
  rst=1;#1;`CHECK(!up && !down && !single_click && !double_click,"reset clears in-flight gestures")
  $display("PASS tb_ec11_encoder checks=%0d up=%0d down=%0d single=%0d double=%0d",checks,ups,downs,singles,doubles);$finish;
 end
 initial begin #100000;$fatal(1,"encoder timeout");end
endmodule
